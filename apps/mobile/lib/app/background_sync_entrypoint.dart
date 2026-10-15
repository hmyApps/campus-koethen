// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';

import '../core/background/background_sync_runner.dart';
import '../core/background/background_sync_settings.dart';
import '../core/background/foreground_bridge.dart';
import '../core/prefs/settings_controller.dart';
import 'app_bootstrap.dart';
import 'background_sync_steps.dart';

/// The function the operating system starts for a background run.
///
/// Runs in its own isolate, usually in a process nobody else is using.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await runBackgroundSyncOnce();
    // Always "success": a failed run is not retried sooner. The next period is
    // at most fifteen minutes away, and a retry loop only costs battery.
    return true;
  });
}

/// One background run, wherever it was started.
///
/// If the app's isolate is alive in this process the run is handed to it: the
/// encrypted caches must not be opened a second time. Otherwise this isolate
/// opens them itself, runs and closes them again.
Future<void> runBackgroundSyncOnce() async {
  try {
    await ensureHeadlessLocaleData();
    final DelegatedRun delegated = await ForegroundBridge.delegate();
    if (delegated != DelegatedRun.noForeground) return;

    final ProviderContainer container = ProviderContainer(
      overrides: await createAppOverrides(),
    );
    try {
      await performBackgroundSync(container, ownsNotifications: true);
    } finally {
      container.dispose();
      try {
        await Hive.close();
      } catch (_) {}
    }
  } catch (_) {
    // Nothing to report to: the system only needs the run to end.
  }
}

/// Date symbols for both app languages.
///
/// The app's widgets load them as a side effect of their localisation
/// delegates; a background run has no widgets, and the reminder texts format
/// times and dates.
Future<void> ensureHeadlessLocaleData() async {
  await initializeDateFormatting('de');
  await initializeDateFormatting('en');
}

/// Runs every step against [container], unless the reader switched the
/// background sync off.
Future<BackgroundSyncResult?> performBackgroundSync(
  ProviderContainer container, {
  required bool ownsNotifications,
}) async {
  if (!BackgroundSyncSettings(container.read(keyValueStoreProvider)).enabled) {
    return null;
  }
  final BackgroundSyncResult result = await BackgroundSyncRunner(
    steps: BackgroundSyncSteps(
      container,
      ownsNotifications: ownsNotifications,
    ).build(),
  ).run();
  assert(() {
    debugPrint(result.toString());
    return true;
  }());
  return result;
}
