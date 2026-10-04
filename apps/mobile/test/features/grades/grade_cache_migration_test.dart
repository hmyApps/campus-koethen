// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/features/grades/data/encrypted_grade_cache.dart';
import 'package:campus_koethen/features/grades/domain/exam_report.dart';
import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const FlutterSecureStorage _storage = FlutterSecureStorage();

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('grade-cache-test-');
    Hive.init(directory.path);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  EncryptedBox boxNamed(String boxName, String keyName) => EncryptedBox(
    boxName: boxName,
    keyStorageKey: keyName,
    storage: _storage,
    hive: Hive,
    initializeHive: () async {},
  );

  test('the cache lives in the v2 box, not the v1 box', () async {
    final cache = EncryptedGradeCache(
      boxNamed('campus_grades_cache_v2', 'grades.cache.key.v2'),
    );
    final report = GradeReport(<GradeEntry>[
      const GradeEntry(
        examNumber: '1',
        title: 'Analysis I',
        grade: Grade.graded(1.7),
        status: ExamStatus.passed,
        statusText: 'bestanden',
        path: '1.1',
        module: 'Modul Mathematik',
        extras: <String, String>{'Vermerk': 'Nachschreiber'},
      ),
    ]);
    await cache.writeReport(report);

    final GradeReport? read = await cache.readReport();
    expect(read, isNotNull);
    expect(read!.entries.single.title, 'Analysis I');
    expect(read.entries.single.module, 'Modul Mathematik');
    expect(read.entries.single.extras['Vermerk'], 'Nachschreiber');

    // The old v1 box is untouched — a fresh install with a v1 box never
    // surfaces that data through the v2 cache.
    final EncryptedBox v1 = boxNamed(
      'campus_grades_cache_v1',
      'grades.cache.key.v1',
    );
    expect(await v1.read('report'), isNull);
  });

  test(
    'a pre-existing v1 box is simply never read: opening the v2 cache always '
    'succeeds and starts empty, never throwing on old content',
    () async {
      // Simulate a v1 install: some old-shaped JSON under the old box/key.
      final EncryptedBox v1 = boxNamed(
        'campus_grades_cache_v1',
        'grades.cache.key.v1',
      );
      await v1.write(
        'report',
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'examNumber': '1',
            'title': 'Altes Format',
            'gradeKind': 'graded',
            'gradeValue': 1.0,
            'status': 'passed',
            'statusText': 'bestanden',
          },
        ]),
      );

      final cache = EncryptedGradeCache(
        boxNamed('campus_grades_cache_v2', 'grades.cache.key.v2'),
      );

      // Never throws; simply behaves like any other empty cache.
      final GradeReport? read = await cache.readReport();
      expect(read, isNull);
    },
  );

  test('writeReport/readReport round-trips the exam-report offers alongside '
      'the entries', () async {
    final cache = EncryptedGradeCache(
      boxNamed('campus_grades_cache_v2', 'grades.cache.key.v2'),
    );
    final report = GradeReport(
      <GradeEntry>[
        const GradeEntry(
          examNumber: '1',
          title: 'Analysis I',
          grade: Grade.graded(1.7),
          status: ExamStatus.passed,
          statusText: 'bestanden',
        ),
      ],
      examReports: const <ExamReportOffer>[
        ExamReportOffer(
          buttonId:
              'examsReadonly:exaReports:fieldset_exaReports:printReport_0',
          label: 'Leistungsübersicht [PDF]',
        ),
      ],
    );
    await cache.writeReport(report);

    final GradeReport? read = await cache.readReport();
    expect(read, isNotNull);
    expect(read!.entries.single.title, 'Analysis I');
    expect(read.examReports, hasLength(1));
    expect(
      read.examReports.single.buttonId,
      'examsReadonly:exaReports:fieldset_exaReports:printReport_0',
    );
  });

  test('a report cached before examReports existed (a bare entries array, no '
      'wrapper) still reads correctly, with no exam reports rather than a '
      'thrown error', () async {
    final EncryptedBox box = boxNamed(
      'campus_grades_cache_v2',
      'grades.cache.key.v2',
    );
    await box.write(
      'report',
      jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'examNumber': '1',
          'title': 'Vor der Bescheinigungs-Funktion',
          'gradeKind': 'graded',
          'gradeValue': 1.0,
          'status': 'passed',
          'statusText': 'bestanden',
        },
      ]),
    );
    final cache = EncryptedGradeCache(box);

    final GradeReport? read = await cache.readReport();

    expect(read, isNotNull);
    expect(read!.entries.single.title, 'Vor der Bescheinigungs-Funktion');
    expect(read.examReports, isEmpty);
  });
}
