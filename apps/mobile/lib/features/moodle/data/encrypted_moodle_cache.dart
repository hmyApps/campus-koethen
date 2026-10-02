// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/cache/encrypted_box.dart';
import '../domain/moodle_announcement.dart';
import '../domain/moodle_assignment.dart';
import '../domain/moodle_cache.dart';
import '../domain/moodle_content.dart';
import '../domain/moodle_course.dart';
import '../domain/moodle_deadline.dart';
import '../domain/moodle_failure.dart';
import 'moodle_codec.dart';

/// [MoodleCacheStore] backed by the shared [EncryptedBox] (encrypted at rest
/// with a device-held 256-bit key — the same infrastructure the grades cache
/// uses, not a second crypto implementation).
///
/// All personal Moodle data lives only here on-device. A corrupt or missing
/// entry decodes to null so the caller keeps the last good data; [clear] wipes
/// the whole box AND deletes its key.
class EncryptedMoodleCache implements MoodleCacheStore {
  EncryptedMoodleCache([EncryptedBox? box])
    : _box =
          box ??
          EncryptedBox(
            boxName: 'campus_moodle_cache_v1',
            keyStorageKey: 'moodle.cache.key.v1',
          );

  final EncryptedBox _box;

  static const String _coursesKey = 'courses';
  static const String _deadlinesKey = 'deadlines';
  static const String _marksKey = 'marks';
  static String _sectionsKey(int courseId) => 'sections.$courseId';
  static String _assignmentsKey(int courseId) => 'assignments.$courseId';
  static String _announcementsKey(int courseId) => 'announcements.$courseId';
  static String _fetchedAtKey(int courseId) => 'detailFetchedAt.$courseId';

  Future<T?> _read<T>(String key, T Function(String) decode) async {
    final String? raw = await _box.read(key);
    if (raw == null) return null;
    try {
      return decode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MoodleCourse>?> readCourses() =>
      _read(_coursesKey, decodeCourses);

  @override
  Future<void> writeCourses(List<MoodleCourse> courses) =>
      _box.write(_coursesKey, encodeCourses(courses));

  @override
  Future<List<MoodleDeadline>?> readDeadlines() =>
      _read(_deadlinesKey, decodeDeadlines);

  @override
  Future<void> writeDeadlines(List<MoodleDeadline> deadlines) =>
      _box.write(_deadlinesKey, encodeDeadlines(deadlines));

  @override
  Future<List<MoodleSection>?> readSections(int courseId) =>
      _read(_sectionsKey(courseId), decodeSections);

  @override
  Future<void> writeSections(int courseId, List<MoodleSection> sections) =>
      _box.write(_sectionsKey(courseId), encodeSections(sections));

  @override
  Future<List<MoodleAssignment>?> readAssignments(int courseId) =>
      _read(_assignmentsKey(courseId), decodeAssignments);

  @override
  Future<void> writeAssignments(int courseId, List<MoodleAssignment> items) =>
      _box.write(_assignmentsKey(courseId), encodeAssignments(items));

  @override
  Future<List<MoodleAnnouncement>?> readAnnouncements(int courseId) =>
      _read(_announcementsKey(courseId), decodeAnnouncements);

  @override
  Future<void> writeAnnouncements(
    int courseId,
    List<MoodleAnnouncement> items,
  ) => _box.write(_announcementsKey(courseId), encodeAnnouncements(items));

  @override
  Future<DateTime?> readCourseDetailFetchedAt(int courseId) async {
    final String? raw = await _box.read(_fetchedAtKey(courseId));
    final int? ms = raw == null ? null : int.tryParse(raw);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> writeCourseDetailFetchedAt(int courseId, DateTime at) =>
      _box.write(_fetchedAtKey(courseId), '${at.millisecondsSinceEpoch}');

  @override
  Future<MoodleSyncMarks> readMarks() async {
    final MoodleSyncMarks? marks = await _read(_marksKey, decodeMarks);
    return marks ?? const MoodleSyncMarks();
  }

  @override
  Future<void> writeMarks(MoodleSyncMarks marks) =>
      _box.write(_marksKey, encodeMarks(marks));

  @override
  Future<void> clear() async {
    final EncryptedBoxWipeResult result = await _box.wipeChecked();
    if (!result.isComplete) {
      throw const MoodleFailure(MoodleFailureKind.cacheUnavailable);
    }
  }
}
