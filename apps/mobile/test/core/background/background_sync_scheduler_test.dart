// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/background/background_sync_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform implements BackgroundJobPlatform {
  final List<String> calls = <String>[];
  Object? failure;

  @override
  Future<void> registerPeriodic() async {
    calls.add('register');
    if (failure != null) throw failure!;
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    if (failure != null) throw failure!;
  }
}

void main() {
  test('registers the job when it is wanted and cancels it when not', () async {
    final _Platform platform = _Platform();
    final BackgroundSyncScheduler scheduler = BackgroundSyncScheduler(platform);

    await scheduler.apply(wanted: true);
    await scheduler.apply(wanted: false);

    expect(platform.calls, <String>['register', 'cancel']);
  });

  test('a platform that refuses never breaks the caller', () async {
    final _Platform platform = _Platform()..failure = StateError('no');

    await BackgroundSyncScheduler(platform).apply(wanted: true);
    await BackgroundSyncScheduler(platform).apply(wanted: false);

    expect(platform.calls, <String>['register', 'cancel']);
  });

  test('a run starts 10 to 15 minutes after the previous one', () {
    expect(
      kBackgroundSyncPeriod - kBackgroundSyncFlex,
      const Duration(minutes: 10),
    );
    expect(kBackgroundSyncPeriod, const Duration(minutes: 15));
  });
}
