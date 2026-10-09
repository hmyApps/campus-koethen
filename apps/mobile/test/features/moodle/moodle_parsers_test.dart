// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer
//
// Parser unit tests. All fixtures are synthetic and use fictional courses
// ("Beispielkurs Informatik", "Musterseminar", "Übungsblatt 1"). No real
// Moodle data, no real credentials, no network call.

import 'dart:convert';

import 'package:campus_koethen/features/moodle/data/moodle_parsers.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_announcement.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_assignment.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_content.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_course.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_failure.dart';
import 'package:flutter_test/flutter_test.dart';

Object? decode(String s) => jsonDecode(s);

void main() {
  group('parseToken', () {
    test('returns the token on success', () {
      expect(
        parseToken(decode('{"token":"abcdef0123456789"}')),
        'abcdef0123456789',
      );
    });

    test('maps invalidlogin to invalidCredentials', () {
      expect(
        () => parseToken(
          decode('{"error":"Invalid login","errorcode":"invalidlogin"}'),
        ),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidCredentials)),
      );
    });

    test('throws invalidResponse when no token field', () {
      expect(
        () => parseToken(decode('{"foo":"bar"}')),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });
  });

  group('moodleExceptionOf', () {
    test('detects an invalid-token exception', () {
      final MoodleFailure? f = moodleExceptionOf(
        decode(
          '{"exception":"moodle_exception","errorcode":"invalidtoken","message":"x"}',
        ),
      );
      expect(f, const MoodleFailure(MoodleFailureKind.tokenRejected));
    });

    test('detects an access/permission exception', () {
      final MoodleFailure? f = moodleExceptionOf(
        decode(
          '{"exception":"webservice_access_exception","errorcode":"accessexception","message":"x"}',
        ),
      );
      expect(f, const MoodleFailure(MoodleFailureKind.permissionDenied));
    });

    test('returns null for a normal payload', () {
      expect(moodleExceptionOf(decode('{"userid":1}')), isNull);
    });

    test('keeps an expired token classified as expired', () {
      expect(
        moodleExceptionOf(
          decode(
            '{"exception":"moodle_exception","errorcode":"expiredtoken","message":"x"}',
          ),
        ),
        const MoodleFailure(MoodleFailureKind.tokenExpired),
      );
    });

    test('a rejected request parameter is not a rejected sign-in', () {
      expect(
        moodleExceptionOf(
          decode(
            '{"exception":"invalid_parameter_exception","errorcode":"invalidparameter","message":"x"}',
          ),
        ),
        const MoodleFailure(MoodleFailureKind.invalidResponse),
      );
    });

    test('an unknown exception is unknown, not a rejected sign-in', () {
      // For example a course that was deleted in the meantime.
      expect(
        moodleExceptionOf(
          decode(
            '{"exception":"dml_missing_record_exception","errorcode":"invalidrecord","message":"x"}',
          ),
        ),
        const MoodleFailure(MoodleFailureKind.unknown),
      );
    });

    test('an exception without an error code is unknown', () {
      expect(
        moodleExceptionOf(decode('{"exception":"moodle_exception"}')),
        const MoodleFailure(MoodleFailureKind.unknown),
      );
    });

    test('a suspended or deleted Moodle account rejects the sign-in', () {
      for (final String code in <String>[
        'wsaccessusersuspended',
        'wsaccessuserdeleted',
        'wsaccessusernologin',
      ]) {
        expect(
          moodleExceptionOf(
            decode(
              '{"exception":"moodle_exception","errorcode":"$code","message":"x"}',
            ),
          ),
          const MoodleFailure(MoodleFailureKind.tokenRejected),
          reason: code,
        );
      }
    });
  });

  group('parseSiteInfo', () {
    test('reads user id and names', () {
      final info = parseSiteInfo(
        decode(
          '{"userid":4242,"username":"s123456","fullname":"Vorname Nachname","sitename":"Moodle Demo"}',
        ),
      );
      expect(info.userId, 4242);
      expect(info.username, 's123456');
      expect(info.siteName, 'Moodle Demo');
    });
  });

  group('parseCourses', () {
    const String fixture = '''
{"courses":[
  {"id":101,"shortname":"INF-BEISPIEL","fullname":"Beispielkurs Informatik",
   "summary":"<p>Ein <b>Demo</b>-Kurs.</p><script>alert(1)</script>",
   "startdate":1704067200,"enddate":0,"progress":42,"hidden":0},
  {"id":102,"fullname":"Musterseminar","shortname":"","summary":"","progress":null,"hidden":1}
],"nextoffset":2}''';

    test('parses courses and strips HTML/scripts from the summary', () {
      final List<MoodleCourse> courses = parseCourses(decode(fixture));
      expect(courses, hasLength(2));
      expect(courses.first.id, 101);
      expect(courses.first.fullName, 'Beispielkurs Informatik');
      expect(courses.first.summary, 'Ein Demo-Kurs.');
      expect(courses.first.summary, isNot(contains('alert')));
      expect(courses.first.progress, 42);
      expect(courses.first.startDate, isNotNull);
      expect(courses.first.endDate, isNull); // enddate 0 -> null
    });

    test('handles a missing progress and hidden flag', () {
      final List<MoodleCourse> courses = parseCourses(decode(fixture));
      expect(courses[1].progress, isNull);
      expect(courses[1].hidden, isTrue);
    });

    test('throws invalidResponse without a timeline course list', () {
      expect(
        () => parseCourses(decode('{"notCourses":[]}')),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });
  });

  group('parseSections', () {
    const String fixture = '''
[
 {"name":"Allgemeines","summary":"<p>Intro</p>","visible":1,"modules":[
   {"id":5001,"name":"Übungsblatt 1","modname":"resource","description":"<p>PDF</p>","visible":1,
    "contents":[{"type":"file","filename":"uebung1.pdf",
      "fileurl":"https://moodle.hs-anhalt.de/webservice/pluginfile.php/1/mod_resource/content/1/uebung1.pdf",
      "mimetype":"application/pdf","filesize":12345,"timemodified":1704153600}]},
   {"id":5002,"name":"Externer Link","modname":"url",
    "contents":[{"type":"url","fileurl":"https://example.org/extern"}]},
   {"id":5003,"name":"Aufgabe","modname":"assign","instance":9001},
   {"id":5004,"name":"Etwas Neues","modname":"h5pactivity"}
 ]}
]''';

    test('parses sections, module types and files', () {
      final List<MoodleSection> sections = parseSections(decode(fixture));
      expect(sections, hasLength(1));
      final MoodleSection s = sections.first;
      expect(s.name, 'Allgemeines');
      expect(s.summary, 'Intro');
      expect(s.modules, hasLength(4));

      final MoodleModule resource = s.modules[0];
      expect(resource.type, MoodleModuleType.resource);
      expect(resource.files, hasLength(1));
      expect(resource.files.first.fileName, 'uebung1.pdf');
      expect(resource.files.first.mimeType, 'application/pdf');
      expect(resource.files.first.fileSize, 12345);
    });

    test('keeps the external url for url modules', () {
      final MoodleModule url = parseSections(decode(fixture)).first.modules[1];
      expect(url.type, MoodleModuleType.url);
      expect(url.url, 'https://example.org/extern');
    });

    test('exposes the assignment instance id', () {
      final MoodleModule assign = parseSections(
        decode(fixture),
      ).first.modules[2];
      expect(assign.type, MoodleModuleType.assign);
      expect(assign.instanceId, 9001);
    });

    test('degrades an unknown module type to unknown, not dropped', () {
      final MoodleModule unknown = parseSections(
        decode(fixture),
      ).first.modules[3];
      expect(unknown.type, MoodleModuleType.unknown);
      expect(unknown.rawType, 'h5pactivity');
      expect(unknown.name, 'Etwas Neues');
    });
  });

  group('parseAssignments', () {
    const String fixture = '''
{"courses":[{"id":101,"assignments":[
  {"id":9001,"cmid":5003,"course":101,"name":"Übungsblatt 1 Abgabe",
   "intro":"<p>Bitte abgeben</p>","duedate":1704672000,"cutoffdate":0}
]}]}''';

    test('parses assignments with due dates', () {
      final List<MoodleAssignment> a = parseAssignments(decode(fixture));
      expect(a, hasLength(1));
      expect(a.first.id, 9001);
      expect(a.first.courseId, 101);
      expect(a.first.name, 'Übungsblatt 1 Abgabe');
      expect(a.first.intro, 'Bitte abgeben');
      expect(a.first.dueDate, isNotNull);
      expect(a.first.cutOffDate, isNull);
    });

    // AGENTS §4: a structurally wrong answer must never read as "no
    // assignments", or the next write replaces the cached list with nothing.
    test('throws invalidResponse when the course list is missing', () {
      expect(
        () => parseAssignments(decode('{"warnings":[]}')),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });

    test('throws invalidResponse when the course list is not a list', () {
      expect(
        () => parseAssignments(decode('{"courses":{"id":101}}')),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });

    test('a valid empty course list is still an empty result', () {
      expect(parseAssignments(decode('{"courses":[],"warnings":[]}')), isEmpty);
    });
  });

  group('parseSubmissionStatus', () {
    test('reads a submitted, graded status', () {
      final MoodleSubmissionStatus s = parseSubmissionStatus(
        decode(
          '''
{"lastattempt":{"submission":{"status":"submitted","timemodified":1704600000}},
 "gradingsummary":null,
 "feedback":{"grade":{"grade":"17.00000"},"gradefordisplay":"17,00 / 20,00"}}''',
        ),
      );
      expect(s.state, MoodleSubmissionState.submitted);
      expect(s.submittedAt, isNotNull);
      expect(s.graded, isTrue);
      expect(s.gradeText, '17,00 / 20,00');
    });

    test('reads a not-started status', () {
      final MoodleSubmissionStatus s = parseSubmissionStatus(
        decode('{"lastattempt":{"submission":{"status":"new"}}}'),
      );
      expect(s.state, MoodleSubmissionState.none);
      expect(s.graded, isFalse);
    });
  });

  group('parseDeadlines', () {
    const String fixture = '''
{"events":[
  {"id":7001,"name":"Übungsblatt 1 ist fällig","timesort":1704672000,"timestart":1704672000,
   "modulename":"assign","eventtype":"due",
   "course":{"id":101,"fullname":"Beispielkurs Informatik"},
   "url":"https://moodle.hs-anhalt.de/mod/assign/view.php?id=5003"}
]}''';

    test('parses events into deadlines with absolute instants', () {
      final List<MoodleDeadline> d = parseDeadlines(decode(fixture));
      expect(d, hasLength(1));
      expect(d.first.id, 7001);
      expect(d.first.title, 'Übungsblatt 1 ist fällig');
      expect(d.first.courseId, 101);
      expect(d.first.courseName, 'Beispielkurs Informatik');
      expect(d.first.moduleName, 'assign');
      // 1704672000 s = 2024-01-08T00:00:00Z
      expect(d.first.dueAt.toUtc(), DateTime.utc(2024, 1, 8, 0, 0, 0));
    });
  });

  group('parseDiscussions', () {
    test('parses announcements and strips HTML', () {
      final List<MoodleAnnouncement> a = parseDiscussions(
        decode('''
{"discussions":[
  {"id":8001,"discussion":8001,"subject":"Willkommen","message":"<p>Hallo <i>Welt</i></p>",
   "userfullname":"Dozent Demo","created":1704067200,"timemodified":1704067200}
]}'''),
        courseId: 101,
      );
      expect(a, hasLength(1));
      expect(a.first.subject, 'Willkommen');
      expect(a.first.message, 'Hallo Welt');
      expect(a.first.authorName, 'Dozent Demo');
      expect(a.first.courseId, 101);
    });

    test('a valid empty discussion list is still an empty result', () {
      expect(
        parseDiscussions(
          decode('{"discussions":[],"warnings":[]}'),
          courseId: 101,
        ),
        isEmpty,
      );
    });

    test('throws invalidResponse when the discussion list is missing', () {
      expect(
        () => parseDiscussions(decode('{"warnings":[]}'), courseId: 101),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });

    test('throws invalidResponse when the discussion list is not a list', () {
      expect(
        () => parseDiscussions(decode('{"discussions":"x"}'), courseId: 101),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });

    test('throws invalidResponse for an absent body', () {
      expect(
        () => parseDiscussions(null, courseId: 101),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });
  });

  group('parseNewsForumIds', () {
    test('returns only news-forum ids', () {
      final List<int> ids = parseNewsForumIds(
        decode('''
[{"id":3001,"course":101,"type":"news","name":"Ankündigungen"},
 {"id":3002,"course":101,"type":"general","name":"Allgemeines Forum"}]'''),
      );
      expect(ids, <int>[3001]);
    });

    test('a valid empty forum list is still an empty result', () {
      expect(parseNewsForumIds(decode('[]')), isEmpty);
    });

    test('throws invalidResponse when the forum list is not a list', () {
      expect(
        () => parseNewsForumIds(decode('{"forums":[]}')),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });

    test('throws invalidResponse for an absent body', () {
      expect(
        () => parseNewsForumIds(null),
        throwsA(const MoodleFailure(MoodleFailureKind.invalidResponse)),
      );
    });
  });
}
