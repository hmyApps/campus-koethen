// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/data/his_in_one_html_parser.dart';
import 'package:campus_koethen/features/grades/domain/exam_report.dart';
import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:campus_koethen/features/grades/domain/grade_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import 'his_in_one_fixtures.dart';

void main() {
  _readOverviewTests();

  group('findExpandRequest', () {
    test(
      'collects the form action, ALL hidden fields and the expandAll2 button',
      () async {
        final HisInOneExpandRequest? req =
            await HisInOneHtmlParser.findExpandRequest(
              hisInOneCollapsedOverviewHtml,
            );
        expect(req, isNotNull);
        expect(
          req!.action,
          '/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml',
        );
        expect(req.hiddenFields['authenticity_token'], 'TOKEN-XYZ');
        expect(req.hiddenFields['javax.faces.ViewState'], 'VIEWSTATE-1');
        expect(req.hiddenFields['examsReadonly_SUBMIT'], '1');
        expect(
          req.hiddenFields['_flowExecutionKey'],
          'e1s3',
          reason: 'never hard-coded, always taken from the loaded page',
        );
        expect(
          req.buttonName,
          'examsReadonly:overviewAsTreeReadonly:expandAll2',
        );
      },
    );

    test(
      'falls back to the :expandAll suffix when :expandAll2 is absent',
      () async {
        final HisInOneExpandRequest? req =
            await HisInOneHtmlParser.findExpandRequest(
              hisInOneCollapsedOverviewFallbackButtonHtml,
            );
        expect(req, isNotNull);
        expect(
          req!.buttonName,
          'examsReadonly:overviewAsTreeReadonly:expandAll',
        );
      },
    );

    test('returns null when the examsReadonly form is missing', () async {
      expect(
        await HisInOneHtmlParser.findExpandRequest(hisInOneNoFormHtml),
        isNull,
      );
    });
  });

  group('findExamReports', () {
    test('reads all three print buttons by their stable class', () async {
      final List<ExamReportOffer> offers =
          await HisInOneHtmlParser.findExamReports(hisInOneExamReportsHtml);

      expect(offers, hasLength(3));
      expect(
        offers[0].buttonId,
        'examsReadonly:exaReports:fieldset_exaReports:printReport_0',
      );
      expect(
        offers[0].label,
        'Leistungsübersicht (bestandene Leistungen) / '
        'List of passed exam (german) [PDF]',
      );
      expect(
        offers[2].buttonId,
        'examsReadonly:exaReports:fieldset_exaReports:printReport_2',
      );
    });

    test('an overview with no Bescheinigungen section yields an empty list, '
        'never an error', () async {
      expect(
        await HisInOneHtmlParser.findExamReports(hisInOneNoExamReportsHtml),
        isEmpty,
      );
    });
  });

  group('buildExamReportPostRequest', () {
    test(
      'submits the real full-POST shape: the form action, every hidden '
      'field, the chosen button\'s own name/value and DISABLE_VALIDATION',
      () async {
        final HisInOneFullPostRequest? request =
            await HisInOneHtmlParser.buildExamReportPostRequest(
              hisInOneExamReportsHtml,
              'examsReadonly:exaReports:fieldset_exaReports:printReport_0',
            );

        expect(request, isNotNull);
        expect(
          request!.action,
          '/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml'
          '?_flowId=examsOverviewForPerson-flow&_flowExecutionKey=e8s1',
        );
        expect(request.formData['authenticity_token'], 'TOKEN-XYZ');
        expect(request.formData['javax.faces.ViewState'], 'e8s1');
        expect(request.formData['examsReadonly_SUBMIT'], '1');
        expect(
          request
              .formData['examsReadonly:exaReports:fieldset_exaReports:printReport_0'],
          'Leistungsübersicht (bestandene Leistungen) / '
          'List of passed exam (german) [PDF]',
        );
        expect(request.formData['DISABLE_VALIDATION'], 'true');
      },
    );

    test('a button id not on the page yields null, never a guess', () async {
      expect(
        await HisInOneHtmlParser.buildExamReportPostRequest(
          hisInOneExamReportsHtml,
          'examsReadonly:exaReports:fieldset_exaReports:printReport_9',
        ),
        isNull,
      );
    });
  });

  group('parseGradeReport', () {
    late GradeReport report;
    setUp(
      () async => report = await HisInOneHtmlParser.parseGradeReport(
        hisInOneExpandedTreeHtml,
      ),
    );

    test(
      'returns EVERY tree row — module and root containers included, flagged '
      'via isLeaf rather than dropped',
      () {
        // All 9 rows of the fixture, not just the 5 leaves: a leaf filter in
        // the parser would silently drop the (non-leaf) C-Sammelkonto average
        // row before GradeProjection ever sees it (the regression this
        // fixture exists for).
        expect(report.entries, hasLength(9));
        expect(
          report.entries.map((GradeEntry e) => e.title),
          contains('Bachelor Angewandte Informatik'),
        );
        expect(
          report.entries.map((GradeEntry e) => e.title),
          contains('Modul Mathematik'),
        );
        final GradeEntry root = report.entries.firstWhere(
          (GradeEntry e) => e.path == '1',
        );
        final GradeEntry module = report.entries.firstWhere(
          (GradeEntry e) => e.path == '1.1',
        );
        expect(root.isLeaf, isFalse);
        expect(module.isLeaf, isFalse);
      },
    );

    test('never matches the Studienverlauf decoy table', () {
      expect(
        report.entries.map((GradeEntry e) => e.title),
        isNot(contains('Decoy-Wurzel')),
      );
    });

    test('reads a dot-decimal grade and groups leaves under their module', () {
      final GradeEntry pass = report.entries.firstWhere(
        (GradeEntry e) => e.path == '1.1.1',
      );
      expect(pass.title, 'Mathematik I');
      expect(pass.grade.isGraded, isTrue);
      expect(pass.grade.value, 1.7);
      expect(pass.status, ExamStatus.passed);
      expect(pass.module, 'Modul Mathematik');
      expect(pass.examNumber, '11111');
      expect(pass.attempt, '1');
      expect(pass.isLeaf, isTrue);
    });

    test('maps the NB code to failed (a retake, not deduplicated)', () {
      final Iterable<GradeEntry> mathRows = report.entries.where(
        (GradeEntry e) => e.title == 'Mathematik I',
      );
      expect(mathRows, hasLength(2));
      expect(
        mathRows.map((GradeEntry e) => e.status),
        containsAll(<ExamStatus>[ExamStatus.passed, ExamStatus.failed]),
      );
      final GradeEntry retake = mathRows.firstWhere(
        (GradeEntry e) => e.status == ExamStatus.failed,
      );
      expect(retake.grade.value, 4.0);
      expect(retake.extras['Vermerk'], 'Nachschreiber');
    });

    test('parses Freigabedatum as dd.MM.yyyy HH:mm:ss', () {
      final GradeEntry pass = report.entries.firstWhere(
        (GradeEntry e) => e.path == '1.1.1',
      );
      expect(pass.examDate, DateTime(2026, 2, 12, 10, 15, 0));
    });

    test(
      'empty Bewertung + Status BE is passed-ungraded, Bonus is kept as-is',
      () {
        final GradeEntry seminar = report.entries.firstWhere(
          (GradeEntry e) => e.path == '1.2.1',
        );
        expect(seminar.grade.isPassedUngraded, isTrue);
        expect(
          seminar.bonus,
          '5',
          reason: 'never reinterpreted as ECTS credits',
        );
        expect(seminar.module, 'Modul Programmierung');
      },
    );

    test(
      'C-Sammelkonto is classified like Credit-Sammelkonto (average row)',
      () {
        final GradeEntry avg = report.entries.firstWhere(
          (GradeEntry e) => e.path == '1.3',
        );
        expect(avg.title, 'C-Sammelkonto');
        expect(avg.grade.value, 2.1);
        expect(avg.module, 'Bachelor Angewandte Informatik');
        expect(
          avg.isLeaf,
          isFalse,
          reason:
              'the average row is an inner node in the real portal — it '
              'must still be present in the report, just not shown as a '
              'result',
        );
      },
    );

    test('an unknown status code stays visible with its original text', () {
      final GradeEntry cert = report.entries.firstWhere(
        (GradeEntry e) => e.path == '2',
      );
      expect(cert.status, ExamStatus.unknown);
      expect(cert.statusText, 'XX');
      expect(cert.module, isNull, reason: 'a second root has no parent');
    });

    test('multiple roots are all represented (n roots)', () {
      final Iterable<GradeEntry> topLevelDescendants = report.entries.where(
        (GradeEntry e) => e.path == '1.3' || e.path == '2',
      );
      expect(topLevelDescendants, hasLength(2));
    });
  });

  group('structure validation', () {
    test('missing Status column yields portalStructureChanged', () async {
      await expectLater(
        HisInOneHtmlParser.parseGradeReport(hisInOneStructureChangedHtml),
        throwsA(
          isA<GradeFailure>().having(
            (GradeFailure e) => e.kind,
            'kind',
            GradeFailureKind.portalStructureChanged,
          ),
        ),
      );
    });

    test(
      'a page without the pinned container id yields portalStructureChanged',
      () async {
        await expectLater(
          HisInOneHtmlParser.parseGradeReport(hisInOneLoginFormHtml),
          throwsA(isA<GradeFailure>()),
        );
      },
    );
  });

  test('recognises the login form (shared with the legacy portal)', () async {
    expect(
      await HisInOneHtmlParser.hasLoginForm(hisInOneLoginFormHtml),
      isTrue,
    );
    expect(
      await HisInOneHtmlParser.hasLoginForm(hisInOneExpandedTreeHtml),
      isFalse,
    );
  });

  group('isAuthenticated', () {
    test('is false on the anonymous login page', () async {
      expect(
        await HisInOneHtmlParser.isAuthenticated(hisInOneLoginFormHtml),
        isFalse,
      );
    });

    test('is true on an authenticated page even though it still renders the '
        'hidden sessionTimeoutLoginForm (asdf/fdsa) — the regression that made '
        'every login fail regardless of correct credentials', () async {
      expect(
        await HisInOneHtmlParser.hasLoginForm(hisInOneAuthenticatedLandingHtml),
        isTrue,
        reason:
            'sessionTimeoutLoginForm renders asdf/fdsa on every page, so '
            'hasLoginForm alone cannot tell success from failure here',
      );
      expect(
        await HisInOneHtmlParser.isAuthenticated(
          hisInOneAuthenticatedLandingHtml,
        ),
        isTrue,
      );
    });
  });
}

/// Regression group for LEVIORA-154: the deployed portal build renders an
/// account without results as an EMPTY Leistungsdaten section (no tree, no
/// expand-all button). That used to be indistinguishable from an unknown page
/// and was reported as `portalStructureChanged`.
void _readOverviewTests() {
  group('readOverview', () {
    test(
      'an empty Leistungsdaten section is `empty`, never a structure change '
      '— even though the Studienverlauf section below it does hold a tree',
      () async {
        final HisInOneOverview overview = await HisInOneHtmlParser.readOverview(
          hisInOneEmptyOverviewHtml,
        );
        expect(overview.kind, HisInOneOverviewKind.empty);
        expect(overview.expandRequest, isNull);
      },
    );

    test('a tree without any expand-all control is `rendered`', () async {
      final HisInOneOverview overview = await HisInOneHtmlParser.readOverview(
        hisInOneRenderedTreeNoExpandAllHtml,
      );
      expect(overview.kind, HisInOneOverviewKind.rendered);
      expect(overview.expandRequest, isNull);
    });

    test(
      'a collapsed tree with an expand-all button is `expandable`',
      () async {
        final HisInOneOverview overview = await HisInOneHtmlParser.readOverview(
          hisInOneCollapsedOverviewHtml,
        );
        expect(overview.kind, HisInOneOverviewKind.expandable);
        expect(overview.expandRequest, isNotNull);
      },
    );

    test(
      'a page that is not the exam overview at all is `unrecognised`',
      () async {
        final HisInOneOverview overview = await HisInOneHtmlParser.readOverview(
          hisInOneNoFormHtml,
        );
        expect(overview.kind, HisInOneOverviewKind.unrecognised);
      },
    );
  });

  group('parseGradeReport (deployed portal build)', () {
    test(
      'reads a tree nested directly under the Leistungsdaten section, '
      'without the older :tree:ExamOverviewForPersonTreeReadonly id',
      () async {
        final GradeReport report = await HisInOneHtmlParser.parseGradeReport(
          hisInOneRenderedTreeNoExpandAllHtml,
        );
        expect(report.entries, hasLength(3));
        expect(
          report.entries.map((GradeEntry e) => e.title),
          containsAll(<String>['Mathematik I']),
        );
        // The Studienverlauf decoy must never leak in.
        expect(
          report.entries.any((GradeEntry e) => e.title == 'Decoy-Wurzel'),
          isFalse,
        );
      },
    );
  });
}
