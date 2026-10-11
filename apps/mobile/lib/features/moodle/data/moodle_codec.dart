// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import '../domain/moodle_announcement.dart';
import '../domain/moodle_assignment.dart';
import '../domain/moodle_cache.dart';
import '../domain/moodle_content.dart';
import '../domain/moodle_course.dart';
import '../domain/moodle_deadline.dart';

/// JSON (de)serialization for the encrypted Moodle cache.
///
/// Kept separate from the network parsers: this is the app's own on-disk format,
/// fully controlled, so it is exact and round-trips losslessly. Decoders throw
/// on malformed input; the cache store treats a throw as "no usable entry" and
/// keeps the previous good data.

int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
DateTime? _date(Object? v) =>
    v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

// -- Courses ----------------------------------------------------------------

String encodeCourses(List<MoodleCourse> courses) =>
    jsonEncode(courses.map(_courseToJson).toList());

List<MoodleCourse> decodeCourses(String raw) {
  final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((dynamic e) => _courseFromJson(e as Map<String, dynamic>))
      .toList();
}

Map<String, dynamic> _courseToJson(MoodleCourse c) => <String, dynamic>{
  'id': c.id,
  'fullName': c.fullName,
  'shortName': c.shortName,
  'summary': c.summary,
  'startDate': _ms(c.startDate),
  'endDate': _ms(c.endDate),
  'progress': c.progress,
  'hidden': c.hidden,
};

MoodleCourse _courseFromJson(Map<String, dynamic> m) => MoodleCourse(
  id: m['id'] as int,
  fullName: m['fullName'] as String,
  shortName: (m['shortName'] as String?) ?? '',
  summary: (m['summary'] as String?) ?? '',
  startDate: _date(m['startDate']),
  endDate: _date(m['endDate']),
  progress: m['progress'] as int?,
  hidden: (m['hidden'] as bool?) ?? false,
);

// -- Deadlines --------------------------------------------------------------

String encodeDeadlines(List<MoodleDeadline> deadlines) =>
    jsonEncode(deadlines.map(_deadlineToJson).toList());

List<MoodleDeadline> decodeDeadlines(String raw) {
  final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((dynamic e) => _deadlineFromJson(e as Map<String, dynamic>))
      .toList();
}

Map<String, dynamic> _deadlineToJson(MoodleDeadline d) => <String, dynamic>{
  'id': d.id,
  'title': d.title,
  'dueAt': _ms(d.dueAt),
  'courseId': d.courseId,
  'courseName': d.courseName,
  'moduleName': d.moduleName,
  'eventType': d.eventType,
};

MoodleDeadline _deadlineFromJson(Map<String, dynamic> m) => MoodleDeadline(
  id: m['id'] as int,
  title: m['title'] as String,
  dueAt: DateTime.fromMillisecondsSinceEpoch(m['dueAt'] as int),
  courseId: m['courseId'] as int?,
  courseName: m['courseName'] as String?,
  moduleName: m['moduleName'] as String?,
  eventType: m['eventType'] as String?,
);

// -- Sections / modules / files ---------------------------------------------

String encodeSections(List<MoodleSection> sections) =>
    jsonEncode(sections.map(_sectionToJson).toList());

List<MoodleSection> decodeSections(String raw) {
  final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((dynamic e) => _sectionFromJson(e as Map<String, dynamic>))
      .toList();
}

Map<String, dynamic> _sectionToJson(MoodleSection s) => <String, dynamic>{
  'name': s.name,
  'summary': s.summary,
  'visible': s.visible,
  'modules': s.modules.map(_moduleToJson).toList(),
};

MoodleSection _sectionFromJson(Map<String, dynamic> m) => MoodleSection(
  name: m['name'] as String,
  summary: (m['summary'] as String?) ?? '',
  visible: (m['visible'] as bool?) ?? true,
  modules: ((m['modules'] as List<dynamic>?) ?? <dynamic>[])
      .map((dynamic e) => _moduleFromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _moduleToJson(MoodleModule m) => <String, dynamic>{
  'id': m.id,
  'name': m.name,
  'rawType': m.rawType,
  'description': m.description,
  'url': m.url,
  'visible': m.visible,
  'availabilityInfo': m.availabilityInfo,
  'instanceId': m.instanceId,
  'files': m.files.map(_fileToJson).toList(),
};

MoodleModule _moduleFromJson(Map<String, dynamic> m) {
  final String rawType = (m['rawType'] as String?) ?? '';
  return MoodleModule(
    id: m['id'] as int,
    name: m['name'] as String,
    type: MoodleModuleType.fromRaw(rawType),
    rawType: rawType,
    description: (m['description'] as String?) ?? '',
    url: m['url'] as String?,
    visible: (m['visible'] as bool?) ?? true,
    availabilityInfo: m['availabilityInfo'] as String?,
    instanceId: m['instanceId'] as int?,
    files: ((m['files'] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic e) => _fileFromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

Map<String, dynamic> _fileToJson(MoodleFile f) => <String, dynamic>{
  'fileName': f.fileName,
  'fileUrl': f.fileUrl,
  'mimeType': f.mimeType,
  'fileSize': f.fileSize,
  'timeModified': _ms(f.timeModified),
};

MoodleFile _fileFromJson(Map<String, dynamic> m) => MoodleFile(
  fileName: m['fileName'] as String,
  fileUrl: m['fileUrl'] as String,
  mimeType: m['mimeType'] as String?,
  fileSize: m['fileSize'] as int?,
  timeModified: _date(m['timeModified']),
);

// -- Assignments ------------------------------------------------------------

String encodeAssignments(List<MoodleAssignment> items) =>
    jsonEncode(items.map(_assignmentToJson).toList());

List<MoodleAssignment> decodeAssignments(String raw) {
  final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((dynamic e) => _assignmentFromJson(e as Map<String, dynamic>))
      .toList();
}

Map<String, dynamic> _assignmentToJson(MoodleAssignment a) => <String, dynamic>{
  'id': a.id,
  'courseId': a.courseId,
  'name': a.name,
  'cmid': a.cmid,
  'intro': a.intro,
  'dueDate': _ms(a.dueDate),
  'cutOffDate': _ms(a.cutOffDate),
  'status': a.status == null ? null : _statusToJson(a.status!),
};

MoodleAssignment _assignmentFromJson(Map<String, dynamic> m) =>
    MoodleAssignment(
      id: m['id'] as int,
      courseId: m['courseId'] as int,
      name: m['name'] as String,
      cmid: m['cmid'] as int?,
      intro: (m['intro'] as String?) ?? '',
      dueDate: _date(m['dueDate']),
      cutOffDate: _date(m['cutOffDate']),
      status: m['status'] == null
          ? null
          : _statusFromJson(m['status'] as Map<String, dynamic>),
    );

Map<String, dynamic> _statusToJson(MoodleSubmissionStatus s) =>
    <String, dynamic>{
      'state': s.state.name,
      'submittedAt': _ms(s.submittedAt),
      'isLate': s.isLate,
      'graded': s.graded,
      'gradeText': s.gradeText,
    };

MoodleSubmissionStatus _statusFromJson(Map<String, dynamic> m) =>
    MoodleSubmissionStatus(
      state: MoodleSubmissionState.values.firstWhere(
        (MoodleSubmissionState e) => e.name == m['state'],
        orElse: () => MoodleSubmissionState.unknown,
      ),
      submittedAt: _date(m['submittedAt']),
      isLate: (m['isLate'] as bool?) ?? false,
      graded: (m['graded'] as bool?) ?? false,
      gradeText: m['gradeText'] as String?,
    );

// -- Announcements ----------------------------------------------------------

String encodeAnnouncements(List<MoodleAnnouncement> items) =>
    jsonEncode(items.map(_announcementToJson).toList());

List<MoodleAnnouncement> decodeAnnouncements(String raw) {
  final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((dynamic e) => _announcementFromJson(e as Map<String, dynamic>))
      .toList();
}

Map<String, dynamic> _announcementToJson(MoodleAnnouncement a) =>
    <String, dynamic>{
      'id': a.id,
      'courseId': a.courseId,
      'subject': a.subject,
      'message': a.message,
      'authorName': a.authorName,
      'createdAt': _ms(a.createdAt),
      'links': a.links,
    };

MoodleAnnouncement _announcementFromJson(Map<String, dynamic> m) =>
    MoodleAnnouncement(
      id: m['id'] as int,
      courseId: m['courseId'] as int,
      subject: m['subject'] as String,
      message: (m['message'] as String?) ?? '',
      authorName: m['authorName'] as String?,
      createdAt: _date(m['createdAt']),
      // Absent in bundles written before links were kept — an older cache
      // decodes as "no links" rather than failing to decode at all.
      links: <String>[
        for (final Object? link in (m['links'] as List<dynamic>?) ?? const [])
          if (link is String) link,
      ],
    );

// -- Sync marks -------------------------------------------------------------

String encodeMarks(MoodleSyncMarks marks) => jsonEncode(<String, dynamic>{
  'lastAttempt': _ms(marks.lastAttempt),
  'lastSuccess': _ms(marks.lastSuccess),
  'deadlinesConfirmed': marks.deadlinesConfirmed,
});

MoodleSyncMarks decodeMarks(String raw) {
  final Map<String, dynamic> m = jsonDecode(raw) as Map<String, dynamic>;
  return MoodleSyncMarks(
    lastAttempt: _date(m['lastAttempt']),
    lastSuccess: _date(m['lastSuccess']),
    // Marks written before the flag existed describe a confirmed list.
    deadlinesConfirmed: m['deadlinesConfirmed'] != false,
  );
}
