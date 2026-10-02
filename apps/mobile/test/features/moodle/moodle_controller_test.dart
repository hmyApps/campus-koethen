// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/moodle/application/moodle_account_controller.dart';
import 'package:campus_koethen/features/moodle/application/moodle_controller.dart';
import 'package:campus_koethen/features/moodle/application/moodle_providers.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_cache.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_course.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_moodle.dart';

const MoodleToken _token = MoodleToken(
  value: 'tok',
  userId: 7,
  username: 'demo',
);

ProviderContainer _container({
  required FakeMoodleApiClient api,
  required InMemoryMoodleTokenStore tokens,
  required InMemoryMoodleCacheStore cache,
  required MutableClock clock,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      moodleApiClientProvider.overrideWithValue(api),
      moodleTokenStoreProvider.overrideWithValue(tokens),
      moodleCacheStoreProvider.overrideWithValue(cache),
      moodleClockProvider.overrideWithValue(clock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

MoodleCourse course(int id) =>
    MoodleCourse(id: id, fullName: 'Beispielkurs $id');
MoodleDeadline deadline(int id) => MoodleDeadline(
  id: id,
  title: 'D$id',
  dueAt: DateTime.fromMillisecondsSinceEpoch(1704672000 * 1000),
);

void main() {
  final DateTime t0 = DateTime.utc(2026, 7, 26, 12);

  group('account', () {
    test('starts disconnected when the token store is empty', () async {
      final c = _container(
        api: FakeMoodleApiClient(),
        tokens: InMemoryMoodleTokenStore(),
        cache: InMemoryMoodleCacheStore(),
        clock: MutableClock(t0),
      );
      final MoodleAccount? a = await c.read(
        moodleAccountControllerProvider.future,
      );
      expect(a, isNull);
    });

    test('restores a stored account without exposing the token', () async {
      final c = _container(
        api: FakeMoodleApiClient(),
        tokens: InMemoryMoodleTokenStore()..token = _token,
        cache: InMemoryMoodleCacheStore(),
        clock: MutableClock(t0),
      );
      final MoodleAccount? a = await c.read(
        moodleAccountControllerProvider.future,
      );
      expect(a, isNotNull);
      expect(a!.username, 'demo');
      expect(a.toString().contains('tok'), isFalse);
    });

    test('disconnect wipes token and cache', () async {
      final tokens = InMemoryMoodleTokenStore()..token = _token;
      final cache = InMemoryMoodleCacheStore()
        ..courses = <MoodleCourse>[course(1)];
      final c = _container(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      );
      await c.read(moodleAccountControllerProvider.future);

      await c.read(moodleAccountControllerProvider.notifier).disconnect();

      expect(tokens.token, isNull);
      expect(cache.clears, greaterThanOrEqualTo(1));
      expect(c.read(moodleAccountControllerProvider).value, isNull);
    });

    test(
      'failed token deletion still attempts the cache wipe and stays connected',
      () async {
        final tokens = InMemoryMoodleTokenStore()
          ..token = _token
          ..clearError = const MoodleFailure(
            MoodleFailureKind.secureStorageUnavailable,
          );
        final cache = InMemoryMoodleCacheStore()
          ..courses = <MoodleCourse>[course(1)];
        final c = _container(
          api: FakeMoodleApiClient(),
          tokens: tokens,
          cache: cache,
          clock: MutableClock(t0),
        );
        await c.read(moodleAccountControllerProvider.future);

        await expectLater(
          c.read(moodleAccountControllerProvider.notifier).disconnect(),
          throwsA(
            const MoodleFailure(MoodleFailureKind.secureStorageUnavailable),
          ),
        );

        expect(cache.clears, 1);
        expect(cache.courses, isNull);
        expect(c.read(moodleAccountControllerProvider).value, isNotNull);
      },
    );

    test('failed cache wipe keeps the connected UI state', () async {
      final tokens = InMemoryMoodleTokenStore()..token = _token;
      final cache = InMemoryMoodleCacheStore()
        ..courses = <MoodleCourse>[course(1)]
        ..clearError = const MoodleFailure(MoodleFailureKind.cacheUnavailable);
      final c = _container(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      );
      await c.read(moodleAccountControllerProvider.future);

      await expectLater(
        c.read(moodleAccountControllerProvider.notifier).disconnect(),
        throwsA(const MoodleFailure(MoodleFailureKind.cacheUnavailable)),
      );

      expect(tokens.clears, 1);
      expect(cache.courses, isNotNull);
      expect(c.read(moodleAccountControllerProvider).value, isNotNull);
    });
  });

  group('sync policy', () {
    Future<ProviderContainer> connected({
      required FakeMoodleApiClient api,
      required InMemoryMoodleCacheStore cache,
      required MutableClock clock,
    }) async {
      final tokens = InMemoryMoodleTokenStore()..token = _token;
      final c = _container(
        api: api,
        tokens: tokens,
        cache: cache,
        clock: clock,
      );
      await c.read(moodleAccountControllerProvider.future);
      c.listen(moodleControllerProvider, (_, _) {});
      await c.read(moodleControllerProvider.future);
      return c;
    }

    test('first open without a cache syncs once', () async {
      final api = FakeMoodleApiClient()
        ..courses = <MoodleCourse>[course(1)]
        ..deadlines = <MoodleDeadline>[deadline(9)];
      final cache = InMemoryMoodleCacheStore();
      final c = await connected(
        api: api,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(moodleControllerProvider.notifier).maybeAutoSync();

      expect(api.courseCalls, 1);
      expect(cache.courses, hasLength(1));
      final MoodleOverviewState s = c
          .read(moodleControllerProvider)
          .requireValue;
      expect(s.courses, hasLength(1));
      expect(s.deadlines, hasLength(1));
    });

    test(
      'an attempt younger than one hour prevents an automatic call',
      () async {
        final api = FakeMoodleApiClient()..courses = <MoodleCourse>[course(1)];
        final cache = InMemoryMoodleCacheStore()
          ..marks = MoodleSyncMarks(
            lastAttempt: t0.subtract(const Duration(minutes: 59)),
          );
        final c = await connected(
          api: api,
          cache: cache,
          clock: MutableClock(t0),
        );

        await c.read(moodleControllerProvider.notifier).maybeAutoSync();

        expect(api.courseCalls, 0);
      },
    );

    test('after one hour exactly one automatic attempt runs', () async {
      final api = FakeMoodleApiClient()..courses = <MoodleCourse>[course(1)];
      final cache = InMemoryMoodleCacheStore()
        ..marks = MoodleSyncMarks(
          lastAttempt: t0.subtract(const Duration(hours: 1)),
        );
      final c = await connected(
        api: api,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(moodleControllerProvider.notifier).maybeAutoSync();

      expect(api.courseCalls, 1);
    });

    test('concurrent automatic syncs cause only one network call', () async {
      final api = FakeMoodleApiClient()
        ..courses = <MoodleCourse>[course(1)]
        ..delay = const Duration(milliseconds: 30);
      final cache = InMemoryMoodleCacheStore();
      final c = await connected(
        api: api,
        cache: cache,
        clock: MutableClock(t0),
      );

      final notifier = c.read(moodleControllerProvider.notifier);
      await Future.wait(<Future<void>>[
        notifier.maybeAutoSync(),
        notifier.maybeAutoSync(),
      ]);

      expect(api.courseCalls, 1);
    });

    test('manual refresh bypasses the one-hour gate', () async {
      final api = FakeMoodleApiClient()..courses = <MoodleCourse>[course(1)];
      final cache = InMemoryMoodleCacheStore()
        ..marks = MoodleSyncMarks(lastAttempt: t0);
      final c = await connected(
        api: api,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(moodleControllerProvider.notifier).refresh();

      expect(api.courseCalls, 1);
    });

    test('logout waits for and discards a delayed sync response', () async {
      final Completer<List<MoodleCourse>> response =
          Completer<List<MoodleCourse>>();
      final api = FakeMoodleApiClient()..pendingCourses = response;
      final cache = InMemoryMoodleCacheStore();
      final c = await connected(
        api: api,
        cache: cache,
        clock: MutableClock(t0),
      );

      final Future<void> refresh = c
          .read(moodleControllerProvider.notifier)
          .refresh();
      await Future<void>.delayed(Duration.zero);
      expect(api.courseCalls, 1);

      bool logoutCompleted = false;
      final Future<void> logout = c
          .read(moodleAccountControllerProvider.notifier)
          .disconnect()
          .whenComplete(() => logoutCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(
        logoutCompleted,
        isFalse,
        reason: 'the wipe must follow the last in-flight cache write',
      );

      response.complete(<MoodleCourse>[course(99)]);
      await Future.wait(<Future<void>>[refresh, logout]);

      expect(cache.courses, isNull);
      expect(cache.deadlines, isNull);
      expect(cache.marks, const MoodleSyncMarks());
      expect(c.read(moodleAccountControllerProvider).value, isNull);
      expect(c.read(moodleControllerProvider).value?.courses, isEmpty);
    });

    test('a failed sync keeps the old cache and surfaces the error', () async {
      final api = FakeMoodleApiClient()
        ..throwOnCourses = const MoodleFailure(
          MoodleFailureKind.networkUnavailable,
        );
      final cache = InMemoryMoodleCacheStore()
        ..courses = <MoodleCourse>[course(1)]
        ..marks = MoodleSyncMarks(
          lastSuccess: t0.subtract(const Duration(days: 2)),
        );
      final c = await connected(
        api: api,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(moodleControllerProvider.notifier).refresh();

      final MoodleOverviewState s = c
          .read(moodleControllerProvider)
          .requireValue;
      expect(s.error?.kind, MoodleFailureKind.networkUnavailable);
      expect(s.courses, hasLength(1), reason: 'old cache stays visible');
      expect(cache.courses, hasLength(1));
    });

    test(
      'a failed auto attempt is not retried each build; manual still works',
      () async {
        final api = FakeMoodleApiClient()
          ..throwOnCourses = const MoodleFailure(
            MoodleFailureKind.serviceUnavailable,
          );
        final cache = InMemoryMoodleCacheStore();
        final c = await connected(
          api: api,
          cache: cache,
          clock: MutableClock(t0),
        );
        final notifier = c.read(moodleControllerProvider.notifier);

        await notifier.maybeAutoSync(); // #1 fails, records lastAttempt
        await notifier.maybeAutoSync(); // within one hour → skipped
        expect(api.courseCalls, 1);

        await notifier.refresh(); // user forces
        expect(api.courseCalls, 2);
      },
    );
  });
}
