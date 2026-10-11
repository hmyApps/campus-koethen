// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'moodle_announcement.dart';
import 'moodle_assignment.dart';
import 'moodle_content.dart';
import 'moodle_course.dart';
import 'moodle_deadline.dart';

/// The two independently tracked sync timestamps.
///
/// [lastAttempt] advances on every automatic try (success or failure) so a
/// failed attempt is not retried on every widget build; [lastSuccess] advances
/// only when a fully validated response actually replaced the cache.
@immutable
class MoodleSyncMarks {
  const MoodleSyncMarks({
    this.lastAttempt,
    this.lastSuccess,
    this.deadlinesConfirmed = true,
  });

  final DateTime? lastAttempt;
  final DateTime? lastSuccess;

  /// Whether the cached deadlines are what Moodle reported in the last
  /// successful sync. False when Moodle answered with an empty list and the
  /// previous list was kept instead (AGENTS.md § 4): it is still shown, but
  /// no reminder or daily-summary count may be derived from it.
  final bool deadlinesConfirmed;

  MoodleSyncMarks copyWith({
    DateTime? lastAttempt,
    DateTime? lastSuccess,
    bool? deadlinesConfirmed,
  }) => MoodleSyncMarks(
    lastAttempt: lastAttempt ?? this.lastAttempt,
    lastSuccess: lastSuccess ?? this.lastSuccess,
    deadlinesConfirmed: deadlinesConfirmed ?? this.deadlinesConfirmed,
  );
}

/// Port: the encrypted, at-rest Moodle cache.
///
/// Everything here is personal Moodle data and is stored only in the encrypted
/// box on-device. A concrete implementation must never lose the last good data
/// on an empty/invalid response — that guard lives in the repository, which only
/// calls the write methods with validated content.
abstract interface class MoodleCacheStore {
  Future<List<MoodleCourse>?> readCourses();
  Future<void> writeCourses(List<MoodleCourse> courses);

  Future<List<MoodleDeadline>?> readDeadlines();
  Future<void> writeDeadlines(List<MoodleDeadline> deadlines);

  Future<List<MoodleSection>?> readSections(int courseId);
  Future<void> writeSections(int courseId, List<MoodleSection> sections);

  Future<List<MoodleAssignment>?> readAssignments(int courseId);
  Future<void> writeAssignments(int courseId, List<MoodleAssignment> items);

  Future<List<MoodleAnnouncement>?> readAnnouncements(int courseId);
  Future<void> writeAnnouncements(int courseId, List<MoodleAnnouncement> items);

  /// When this course's detail bundle was last fetched successfully.
  ///
  /// Per course, not global: the overview's sync mark says nothing about when
  /// a particular course page was last refreshed, and a submission state weeks
  /// old looks exactly like one from a minute ago without it.
  Future<DateTime?> readCourseDetailFetchedAt(int courseId);
  Future<void> writeCourseDetailFetchedAt(int courseId, DateTime at);

  Future<MoodleSyncMarks> readMarks();
  Future<void> writeMarks(MoodleSyncMarks marks);

  /// Wipes every cached entry (used when disconnecting the account).
  Future<void> clear();
}
