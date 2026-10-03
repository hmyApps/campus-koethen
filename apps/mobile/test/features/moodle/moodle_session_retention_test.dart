// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/moodle/application/moodle_account_controller.dart';
import 'package:campus_koethen/features/moodle/application/moodle_course_detail.dart';
import 'package:campus_koethen/features/moodle/application/moodle_providers.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_course.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_moodle.dart';

/// Course detail data must not outlive the account it belongs to.
///
/// `moodleCourseDetailProvider` is a family provider and deliberately not
/// `autoDispose` — reopening a course should be instant. That made the
/// encrypted cache the only thing `disconnect()` actually cleared, while the
/// decoded bundle, `gradeText` included, stayed in Riverpod's own state.
/// Connecting a second account on the same device and opening the same course
/// then showed the FIRST account's grades.
void main() {
  final DateTime t0 = DateTime.utc(2026, 7, 26, 12);

  ProviderContainer containerWith({
    required FakeMoodleApiClient api,
    required InMemoryMoodleTokenStore tokens,
    required InMemoryMoodleCacheStore cache,
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        moodleApiClientProvider.overrideWithValue(api),
        moodleTokenStoreProvider.overrideWithValue(tokens),
        moodleCacheStoreProvider.overrideWithValue(cache),
        moodleClockProvider.overrideWithValue(MutableClock(t0)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'disconnect drops the in-memory course detail, not just the cache',
    () async {
      final api = FakeMoodleApiClient()
        ..courses = <MoodleCourse>[
          const MoodleCourse(id: 42, fullName: 'Rechnernetze'),
        ];
      final tokens = InMemoryMoodleTokenStore();
      final cache = InMemoryMoodleCacheStore();
      final ProviderContainer c = containerWith(
        api: api,
        tokens: tokens,
        cache: cache,
      );

      await c.read(moodleAccountControllerProvider.future);
      await c
          .read(moodleAccountControllerProvider.notifier)
          .connect(username: 'first', password: 'pw');

      final int courseId = api.courses.first.id;
      final MoodleCourseDetail first = await c.read(
        moodleCourseDetailProvider(courseId).future,
      );
      expect(first.course.id, courseId);

      final int generationBefore = c.read(moodleSessionGenerationProvider);
      await c.read(moodleAccountControllerProvider.notifier).disconnect();

      // The generation moved, which is what forces every holder of course data
      // to rebuild rather than serve the previous account's bundle.
      expect(
        c.read(moodleSessionGenerationProvider),
        greaterThan(generationBefore),
      );
      expect(cache.sections, isEmpty);
    },
  );

  test(
    'connecting a second account does not inherit the first one\'s bundle',
    () async {
      final api = FakeMoodleApiClient()
        ..courses = <MoodleCourse>[
          const MoodleCourse(id: 42, fullName: 'Rechnernetze'),
        ];
      final tokens = InMemoryMoodleTokenStore();
      final cache = InMemoryMoodleCacheStore();
      final ProviderContainer c = containerWith(
        api: api,
        tokens: tokens,
        cache: cache,
      );

      await c.read(moodleAccountControllerProvider.future);
      await c
          .read(moodleAccountControllerProvider.notifier)
          .connect(username: 'first', password: 'pw');
      final int courseId = api.courses.first.id;
      await c.read(moodleCourseDetailProvider(courseId).future);

      final int generationBefore = c.read(moodleSessionGenerationProvider);
      api.siteInfo = const MoodleSiteInfo(userId: 8, username: 'second');
      final int clearsBefore = cache.clears;
      await c
          .read(moodleAccountControllerProvider.notifier)
          .connect(username: 'second', password: 'pw');

      // Even without an explicit disconnect in between.
      expect(
        c.read(moodleSessionGenerationProvider),
        greaterThan(generationBefore),
      );
      expect(cache.clears, clearsBefore + 1);
      expect(cache.sections, isEmpty);
    },
  );
}
