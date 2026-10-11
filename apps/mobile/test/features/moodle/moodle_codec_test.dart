// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/moodle/data/moodle_codec.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_announcement.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_assignment.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_cache.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_content.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_course.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('courses round-trip through the codec', () {
    final List<MoodleCourse> courses = <MoodleCourse>[
      MoodleCourse(
        id: 101,
        fullName: 'Beispielkurs Informatik',
        shortName: 'INF',
        summary: 'Demo',
        startDate: DateTime.fromMillisecondsSinceEpoch(1704067200 * 1000),
        progress: 42,
        hidden: false,
      ),
      const MoodleCourse(id: 102, fullName: 'Musterseminar'),
    ];
    expect(decodeCourses(encodeCourses(courses)), courses);
  });

  test('deadlines round-trip and preserve the exact instant', () {
    final List<MoodleDeadline> deadlines = <MoodleDeadline>[
      MoodleDeadline(
        id: 7001,
        title: 'Übungsblatt 1 ist fällig',
        dueAt: DateTime.fromMillisecondsSinceEpoch(1704672000 * 1000),
        courseId: 101,
        courseName: 'Beispielkurs Informatik',
        moduleName: 'assign',
        eventType: 'due',
      ),
    ];
    final List<MoodleDeadline> back = decodeDeadlines(
      encodeDeadlines(deadlines),
    );
    expect(back, deadlines);
    expect(back.first.dueAt.millisecondsSinceEpoch, 1704672000 * 1000);
  });

  test('sections with modules and files round-trip', () {
    final List<MoodleSection> sections = <MoodleSection>[
      const MoodleSection(
        name: 'Allgemeines',
        summary: 'Intro',
        modules: <MoodleModule>[
          MoodleModule(
            id: 5001,
            name: 'Übungsblatt 1',
            type: MoodleModuleType.resource,
            rawType: 'resource',
            files: <MoodleFile>[
              MoodleFile(
                fileName: 'uebung1.pdf',
                fileUrl: 'https://moodle.hs-anhalt.de/x.pdf',
                mimeType: 'application/pdf',
                fileSize: 12345,
              ),
            ],
          ),
        ],
      ),
    ];
    expect(decodeSections(encodeSections(sections)), sections);
  });

  test('assignments (with status) round-trip', () {
    final List<MoodleAssignment> items = <MoodleAssignment>[
      MoodleAssignment(
        id: 9001,
        courseId: 101,
        name: 'Abgabe',
        dueDate: DateTime.fromMillisecondsSinceEpoch(1704672000 * 1000),
        status: MoodleSubmissionStatus(
          state: MoodleSubmissionState.submitted,
          submittedAt: DateTime.fromMillisecondsSinceEpoch(1704600000 * 1000),
          graded: true,
          gradeText: '17 / 20',
        ),
      ),
    ];
    expect(decodeAssignments(encodeAssignments(items)), items);
  });

  test('announcements round-trip', () {
    final List<MoodleAnnouncement> items = <MoodleAnnouncement>[
      MoodleAnnouncement(
        id: 8001,
        courseId: 101,
        subject: 'Willkommen',
        message: 'Hallo Welt',
        authorName: 'Dozent Demo',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1704067200 * 1000),
      ),
    ];
    expect(decodeAnnouncements(encodeAnnouncements(items)), items);
  });

  test('sync marks round-trip', () {
    final MoodleSyncMarks marks = MoodleSyncMarks(
      lastAttempt: DateTime.fromMillisecondsSinceEpoch(1704672000 * 1000),
      lastSuccess: DateTime.fromMillisecondsSinceEpoch(1704600000 * 1000),
    );
    final MoodleSyncMarks back = decodeMarks(encodeMarks(marks));
    expect(back.lastAttempt, marks.lastAttempt);
    expect(back.lastSuccess, marks.lastSuccess);
    expect(back.deadlinesConfirmed, isTrue);
  });

  test('sync marks keep an unconfirmed deadline list across a restart', () {
    const MoodleSyncMarks marks = MoodleSyncMarks(deadlinesConfirmed: false);
    expect(decodeMarks(encodeMarks(marks)).deadlinesConfirmed, isFalse);
    // Marks written before the flag existed describe a confirmed list.
    expect(decodeMarks('{"lastAttempt":null}').deadlinesConfirmed, isTrue);
  });

  test(
    'decoding malformed JSON throws (so the store can treat it as empty)',
    () {
      expect(() => decodeCourses('not json'), throwsA(isA<Object>()));
    },
  );
}
