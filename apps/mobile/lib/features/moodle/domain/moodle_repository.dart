// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../../../core/documents/app_document.dart';
import 'moodle_account.dart';
import 'moodle_announcement.dart';
import 'moodle_assignment.dart';
import 'moodle_cache.dart';
import 'moodle_content.dart';
import 'moodle_course.dart';
import 'moodle_deadline.dart';
import 'moodle_downloader.dart';

/// The course list plus upcoming deadlines fetched together on a sync.
@immutable
class MoodleOverview {
  const MoodleOverview({
    required this.courses,
    required this.deadlines,
    this.deadlinesConfirmed = true,
  });

  final List<MoodleCourse> courses;
  final List<MoodleDeadline> deadlines;

  /// False when [deadlines] is the kept previous list because Moodle answered
  /// with an empty one; see `MoodleSyncMarks.deadlinesConfirmed`.
  final bool deadlinesConfirmed;
}

/// Everything shown on a course detail page.
@immutable
class MoodleCourseDetail {
  const MoodleCourseDetail({
    required this.course,
    this.sections = const <MoodleSection>[],
    this.assignments = const <MoodleAssignment>[],
    this.announcements = const <MoodleAnnouncement>[],
    this.fetchedAt,
  });

  final MoodleCourse course;
  final List<MoodleSection> sections;
  final List<MoodleAssignment> assignments;
  final List<MoodleAnnouncement> announcements;

  /// When this bundle was last fetched from Moodle, or null when that is not
  /// recorded (a bundle cached before the timestamp existed).
  final DateTime? fetchedAt;
}

/// The single facade the Moodle and calendar features use.
///
/// It owns the token store, the API client and the encrypted cache, and it is
/// the only component that ever holds a live token. Invalid responses never
/// destroy the last good cache; a valid empty current-course list is allowed to
/// clear courses that Moodle no longer classifies as in progress.
abstract interface class MoodleRepository {
  /// The current public connection state, or null when not connected. Never
  /// exposes the token.
  Future<MoodleAccount?> currentAccount();

  /// Verifies the credentials against Moodle, and only on success stores the
  /// token in secure storage. The password is never persisted.
  Future<MoodleAccount> connect({
    required String username,
    required String password,
  });

  /// Wipes token, user id, encrypted cache, cache key and sync timestamps.
  Future<void> disconnect();

  Future<List<MoodleCourse>?> cachedCourses();
  Future<List<MoodleDeadline>?> cachedDeadlines();
  Future<MoodleSyncMarks> syncMarks();

  /// Records that an automatic sync was attempted (advances `lastAttempt`).
  Future<void> recordAttempt(DateTime at);

  /// Fetches courses + deadlines, validates, replaces the cache and advances
  /// `lastSuccess`. Throws [MoodleFailure] on any error, leaving the cache
  /// untouched.
  Future<MoodleOverview> refreshOverview();

  Future<MoodleCourseDetail?> cachedCourseDetail(int courseId);

  /// Loads sections, assignments (with submission status) and announcements for
  /// one course, caches them and returns the bundle.
  Future<MoodleCourseDetail> refreshCourseDetail(int courseId);

  /// Downloads one Moodle file on demand. The token is read internally and
  /// attached only for the pinned Moodle host — it never reaches the UI.
  Future<AppDocument> downloadFile(
    MoodleFile file, {
    MoodleDownloadProgress? onProgress,
    MoodleDownloadCancel? cancel,
  });
}
