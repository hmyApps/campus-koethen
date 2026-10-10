// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/text/html_content.dart';
import '../domain/moodle_account.dart';
import '../domain/moodle_announcement.dart';
import '../domain/moodle_assignment.dart';
import '../domain/moodle_content.dart';
import '../domain/moodle_course.dart';
import '../domain/moodle_deadline.dart';
import '../domain/moodle_failure.dart';

/// Defensive parsers from raw Moodle JSON to domain value objects.
///
/// Moodle is inconsistent: numbers arrive as ints or strings, optional fields
/// are absent or `0`, and errors come back as HTTP 200 with an `exception`
/// object. Every parser tolerates that, never throws a raw [TypeError], and
/// maps a structurally invalid payload to [MoodleFailureKind.invalidResponse]
/// so the caller can keep the last good cache.

// ---------------------------------------------------------------------------
// Coercion helpers
// ---------------------------------------------------------------------------

int? _asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

int _asInt(Object? v, {int fallback = 0}) => _asIntOrNull(v) ?? fallback;

String _asString(Object? v, {String fallback = ''}) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

String? _asStringOrNull(Object? v) {
  if (v == null) return null;
  final String s = v is String ? v : v.toString();
  return s.isEmpty ? null : s;
}

bool _asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

/// Moodle timestamps are absolute Unix seconds. `0`/absent means "no date".
/// Converts to the correct instant without a second timezone shift.
DateTime? _dateFromUnix(Object? v) {
  final int? seconds = _asIntOrNull(v);
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

String _plain(Object? v) => htmlToSafeText(_asStringOrNull(v));

/// Like [_plain] but keeps `null` as `null` for optional fields.
String? _plainOrNull(Object? v) {
  final String? raw = _asStringOrNull(v);
  if (raw == null) return null;
  return htmlToSafeText(raw);
}

Never _invalid() =>
    throw const MoodleFailure(MoodleFailureKind.invalidResponse);

List<Object?> _asList(Object? v) {
  if (v is List) return v;
  _invalid();
}

Map<String, Object?> _asMap(Object? v) {
  if (v is Map) return v.cast<String, Object?>();
  _invalid();
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Extracts the token from `/login/token.php`, mapping login errors.
String parseToken(Object? json) {
  final Map<String, Object?> map = _asMap(json);
  final String? token = _asStringOrNull(map['token']);
  if (token != null) return token;

  final String? errorCode = _asStringOrNull(map['errorcode']);
  final bool hasError = map.containsKey('error') || errorCode != null;
  if (hasError) {
    switch (errorCode) {
      case 'invalidlogin':
      case 'invalid_login':
        throw const MoodleFailure(MoodleFailureKind.invalidCredentials);
      case 'sitemaintenance':
        throw const MoodleFailure(MoodleFailureKind.serviceUnavailable);
      default:
        // token.php mostly returns invalidlogin for wrong credentials.
        throw const MoodleFailure(MoodleFailureKind.invalidCredentials);
    }
  }
  throw const MoodleFailure(MoodleFailureKind.invalidResponse);
}

/// Returns a classified failure when [json] is a Moodle exception envelope,
/// else null. Moodle returns these with HTTP 200.
///
/// Only errors about the token or the Moodle account itself are reported as a
/// rejected sign-in. Everything else — a request parameter Moodle refuses, a
/// course deleted in the meantime, a code this app does not know — used to
/// tell the user to reconnect, which cannot fix any of them.
MoodleFailure? moodleExceptionOf(Object? json) {
  if (json is! Map) return null;
  if (!json.containsKey('exception')) return null;
  final String? code = _asStringOrNull(json['errorcode']);
  switch (code) {
    case 'invalidtoken':
    case 'wsaccessusersuspended':
    case 'wsaccessuserdeleted':
    case 'wsaccessusernologin':
      return const MoodleFailure(MoodleFailureKind.tokenRejected);
    case 'expiredtoken':
      return const MoodleFailure(MoodleFailureKind.tokenExpired);
    case 'invalidparameter':
      return const MoodleFailure(MoodleFailureKind.invalidResponse);
    case 'accessexception':
    case 'nopermissions':
    case 'requireloginerror':
    case 'notingroup':
      return const MoodleFailure(MoodleFailureKind.permissionDenied);
    case 'servicenotavailable':
    case 'sitemaintenance':
      return const MoodleFailure(MoodleFailureKind.serviceUnavailable);
    default:
      return const MoodleFailure(MoodleFailureKind.unknown);
  }
}

MoodleSiteInfo parseSiteInfo(Object? json) {
  final Map<String, Object?> map = _asMap(json);
  final int? userId = _asIntOrNull(map['userid']);
  if (userId == null) _invalid();
  return MoodleSiteInfo(
    userId: userId,
    username: _asStringOrNull(map['username']),
    fullName: _asStringOrNull(map['fullname']),
    siteName: _asStringOrNull(map['sitename']),
  );
}

// ---------------------------------------------------------------------------
// Courses
// ---------------------------------------------------------------------------

List<MoodleCourse> parseCourses(Object? json) {
  // The timeline endpoint is the same source Moodle Web's course overview
  // uses. Its response wraps the classified courses alongside `nextoffset`.
  final Map<String, Object?> response = _asMap(json);
  final List<Object?> list = _asList(response['courses']);
  final List<MoodleCourse> out = <MoodleCourse>[];
  for (final Object? raw in list) {
    if (raw is! Map) continue;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    final int? id = _asIntOrNull(m['id']);
    if (id == null) continue;
    out.add(
      MoodleCourse(
        id: id,
        fullName: _asString(
          m['fullname'],
          // Empty rather than a hardcoded German "Kurs 12" — the
          // presentation layer localises the fallback.
          fallback: _asString(m['displayname'], fallback: ''),
        ),
        shortName: _asString(m['shortname']),
        summary: _plain(m['summary']),
        startDate: _dateFromUnix(m['startdate']),
        endDate: _dateFromUnix(m['enddate']),
        progress: _asIntOrNull(m['progress']),
        hidden: _asBool(m['hidden']),
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Course contents (sections + modules + files)
// ---------------------------------------------------------------------------

List<MoodleSection> parseSections(Object? json) {
  final List<Object?> list = _asList(json);
  final List<MoodleSection> out = <MoodleSection>[];
  for (final Object? raw in list) {
    if (raw is! Map) continue;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    out.add(
      MoodleSection(
        name: _asString(m['name'], fallback: ''),
        summary: _plain(m['summary']),
        visible: m['visible'] == null ? true : _asBool(m['visible']),
        modules: _parseModules(m['modules']),
      ),
    );
  }
  return out;
}

List<MoodleModule> _parseModules(Object? json) {
  if (json is! List) return const <MoodleModule>[];
  final List<MoodleModule> out = <MoodleModule>[];
  for (final Object? raw in json) {
    if (raw is! Map) continue;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    final int? id = _asIntOrNull(m['id']);
    if (id == null) continue;
    final String rawType = _asString(m['modname']);
    final List<MoodleFile> files = _parseModuleContents(m['contents']);
    final String? externalUrl = _externalUrlFor(rawType, m, files);
    out.add(
      MoodleModule(
        id: id,
        name: _asString(m['name'], fallback: ''),
        type: MoodleModuleType.fromRaw(rawType),
        rawType: rawType,
        description: _plain(m['description']),
        url: externalUrl,
        visible: m['visible'] == null ? true : _asBool(m['visible']),
        // Every other text field goes through `_plain`; this one did not, so
        // a restricted module showed its raw <span> markup — in the very
        // state where the reader is asking "why can I not get in here?".
        availabilityInfo: _plainOrNull(m['availabilityinfo']),
        files: files,
        instanceId: _asIntOrNull(m['instance']),
      ),
    );
  }
  return out;
}

/// For a `url` module the single content entry is an external link, not a
/// Moodle file — surface it as [MoodleModule.url] (opened without a token) and
/// keep it out of the downloadable-files list.
String? _externalUrlFor(
  String rawType,
  Map<String, Object?> module,
  List<MoodleFile> files,
) {
  if (rawType != 'url') return null;
  final Object? contents = module['contents'];
  if (contents is List) {
    for (final Object? c in contents) {
      if (c is Map) {
        final String? u = _asStringOrNull(c['fileurl']);
        if (u != null) return u;
      }
    }
  }
  return _asStringOrNull(module['url']);
}

List<MoodleFile> _parseModuleContents(Object? json) {
  if (json is! List) return const <MoodleFile>[];
  final List<MoodleFile> out = <MoodleFile>[];
  for (final Object? raw in json) {
    if (raw is! Map) continue;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    // Only real files are downloadable; skip url/other content rows.
    final String type = _asString(m['type'], fallback: 'file');
    if (type != 'file') continue;
    final String? url = _asStringOrNull(m['fileurl']);
    final String? name = _asStringOrNull(m['filename']);
    if (url == null || name == null) continue;
    out.add(
      MoodleFile(
        fileName: name,
        fileUrl: url,
        mimeType: _asStringOrNull(m['mimetype']),
        fileSize: _asIntOrNull(m['filesize']),
        timeModified: _dateFromUnix(m['timemodified']),
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Assignments
// ---------------------------------------------------------------------------

List<MoodleAssignment> parseAssignments(Object? json) {
  final Map<String, Object?> map = _asMap(json);
  // A missing or mistyped course list is a broken answer, not "no
  // assignments": reading it as empty would overwrite the cached list.
  final List<Object?> courses = _asList(map['courses']);
  final List<MoodleAssignment> out = <MoodleAssignment>[];
  for (final Object? rawCourse in courses) {
    if (rawCourse is! Map) continue;
    final int courseId = _asInt(rawCourse['id']);
    final Object? assignments = rawCourse['assignments'];
    if (assignments is! List) continue;
    for (final Object? rawA in assignments) {
      if (rawA is! Map) continue;
      final Map<String, Object?> a = rawA.cast<String, Object?>();
      final int? id = _asIntOrNull(a['id']);
      if (id == null) continue;
      out.add(
        MoodleAssignment(
          id: id,
          courseId: _asIntOrNull(a['course']) ?? courseId,
          name: _asString(a['name'], fallback: ''),
          cmid: _asIntOrNull(a['cmid']),
          intro: _plain(a['intro']),
          dueDate: _dateFromUnix(a['duedate']),
          cutOffDate: _dateFromUnix(a['cutoffdate']),
        ),
      );
    }
  }
  return out;
}

MoodleSubmissionStatus parseSubmissionStatus(Object? json) {
  final Map<String, Object?> map = _asMap(json);
  final Object? lastAttempt = map['lastattempt'];
  MoodleSubmissionState state = MoodleSubmissionState.unknown;
  DateTime? submittedAt;
  if (lastAttempt is Map) {
    final Object? submission = lastAttempt['submission'];
    if (submission is Map) {
      state = MoodleSubmissionState.fromRaw(
        _asStringOrNull(submission['status']),
      );
      submittedAt = _dateFromUnix(submission['timemodified']);
    }
    final String? gradingStatus = _asStringOrNull(lastAttempt['gradingstatus']);
    if (gradingStatus == 'graded') {
      // handled below via feedback too
    }
  }

  bool graded = false;
  String? gradeText;
  final Object? feedback = map['feedback'];
  if (feedback is Map) {
    gradeText = _asStringOrNull(feedback['gradefordisplay']);
    final Object? grade = feedback['grade'];
    if (grade is Map && grade['grade'] != null) {
      graded = true;
      gradeText ??= _asStringOrNull(grade['grade']);
    }
    if (gradeText != null) graded = true;
  }
  // gradingstatus == graded is also a reliable signal.
  if (lastAttempt is Map &&
      _asStringOrNull(lastAttempt['gradingstatus']) == 'graded') {
    graded = true;
  }

  return MoodleSubmissionStatus(
    state: state,
    submittedAt: submittedAt,
    graded: graded,
    gradeText: gradeText == null ? null : htmlToSafeText(gradeText),
  );
}

// ---------------------------------------------------------------------------
// Announcements (news-forum discussions)
// ---------------------------------------------------------------------------

List<int> parseNewsForumIds(Object? json) {
  // `mod_forum_get_forums_by_courses` answers with a bare list. Anything else
  // is invalid and must not read as "this course has no announcements".
  final List<Object?> forums = _asList(json);
  final List<int> ids = <int>[];
  for (final Object? raw in forums) {
    if (raw is! Map) continue;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    if (_asString(m['type']) != 'news') continue;
    final int? id = _asIntOrNull(m['id']);
    if (id != null) ids.add(id);
  }
  return ids;
}

List<MoodleAnnouncement> parseDiscussions(
  Object? json, {
  required int courseId,
}) {
  // Same rule as above: only a real discussion list — possibly empty — is a
  // result. A missing or mistyped one throws so the cache is kept.
  final List<Object?> discussions = json is List
      ? json
      : _asList(_asMap(json)['discussions']);
  final List<MoodleAnnouncement> out = <MoodleAnnouncement>[];
  for (final Object? raw in discussions) {
    if (raw is! Map) continue;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    final int? id = _asIntOrNull(m['discussion']) ?? _asIntOrNull(m['id']);
    if (id == null) continue;
    out.add(
      MoodleAnnouncement(
        id: id,
        courseId: courseId,
        subject: _asString(m['subject'], fallback: _asString(m['name'])),
        message: _plain(m['message']),
        // Recovered from the original markup before it is flattened: the
        // reduction to plain text is what dropped every URL.
        links: htmlLinkTargets(_asStringOrNull(m['message'])),
        authorName: _asStringOrNull(m['userfullname']),
        createdAt:
            _dateFromUnix(m['created']) ?? _dateFromUnix(m['timemodified']),
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Deadlines (calendar action events)
// ---------------------------------------------------------------------------

List<MoodleDeadline> parseDeadlines(Object? json) {
  Object? events;
  if (json is Map) {
    events = json['events'];
  } else if (json is List) {
    events = json;
  }
  if (events is! List) return const <MoodleDeadline>[];
  final List<MoodleDeadline> out = <MoodleDeadline>[];
  for (final Object? raw in events) {
    if (raw is! Map) continue;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    final int? id = _asIntOrNull(m['id']);
    final DateTime? dueAt =
        _dateFromUnix(m['timesort']) ?? _dateFromUnix(m['timestart']);
    if (id == null || dueAt == null) continue;
    int? courseId;
    String? courseName;
    final Object? course = m['course'];
    if (course is Map) {
      courseId = _asIntOrNull(course['id']);
      courseName = _asStringOrNull(course['fullname']);
    }
    out.add(
      MoodleDeadline(
        id: id,
        title: _asString(m['name'], fallback: ''),
        dueAt: dueAt,
        courseId: courseId,
        courseName: courseName,
        moduleName: _asStringOrNull(m['modulename']),
        eventType: _asStringOrNull(m['eventtype']),
      ),
    );
  }
  return out;
}
