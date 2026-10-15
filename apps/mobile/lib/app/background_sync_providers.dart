// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/background/background_sync_scheduler.dart';
import '../core/background/background_sync_settings.dart';
import '../core/prefs/settings_controller.dart';
import '../features/mail/application/mail_account_controller.dart';
import '../features/moodle/application/moodle_account_controller.dart';
import '../features/moodle/domain/moodle_account.dart';
import '../features/notifications/application/notification_settings_controller.dart';
import 'background_sync_entrypoint.dart';

/// The reader's switch for the periodic background sync.
class BackgroundSyncEnabled extends Notifier<bool> {
  @override
  bool build() =>
      BackgroundSyncSettings(ref.watch(keyValueStoreProvider)).enabled;

  Future<void> set(bool value) async {
    state = value;
    await BackgroundSyncSettings(
      ref.read(keyValueStoreProvider),
    ).setEnabled(value);
  }
}

final NotifierProvider<BackgroundSyncEnabled, bool>
backgroundSyncEnabledProvider = NotifierProvider<BackgroundSyncEnabled, bool>(
  BackgroundSyncEnabled.new,
);

/// Whether a periodic job is worth having: the switch is on and there is
/// something for it to do. `null` while the connected accounts are still being
/// restored: deciding then would cancel the job on every app start.
final Provider<bool?> backgroundSyncWantedProvider = Provider<bool?>((Ref ref) {
  final mail = ref.watch(mailAccountControllerProvider);
  final AsyncValue<MoodleAccount?> moodle = ref.watch(
    moodleAccountControllerProvider,
  );
  if (mail.isLoading || moodle.isLoading) return null;
  if (!ref.watch(backgroundSyncEnabledProvider)) return false;
  return (mail.value?.isSignedIn ?? false) ||
      moodle.value != null ||
      ref.watch(notificationSettingsProvider).optedIn;
});

final Provider<BackgroundSyncScheduler> backgroundSyncSchedulerProvider =
    Provider<BackgroundSyncScheduler>((Ref ref) {
      final bool supported =
          !kIsWeb &&
          (Platform.isAndroid || Platform.isIOS) &&
          !Platform.environment.containsKey('FLUTTER_TEST');
      return BackgroundSyncScheduler(
        supported
            ? WorkmanagerJobPlatform(backgroundSyncDispatcher)
            : const _NoBackgroundJobs(),
      );
    });

/// Desktop, web and tests: no background execution to register.
class _NoBackgroundJobs implements BackgroundJobPlatform {
  const _NoBackgroundJobs();

  @override
  Future<void> registerPeriodic() async {}

  @override
  Future<void> cancel() async {}
}
