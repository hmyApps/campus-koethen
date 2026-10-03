// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer
//
// In-memory fakes for Moodle tests. No real network, no real credentials.

import 'dart:async';

import 'package:campus_koethen/core/time/clock.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_announcement.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_api_client.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_assignment.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_cache.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_content.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_course.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';

class MutableClock implements Clock {
  MutableClock(this._now);
  DateTime _now;
  void advance(Duration d) => _now = _now.add(d);
  void setTo(DateTime t) => _now = t;
  @override
  DateTime now() => _now;
}

/// A fully scriptable [MoodleApiClient]. Each field is either a value to return
/// or, if the matching `throwOn…` is set, an error to throw.
class FakeMoodleApiClient implements MoodleApiClient {
  String tokenToReturn = 'tok-fake';
  MoodleSiteInfo siteInfo = const MoodleSiteInfo(userId: 7, username: 'demo');
  List<MoodleCourse> courses = <MoodleCourse>[];
  List<MoodleDeadline> deadlines = <MoodleDeadline>[];
  List<MoodleSection> sections = <MoodleSection>[];
  List<MoodleAssignment> assignments = <MoodleAssignment>[];
  List<MoodleAnnouncement> announcements = <MoodleAnnouncement>[];
  Map<int, MoodleSubmissionStatus> statuses = <int, MoodleSubmissionStatus>{};

  Object? throwOnRequestToken;
  Object? throwOnSiteInfo;
  Object? throwOnCourses;
  Object? throwOnDeadlines;
  Object? throwOnContents;

  /// Optional artificial latency for the overview calls (concurrency tests).
  Duration? delay;

  /// Optional deterministic gate for logout-race tests.
  Completer<List<MoodleCourse>>? pendingCourses;

  /// Optional deterministic gate for setup accessibility and race tests.
  Completer<String>? pendingToken;
  Completer<void>? tokenRequested;

  int courseCalls = 0;
  int deadlineCalls = 0;
  final List<int> statusRequestedFor = <int>[];

  /// Highest number of read calls that were in flight at the same time.
  ///
  /// Every read below yields once before it answers, so a caller that awaits
  /// its calls one after another never gets above 1 — which is exactly what
  /// distinguishes sequential from concurrent fetching.
  int maxConcurrentReads = 0;
  int _inFlightReads = 0;

  Future<T> _read<T>(Future<T> Function() body) async {
    _inFlightReads++;
    if (_inFlightReads > maxConcurrentReads) {
      maxConcurrentReads = _inFlightReads;
    }
    try {
      await Future<void>.delayed(Duration.zero);
      return await body();
    } finally {
      _inFlightReads--;
    }
  }

  @override
  Future<String> requestToken({
    required String username,
    required String password,
  }) async {
    if (tokenRequested != null && !tokenRequested!.isCompleted) {
      tokenRequested!.complete();
    }
    if (pendingToken != null) return pendingToken!.future;
    if (throwOnRequestToken != null) throw throwOnRequestToken!;
    return tokenToReturn;
  }

  @override
  Future<MoodleSiteInfo> getSiteInfo(String token) async {
    if (throwOnSiteInfo != null) throw throwOnSiteInfo!;
    return siteInfo;
  }

  @override
  Future<List<MoodleCourse>> getCourses({required String token}) async {
    courseCalls++;
    return _read(() async {
      if (pendingCourses != null) return pendingCourses!.future;
      if (delay != null) await Future<void>.delayed(delay!);
      if (throwOnCourses != null) throw throwOnCourses!;
      return courses;
    });
  }

  @override
  Future<List<MoodleDeadline>> getUpcomingDeadlines({
    required String token,
    DateTime? from,
    int limit = 50,
  }) async {
    deadlineCalls++;
    return _read(() async {
      if (throwOnDeadlines != null) throw throwOnDeadlines!;
      return deadlines;
    });
  }

  @override
  Future<List<MoodleSection>> getCourseContents({
    required String token,
    required int courseId,
  }) async {
    return _read(() async {
      if (throwOnContents != null) throw throwOnContents!;
      return sections;
    });
  }

  @override
  Future<List<MoodleAssignment>> getAssignments({
    required String token,
    required List<int> courseIds,
  }) async {
    return _read(() async => assignments);
  }

  @override
  Future<MoodleSubmissionStatus> getSubmissionStatus({
    required String token,
    required int assignmentId,
  }) async {
    statusRequestedFor.add(assignmentId);
    return statuses[assignmentId] ?? const MoodleSubmissionStatus();
  }

  @override
  Future<List<MoodleAnnouncement>> getAnnouncements({
    required String token,
    required int courseId,
  }) async {
    return _read(() async => announcements);
  }
}

class InMemoryMoodleTokenStore implements MoodleTokenStore {
  MoodleToken? token;
  int writes = 0;
  int clears = 0;
  Object? clearError;

  @override
  Future<MoodleToken?> read() async => token;

  @override
  Future<void> write(MoodleToken t) async {
    writes++;
    token = t;
  }

  @override
  Future<void> clear() async {
    clears++;
    if (clearError != null) throw clearError!;
    token = null;
  }
}

class InMemoryMoodleCacheStore implements MoodleCacheStore {
  List<MoodleCourse>? courses;
  List<MoodleDeadline>? deadlines;
  final Map<int, List<MoodleSection>> sections = <int, List<MoodleSection>>{};
  final Map<int, List<MoodleAssignment>> assignments =
      <int, List<MoodleAssignment>>{};
  final Map<int, List<MoodleAnnouncement>> announcements =
      <int, List<MoodleAnnouncement>>{};
  MoodleSyncMarks marks = const MoodleSyncMarks();
  int clears = 0;
  Object? clearError;

  @override
  Future<List<MoodleCourse>?> readCourses() async => courses;
  @override
  Future<void> writeCourses(List<MoodleCourse> c) async => courses = c;

  @override
  Future<List<MoodleDeadline>?> readDeadlines() async => deadlines;
  @override
  Future<void> writeDeadlines(List<MoodleDeadline> d) async => deadlines = d;

  @override
  Future<List<MoodleSection>?> readSections(int courseId) async =>
      sections[courseId];
  @override
  Future<void> writeSections(int courseId, List<MoodleSection> s) async =>
      sections[courseId] = s;

  @override
  Future<List<MoodleAssignment>?> readAssignments(int courseId) async =>
      assignments[courseId];
  @override
  Future<void> writeAssignments(int courseId, List<MoodleAssignment> a) async =>
      assignments[courseId] = a;

  @override
  Future<List<MoodleAnnouncement>?> readAnnouncements(int courseId) async =>
      announcements[courseId];
  @override
  Future<void> writeAnnouncements(
    int courseId,
    List<MoodleAnnouncement> a,
  ) async => announcements[courseId] = a;

  final Map<int, DateTime> detailFetchedAt = <int, DateTime>{};

  @override
  Future<DateTime?> readCourseDetailFetchedAt(int courseId) async =>
      detailFetchedAt[courseId];

  @override
  Future<void> writeCourseDetailFetchedAt(int courseId, DateTime at) async =>
      detailFetchedAt[courseId] = at;

  @override
  Future<MoodleSyncMarks> readMarks() async => marks;
  @override
  Future<void> writeMarks(MoodleSyncMarks m) async => marks = m;

  @override
  Future<void> clear() async {
    clears++;
    if (clearError != null) throw clearError!;
    courses = null;
    deadlines = null;
    sections.clear();
    assignments.clear();
    announcements.clear();
    detailFetchedAt.clear();
    marks = const MoodleSyncMarks();
  }
}
