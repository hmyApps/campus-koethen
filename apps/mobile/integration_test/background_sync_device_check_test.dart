// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/background_sync_entrypoint.dart';
import 'package:campus_koethen/core/background/background_sync_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Manual device check for the background sync (ADR-0002), run on a device or
/// emulator:
///
/// `flutter test integration_test/background_sync_device_check_test.dart
///   -d DEVICE --dart-define=API_BASE_URL=https://…`
///
/// It starts exactly the code a WorkManager run starts, in this process, with
/// the app's real stores. It proves that the headless pipeline (plugins,
/// encrypted stores, notification plugin, planning) runs through on the
/// device without throwing. What it cannot prove is when the operating system
/// decides to start a run; that is observed by hand.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a headless run completes on this device', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      await runBackgroundSyncOnce().timeout(const Duration(minutes: 3));
    });
  });

  testWidgets('the periodic job can be registered and cancelled', (
    WidgetTester tester,
  ) async {
    final WorkmanagerJobPlatform platform = WorkmanagerJobPlatform(
      backgroundSyncDispatcher,
    );
    await tester.runAsync(() async {
      await platform.registerPeriodic();
      await platform.cancel();
    });
  });
}
