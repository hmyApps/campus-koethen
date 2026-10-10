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

  // D-07: the identity of a result row must not depend on its position in
  // the HISinOne tree. A renumbered tree (a module inserted above) used to
  // announce every already graded result below it as a "new grade".
  group('result identity is independent of the tree position', () {
    GradeEntry treeEntry({
      required String number,
      required String path,
      required Grade grade,
      String module = 'Modul A',
      String? attempt = '1',
    }) => GradeEntry(
      examNumber: number,
      title: 'Prüfung $number',
      grade: grade,
      status: grade.isEmpty ? ExamStatus.present : ExamStatus.passed,
      statusText: grade.isEmpty ? 'vorhanden' : 'bestanden',
      attempt: attempt,
      path: path,
      module: module,
    );

    test('a renumbered tree does not announce existing grades as new', () {
      final GradeReport previous = GradeReport(<GradeEntry>[
        treeEntry(number: '101', path: '1.1.1', grade: const Grade.graded(1.7)),
        treeEntry(number: '102', path: '1.1.2', grade: const Grade.graded(2.3)),
      ]);
      final GradeReport current = GradeReport(<GradeEntry>[
        treeEntry(
          number: '900',
          path: '1.1.1',
          grade: const Grade.none(),
          module: 'Neues Modul',
        ),
        treeEntry(number: '101', path: '1.2.1', grade: const Grade.graded(1.7)),
        treeEntry(number: '102', path: '1.2.2', grade: const Grade.graded(2.3)),
      ]);

      expect(newlyGradedEntries(previous: previous, current: current), isEmpty);
    });

    test('a pending result graded after renumbering is announced once', () {
      final GradeReport previous = GradeReport(<GradeEntry>[
        treeEntry(number: '101', path: '1.1.1', grade: const Grade.none()),
      ]);
      final GradeReport current = GradeReport(<GradeEntry>[
        treeEntry(number: '101', path: '1.2.1', grade: const Grade.graded(1.3)),
      ]);

      expect(
        newlyGradedEntries(
          previous: previous,
          current: current,
        ).map((GradeEntry e) => e.examNumber),
        <String>['101'],
      );
    });

    test('a second attempt of the same exam is its own result', () {
      final GradeReport previous = GradeReport(<GradeEntry>[
        treeEntry(number: '101', path: '1.1.1', grade: const Grade.graded(5.0)),
      ]);
      final GradeReport current = GradeReport(<GradeEntry>[
        treeEntry(number: '101', path: '1.1.1', grade: const Grade.graded(5.0)),
        treeEntry(
          number: '101',
          path: '1.1.2',
          grade: const Grade.graded(2.0),
          attempt: '2',
        ),
      ]);

      expect(
        newlyGradedEntries(
          previous: previous,
          current: current,
        ).map((GradeEntry e) => e.attempt),
        <String?>['2'],
      );
    });

    test('the same exam under two modules stays two results', () {
      final GradeReport previous = GradeReport(<GradeEntry>[
        treeEntry(number: '101', path: '1.1.1', grade: const Grade.graded(1.7)),
        treeEntry(
          number: '101',
          path: '1.2.1',
          grade: const Grade.none(),
          module: 'Modul B',
        ),
      ]);
      final GradeReport current = GradeReport(<GradeEntry>[
        treeEntry(number: '101', path: '1.1.1', grade: const Grade.graded(1.7)),
        treeEntry(
          number: '101',
          path: '1.2.1',
          grade: const Grade.graded(2.7),
          module: 'Modul B',
        ),
      ]);

      expect(
        newlyGradedEntries(
          previous: previous,
          current: current,
        ).map((GradeEntry e) => e.module),
        <String?>['Modul B'],
      );
    });

    test('rows without exam number and title fall back to their path', () {
      GradeEntry anonymous(String path, Grade grade) => GradeEntry(
        examNumber: '',
        title: '',
        grade: grade,
        status: grade.isEmpty ? ExamStatus.present : ExamStatus.passed,
        statusText: '',
        path: path,
      );
      final GradeReport previous = GradeReport(<GradeEntry>[
        anonymous('1.1', const Grade.graded(1.0)),
        anonymous('1.2', const Grade.none()),
      ]);
      final GradeReport current = GradeReport(<GradeEntry>[
        anonymous('1.1', const Grade.graded(1.0)),
        anonymous('1.2', const Grade.graded(2.0)),
      ]);

      expect(
        newlyGradedEntries(
          previous: previous,
          current: current,
        ).map((GradeEntry e) => e.path),
        <String?>['1.2'],
      );
    });
  });
}
