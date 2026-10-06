// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:campus_koethen/features/grades/domain/grade_change.dart';
import 'package:flutter_test/flutter_test.dart';

GradeEntry entry({
  required String number,
  required Grade grade,
  String? path,
  bool isLeaf = true,
}) => GradeEntry(
  examNumber: number,
  title: 'Modul $number',
  grade: grade,
  status: grade.isEmpty ? ExamStatus.present : ExamStatus.passed,
  statusText: grade.isEmpty ? 'vorhanden' : 'bestanden',
  path: path,
  isLeaf: isLeaf,
);

void main() {
  test(
    'first successful report establishes a baseline without a notification',
    () {
      final GradeReport current = GradeReport(<GradeEntry>[
        entry(number: '101', grade: const Grade.graded(1.7)),
      ]);

      expect(newlyGradedEntries(previous: null, current: current), isEmpty);
    },
  );

  test('detects a new numeric or ungraded result exactly once', () {
    final GradeReport previous = GradeReport(<GradeEntry>[
      entry(number: '101', path: '1.1', grade: const Grade.none()),
      entry(number: '102', path: '1.2', grade: const Grade.none()),
    ]);
    final GradeReport current = GradeReport(<GradeEntry>[
      entry(number: '101', path: '1.1', grade: const Grade.graded(1.7)),
      entry(number: '102', path: '1.2', grade: const Grade.passedUngraded()),
    ]);

    expect(
      newlyGradedEntries(
        previous: previous,
        current: current,
      ).map((GradeEntry e) => e.examNumber),
      <String>['101', '102'],
    );
    expect(newlyGradedEntries(previous: current, current: current), isEmpty);
  });

  test('does not call a corrected existing grade a newly entered grade', () {
    final GradeReport previous = GradeReport(<GradeEntry>[
      entry(number: '101', grade: const Grade.graded(2.0)),
    ]);
    final GradeReport current = GradeReport(<GradeEntry>[
      entry(number: '101', grade: const Grade.graded(1.7)),
    ]);

    expect(newlyGradedEntries(previous: previous, current: current), isEmpty);
  });

  test('ignores newly graded aggregate tree nodes', () {
    final GradeReport previous = GradeReport(<GradeEntry>[
      entry(number: 'sum', path: '1', grade: const Grade.none(), isLeaf: false),
    ]);
    final GradeReport current = GradeReport(<GradeEntry>[
      entry(
        number: 'sum',
        path: '1',
        grade: const Grade.graded(1.9),
        isLeaf: false,
      ),
    ]);

    expect(newlyGradedEntries(previous: previous, current: current), isEmpty);
  });
}
