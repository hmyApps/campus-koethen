// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/moodle/data/moodle_repository_impl.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_assignment.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_cache.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_course.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_failure.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_moodle.dart';

MoodleDeadline deadline(int id) => MoodleDeadline(
  id: id,
  title: 'D$id',
  dueAt: DateTime.fromMillisecondsSinceEpoch(1704672000 * 1000),
);

void main() {
  late FakeMoodleApiClient api;
  late InMemoryMoodleTokenStore tokens;
  late InMemoryMoodleCacheStore cache;
  late MutableClock clock;
  late MoodleRepositoryImpl repo;

  setUp(() {
    api = FakeMoodleApiClient();
    tokens = InMemoryMoodleTokenStore();
    cache = InMemoryMoodleCacheStore();
    clock = MutableClock(DateTime(2026, 7, 20, 12));
    repo = MoodleRepositoryImpl(
      apiClient: api,
      tokenStore: tokens,
      cacheStore: cache,
      clock: clock,
    );
  });

  group('connect', () {
    test(
      'verifies via site-info, then stores a token and returns account',
      () async {
        api.tokenToReturn = 'tok-abc';
        api.siteInfo = const MoodleSiteInfo(
          userId: 42,
          username: 's123',
          siteName: 'Demo',
        );

        final MoodleAccount account = await repo.connect(
          username: 's123',
          password: 'pw',
        );

        expect(account.userId, 42);
        expect(account.username, 's123');
        expect(tokens.token, isNotNull);
        expect(tokens.token!.value, 'tok-abc');
        expect(tokens.token!.userId, 42);
      },
    );

    test('does not store a token when credentials are rejected', () async {
      api.throwOnRequestToken = const MoodleFailure(
        MoodleFailureKind.invalidCredentials,
      );

      await expectLater(
        repo.connect(username: 'x', password: 'y'),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidCredentials)),
      );
      expect(tokens.token, isNull);
      expect(tokens.writes, 0);
    });

    test('does not store a token when verification fails', () async {
      api.throwOnSiteInfo = const MoodleFailure(
        MoodleFailureKind.tokenRejected,
      );
      await expectLater(
        repo.connect(username: 'x', password: 'y'),
        throwsA(const MoodleFailure(MoodleFailureKind.tokenRejected)),
      );
      expect(tokens.token, isNull);
    });
  });

  group('refreshOverview', () {
    setUp(() {
      tokens.token = const MoodleToken(value: 'tok', userId: 7);
    });

    test('caches courses and deadlines and advances lastSuccess', () async {
      api.courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Beispielkurs Informatik'),
      ];
      api.deadlines = <MoodleDeadline>[deadline(9)];

      final MoodleOverview overview = await repo.refreshOverview();

      expect(overview.courses, hasLength(1));
      expect(cache.courses, hasLength(1));
      expect(cache.deadlines, hasLength(1));
      expect(cache.marks.lastSuccess, clock.now());
      expect(cache.marks.lastAttempt, clock.now());
    });

    test(
      'an empty current-course response removes stale cached courses',
      () async {
        cache.courses = <MoodleCourse>[
          const MoodleCourse(id: 1, fullName: 'Alter Kurs'),
        ];
        cache.deadlines = <MoodleDeadline>[deadline(1)];
        api.courses = <MoodleCourse>[]; // valid: no in-progress courses
        api.deadlines = <MoodleDeadline>[];

        final MoodleOverview overview = await repo.refreshOverview();

        expect(cache.courses, isEmpty);
        expect(cache.deadlines, hasLength(1));
        expect(overview.courses, isEmpty);
      },
    );

    test('an empty deadline response keeps the cache but marks it '
        'unconfirmed', () async {
      // Moodle drops an action event once it is submitted, so "nothing left"
      // arrives as an empty list. The last good list stays (AGENTS.md § 4),
      // but it is no longer what Moodle reports and must not drive reminders.
      cache.deadlines = <MoodleDeadline>[deadline(1)];
      api.courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Beispielkurs Informatik'),
      ];
      api.deadlines = <MoodleDeadline>[];

      final MoodleOverview overview = await repo.refreshOverview();

      expect(cache.deadlines, hasLength(1));
      expect(overview.deadlines, hasLength(1));
      expect(overview.deadlinesConfirmed, isFalse);
      expect(cache.marks.deadlinesConfirmed, isFalse);
    });

    test('a non-empty deadline response confirms the list again', () async {
      cache.marks = const MoodleSyncMarks(deadlinesConfirmed: false);
      api.deadlines = <MoodleDeadline>[deadline(2)];

      final MoodleOverview overview = await repo.refreshOverview();

      expect(overview.deadlinesConfirmed, isTrue);
      expect(cache.marks.deadlinesConfirmed, isTrue);
    });

    test('a failed fetch throws and leaves the cache untouched', () async {
      cache.courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Alter Kurs'),
      ];
      final DateTime before = clock.now();
      cache.marks = MoodleSyncMarks(lastSuccess: before);
      api.throwOnCourses = const MoodleFailure(
        MoodleFailureKind.networkUnavailable,
      );
      clock.advance(const Duration(hours: 1));

      await expectLater(
        repo.refreshOverview(),
        throwsA(const MoodleFailure(MoodleFailureKind.networkUnavailable)),
      );
      expect(cache.courses, hasLength(1));
      expect(cache.marks.lastSuccess, before); // unchanged
    });

    test('throws tokenExpired when there is no token', () async {
      tokens.token = null;
      await expectLater(
        repo.refreshOverview(),
        throwsA(const MoodleFailure(MoodleFailureKind.tokenExpired)),
      );
    });
  });

  group('course detail', () {
    setUp(() {
      tokens.token = const MoodleToken(value: 'tok', userId: 7);
    });

    test('cachedCourseDetail is null before the course is loaded', () async {
      cache.courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Beispielkurs'),
      ];
      expect(await repo.cachedCourseDetail(1), isNull);
    });

    test(
      'refreshCourseDetail loads content, attaches status and flags late',
      () async {
        cache.courses = <MoodleCourse>[
          const MoodleCourse(id: 1, fullName: 'Beispielkurs Informatik'),
        ];
        final DateTime due = DateTime.fromMillisecondsSinceEpoch(
          1704672000 * 1000,
        );
        api.assignments = <MoodleAssignment>[
          MoodleAssignment(id: 50, courseId: 1, name: 'Abgabe', dueDate: due),
        ];
        api.statuses = <int, MoodleSubmissionStatus>{
          50: MoodleSubmissionStatus(
            state: MoodleSubmissionState.submitted,
            submittedAt: due.add(const Duration(days: 1)), // after due -> late
          ),
        };

        final MoodleCourseDetail detail = await repo.refreshCourseDetail(1);

        expect(detail.course.id, 1);
        expect(detail.assignments, hasLength(1));
        expect(api.statusRequestedFor, contains(50));
        expect(detail.assignments.first.status!.isLate, isTrue);
        // Cached for offline re-open.
        expect(await repo.cachedCourseDetail(1), isNotNull);
      },
    );
  });

  group('request concurrency', () {
    setUp(() {
      tokens.token = const MoodleToken(value: 'tok', userId: 7);
    });

    test('refreshOverview asks for courses and deadlines at once', () async {
      await repo.refreshOverview();

      expect(api.courseCalls, 1);
      expect(api.deadlineCalls, 1);
      // Both in flight together: run one after the other, the peak is 1.
      expect(api.maxConcurrentReads, greaterThanOrEqualTo(2));
    });

    test(
      'refreshOverview still reports the original failure, not a wrapper',
      () async {
        api.throwOnDeadlines = const MoodleFailure(
          MoodleFailureKind.tokenExpired,
        );

        await expectLater(
          repo.refreshOverview(),
          throwsA(const MoodleFailure(MoodleFailureKind.tokenExpired)),
        );
      },
    );

    test(
      'refreshCourseDetail asks for contents, assignments and announcements at once',
      () async {
        await repo.refreshCourseDetail(1);

        expect(api.maxConcurrentReads, greaterThanOrEqualTo(3));
      },
    );

    test(
      'refreshCourseDetail still reports the original failure, not a wrapper',
      () async {
        api.throwOnContents = const MoodleFailure(
          MoodleFailureKind.networkUnavailable,
        );

        await expectLater(
          repo.refreshCourseDetail(1),
          throwsA(const MoodleFailure(MoodleFailureKind.networkUnavailable)),
        );
        // Nothing was written for a course whose contents never arrived.
        expect(await repo.cachedCourseDetail(1), isNull);
      },
    );
  });

  test('disconnect wipes token and cache', () async {
    tokens.token = const MoodleToken(value: 'tok', userId: 7);
    cache.courses = <MoodleCourse>[const MoodleCourse(id: 1, fullName: 'X')];

    await repo.disconnect();

    expect(tokens.token, isNull);
    expect(tokens.clears, 1);
    expect(cache.clears, 1);
    expect(cache.courses, isNull);
  });
}
