// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

/// Unique name of the periodic job at the operating system.
const String kBackgroundSyncJobName =
    'dev.erikengler.campuskoethen.background-sync';

/// The period of the job. Android's WorkManager does not run periodic work
/// more often than every 15 minutes.
const Duration kBackgroundSyncPeriod = Duration(minutes: 15);

/// A run starts within the last [kBackgroundSyncFlex] of each period, so
/// between 10 and 15 minutes after the previous one. The operating system may
/// delay it further (battery saver, Doze, iOS's own budget); that is not under
/// the app's control.
const Duration kBackgroundSyncFlex = Duration(minutes: 5);

/// What the platform job service has to offer, in the two calls that matter.
abstract interface class BackgroundJobPlatform {
  Future<void> registerPeriodic();
  Future<void> cancel();
}

/// Keeps the periodic job registered exactly when it is wanted.
class BackgroundSyncScheduler {
  BackgroundSyncScheduler(this._platform);

  final BackgroundJobPlatform _platform;

  /// Registers or cancels the job. Never throws: a platform without background
  /// execution, or a refusal, must not break the app's start.
  Future<void> apply({required bool wanted}) async {
    try {
      if (wanted) {
        await _platform.registerPeriodic();
      } else {
        await _platform.cancel();
      }
    } catch (error) {
      assert(() {
        debugPrint('background sync: scheduling failed (${error.runtimeType})');
        return true;
      }());
    }
  }
}

/// [BackgroundJobPlatform] on the `workmanager` plugin (Android WorkManager,
/// iOS BGTaskScheduler).
class WorkmanagerJobPlatform implements BackgroundJobPlatform {
  WorkmanagerJobPlatform(this._dispatcher);

  /// The top-level function the system calls to start a run.
  final Function _dispatcher;

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await Workmanager().initialize(_dispatcher);
    _initialized = true;
  }

  @override
  Future<void> registerPeriodic() async {
    await _ensureInitialized();
    await Workmanager().registerPeriodicTask(
      kBackgroundSyncJobName,
      kBackgroundSyncJobName,
      frequency: kBackgroundSyncPeriod,
      flexInterval: kBackgroundSyncFlex,
      // `update`, not `keep`: a changed period must take effect on an
      // installation that already has the job.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  @override
  Future<void> cancel() async {
    await _ensureInitialized();
    await Workmanager().cancelByUniqueName(kBackgroundSyncJobName);
  }
}
