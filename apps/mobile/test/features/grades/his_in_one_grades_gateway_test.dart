// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/data/his_in_one_grades_gateway.dart';
import 'package:campus_koethen/features/grades/domain/exam_report.dart';
import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/domain/grade_failure.dart';
import 'package:campus_koethen/features/grades/domain/his_in_one_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_html_adapter.dart';
import 'his_in_one_fixtures.dart';

const GradeCredentials _creds = GradeCredentials(
  username: 'testuser',
  password: 'test-pw',
);

const String _landingUrl =
    'https://sscportal.ssc.hs-anhalt.de/qisserver/rds?state=user&category=menu.browse';

/// The default happy-path script: login → landing → collapsed overview →
/// expand-all → (logout).
FakeHtmlResponse _happyPath(RequestOptions o) {
  final String url = o.uri.toString();
  if (url.contains('auth.login')) {
    return const FakeHtmlResponse.redirect(_landingUrl);
  }
  if (url.contains('auth.logout')) {
    return const FakeHtmlResponse('bye');
  }
  if (url.contains('personExamsReadonly.xhtml') && o.method == 'GET') {
    return const FakeHtmlResponse(hisInOneCollapsedOverviewHtml);
  }
  if (url.contains('personExamsReadonly.xhtml') && o.method == 'POST') {
    return FakeHtmlResponse(hisInOneExpandedTreeHtml);
  }
  if (url == _landingUrl) {
    // Deliberately includes the ever-present `sessionTimeoutLoginForm`
    // (asdf/fdsa) alongside the logout link — the regression case that made
    // every login fail regardless of correct credentials (see
    // `HisInOneHtmlParser.isAuthenticated`).
    return const FakeHtmlResponse(hisInOneAuthenticatedLandingHtml);
  }
  return const FakeHtmlResponse('not found', statusCode: 404);
}

void main() {
  _deployedPortalBuildTests();

  test(
    'logs in form-urlencoded (asdf/fdsa) to the HTTPS HISinOne host',
    () async {
      final adapter = FakeHtmlAdapter(_happyPath);
      final gateway = HisInOneGradesGateway(const HisInOneProfile(), adapter);

      final GradeReport report = await gateway.fetchGrades(_creds);
      expect(report.entries, hasLength(9));

      final RequestOptions login = adapter.requests.firstWhere(
        (RequestOptions o) => o.uri.toString().contains('auth.login'),
      );
      expect(login.method, 'POST');
      expect(login.contentType, contains('application/x-www-form-urlencoded'));
      expect(login.data, <String, String>{
        'asdf': 'testuser',
        'fdsa': 'test-pw',
      });
      expect(login.uri.scheme, 'https');
      expect(login.uri.host, 'sscportal.ssc.hs-anhalt.de');
    },
  );

  test(
    'sends every hidden field from the loaded page (never hard-coded) and the '
    'expandAll2 button, then logs out',
    () async {
      final adapter = FakeHtmlAdapter(_happyPath);
      await HisInOneGradesGateway(
        const HisInOneProfile(),
        adapter,
      ).fetchGrades(_creds);

      final RequestOptions expand = adapter.requests.firstWhere(
        (RequestOptions o) =>
            o.method == 'POST' &&
            o.uri.toString().contains('personExamsReadonly.xhtml'),
      );
      final Map<String, String> body = Map<String, String>.from(
        expand.data as Map,
      );
      expect(body['authenticity_token'], 'TOKEN-XYZ');
      expect(body['javax.faces.ViewState'], 'VIEWSTATE-1');
      expect(body['examsReadonly_SUBMIT'], '1');
      expect(body['_flowExecutionKey'], 'e1s3');
      expect(
        body.containsKey('examsReadonly:overviewAsTreeReadonly:expandAll2'),
        isTrue,
      );
      expect(adapter.urls.any((String u) => u.contains('auth.logout')), isTrue);
    },
  );

  test('rejects a redirect to another host', () async {
    final adapter = FakeHtmlAdapter((RequestOptions o) {
      if (o.uri.toString().contains('auth.login')) {
        return const FakeHtmlResponse.redirect(
          'https://evil.example.com/steal',
        );
      }
      return const FakeHtmlResponse('bye');
    });
    await expectLater(
      HisInOneGradesGateway(
        const HisInOneProfile(),
        adapter,
      ).fetchGrades(_creds),
      throwsA(
        isA<GradeFailure>().having(
          (GradeFailure e) => e.kind,
          'kind',
          GradeFailureKind.tlsOrHostRejected,
        ),
      ),
    );
  });

  test('rejects a redirect that downgrades to HTTP', () async {
    final adapter = FakeHtmlAdapter((RequestOptions o) {
      if (o.uri.toString().contains('auth.login')) {
        return const FakeHtmlResponse.redirect(
          'http://sscportal.ssc.hs-anhalt.de/qisserver/rds?category=menu.browse',
        );
      }
      return const FakeHtmlResponse('bye');
    });
    await expectLater(
      HisInOneGradesGateway(
        const HisInOneProfile(),
        adapter,
      ).fetchGrades(_creds),
      throwsA(
        isA<GradeFailure>().having(
          (GradeFailure e) => e.kind,
          'kind',
          GradeFailureKind.tlsOrHostRejected,
        ),
      ),
    );
  });

  test(
    'detects invalid credentials via the Location fail signal (hisinoneStartPage.faces)',
    () async {
      final adapter = FakeHtmlAdapter((RequestOptions o) {
        if (o.uri.toString().contains('auth.login')) {
          return const FakeHtmlResponse.redirect(
            'https://sscportal.ssc.hs-anhalt.de/hisinoneStartPage.faces',
          );
        }
        return const FakeHtmlResponse('bye');
      });
      await expectLater(
        HisInOneGradesGateway(
          const HisInOneProfile(),
          adapter,
        ).fetchGrades(_creds),
        throwsA(
          isA<GradeFailure>().having(
            (GradeFailure e) => e.kind,
            'kind',
            GradeFailureKind.invalidCredentials,
          ),
        ),
      );
    },
  );

  test('a success Location whose landing page has no logout link (still the '
      'plain login page) is treated as invalid', () async {
    final adapter = FakeHtmlAdapter((RequestOptions o) {
      final String url = o.uri.toString();
      if (url.contains('auth.login')) {
        return const FakeHtmlResponse.redirect(_landingUrl);
      }
      if (url == _landingUrl) {
        return const FakeHtmlResponse(hisInOneLoginFormHtml);
      }
      return const FakeHtmlResponse('bye');
    });
    await expectLater(
      HisInOneGradesGateway(
        const HisInOneProfile(),
        adapter,
      ).fetchGrades(_creds),
      throwsA(
        isA<GradeFailure>().having(
          (GradeFailure e) => e.kind,
          'kind',
          GradeFailureKind.invalidCredentials,
        ),
      ),
    );
  });

  test(
    'a landing page with a logout link succeeds even though it also renders '
    'the ever-present sessionTimeoutLoginForm (asdf/fdsa) — regression for '
    'the bug that rejected every login, including correct credentials',
    () async {
      final adapter = FakeHtmlAdapter(_happyPath);
      final GradeReport report = await HisInOneGradesGateway(
        const HisInOneProfile(),
        adapter,
      ).fetchGrades(_creds);
      expect(report.entries, isNotEmpty);
    },
  );

  test(
    'logs out and maps a structure change even after a parser error',
    () async {
      final adapter = FakeHtmlAdapter((RequestOptions o) {
        final String url = o.uri.toString();
        if (url.contains('auth.login')) {
          return const FakeHtmlResponse.redirect(_landingUrl);
        }
        if (url == _landingUrl) {
          return const FakeHtmlResponse(hisInOneAuthenticatedLandingHtml);
        }
        if (url.contains('auth.logout')) {
          return const FakeHtmlResponse('bye');
        }
        if (url.contains('personExamsReadonly.xhtml') && o.method == 'GET') {
          return const FakeHtmlResponse(hisInOneCollapsedOverviewHtml);
        }
        if (url.contains('personExamsReadonly.xhtml') && o.method == 'POST') {
          return FakeHtmlResponse(hisInOneStructureChangedHtml);
        }
        return const FakeHtmlResponse('not found', statusCode: 404);
      });
      final gateway = HisInOneGradesGateway(const HisInOneProfile(), adapter);

      late final Object caught;
      try {
        await gateway.fetchGrades(_creds);
        fail('expected a failure');
      } catch (e) {
        caught = e;
      }
      expect(
        caught,
        isA<GradeFailure>().having(
          (GradeFailure e) => e.kind,
          'kind',
          GradeFailureKind.portalStructureChanged,
        ),
      );
      expect(caught.toString(), 'GradeFailure(portalStructureChanged)');
      expect(adapter.urls.any((String u) => u.contains('auth.logout')), isTrue);
    },
  );

  test(
    'reports portalStructureChanged when the expand form cannot be found',
    () async {
      final adapter = FakeHtmlAdapter((RequestOptions o) {
        final String url = o.uri.toString();
        if (url.contains('auth.login')) {
          return const FakeHtmlResponse.redirect(_landingUrl);
        }
        if (url == _landingUrl) {
          return const FakeHtmlResponse(hisInOneAuthenticatedLandingHtml);
        }
        if (url.contains('personExamsReadonly.xhtml') && o.method == 'GET') {
          return const FakeHtmlResponse(hisInOneNoFormHtml);
        }
        return const FakeHtmlResponse('bye');
      });
      await expectLater(
        HisInOneGradesGateway(
          const HisInOneProfile(),
          adapter,
        ).fetchGrades(_creds),
        throwsA(
          isA<GradeFailure>().having(
            (GradeFailure e) => e.kind,
            'kind',
            GradeFailureKind.portalStructureChanged,
          ),
        ),
      );
    },
  );

  group('downloadExamReport', () {
    final ExamReportOffer offer = const ExamReportOffer(
      buttonId: 'examsReadonly:exaReports:fieldset_exaReports:printReport_0',
      label:
          'Leistungsübersicht (bestandene Leistungen) / '
          'List of passed exam (german) [PDF]',
    );

    FakeHtmlResponse scriptWithReports(RequestOptions o) {
      final String url = o.uri.toString();
      if (url.contains('auth.login')) {
        return const FakeHtmlResponse.redirect(_landingUrl);
      }
      if (url == _landingUrl) {
        return const FakeHtmlResponse(hisInOneAuthenticatedLandingHtml);
      }
      if (url.contains('auth.logout')) return const FakeHtmlResponse('bye');
      if (url.contains('personExamsReadonly.xhtml') && o.method == 'GET') {
        return FakeHtmlResponse(hisInOneRenderedTreeWithExamReportsHtml);
      }
      return const FakeHtmlResponse('not found', statusCode: 404);
    }

    test(
      'submits the real full-POST shape and returns the verified PDF',
      () async {
        final adapter = FakeHtmlAdapter((RequestOptions o) {
          final String url = o.uri.toString();
          if (o.uri.queryParameters['state'] == 'docdownload') {
            return const FakeHtmlResponse(
              '%PDF-1.7\nfixture',
              contentType: 'application/pdf',
            );
          }
          if (url.contains('personExamsReadonly.xhtml') && o.method == 'POST') {
            expect(
              o.data,
              isA<Map>().having(
                (Map m) => m[offer.buttonId],
                'button field',
                offer.label,
              ),
            );
            expect((o.data as Map)['DISABLE_VALIDATION'], 'true');
            return const FakeHtmlResponse.redirect(
              'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
              '?state=docdownload&docId=abc',
            );
          }
          return scriptWithReports(o);
        });

        final ExamReportDownloadResult result = await HisInOneGradesGateway(
          const HisInOneProfile(),
          adapter,
        ).downloadExamReport(_creds, offer);

        expect(result, isA<ExamReportDownloadLoaded>());
        final ExamReportDownloadLoaded loaded =
            result as ExamReportDownloadLoaded;
        expect(
          loaded.bytes.take(5),
          orderedEquals(<int>[0x25, 0x50, 0x44, 0x46, 0x2d]),
        );
      },
    );

    test('an offer no longer listed on a fresh read is rejected before any '
        'POST', () async {
      final adapter = FakeHtmlAdapter(scriptWithReports);
      const ExamReportOffer stale = ExamReportOffer(
        buttonId: 'examsReadonly:exaReports:fieldset_exaReports:printReport_9',
        label: 'Veraltetes Angebot',
      );

      final ExamReportDownloadResult result = await HisInOneGradesGateway(
        const HisInOneProfile(),
        adapter,
      ).downloadExamReport(_creds, stale);

      expect(result, isA<ExamReportUnavailable>());
      expect(
        (result as ExamReportUnavailable).reason,
        'offer-no-longer-listed',
      );
    });
  });
}

/// Regression group for LEVIORA-154, reproduced against the live portal:
/// HISinOne accepts the credentials of an account whose results still live in
/// HIS-QIS and answers with an empty Leistungen page. The gateway used to
/// report that as `portalStructureChanged`, which aborted setup before the
/// legacy portal was ever tried.
void _deployedPortalBuildTests() {
  FakeHtmlResponse script(String overviewHtml, RequestOptions o) {
    final String url = o.uri.toString();
    if (url.contains('auth.login')) {
      return const FakeHtmlResponse.redirect(_landingUrl);
    }
    if (url.contains('auth.logout')) return const FakeHtmlResponse('bye');
    if (url.contains('personExamsReadonly.xhtml')) {
      return FakeHtmlResponse(overviewHtml);
    }
    if (url == _landingUrl) {
      return const FakeHtmlResponse(hisInOneAuthenticatedLandingHtml);
    }
    return const FakeHtmlResponse('not found', statusCode: 404);
  }

  test(
    'an empty Leistungsdaten section yields an EMPTY report (not a structure '
    'change), sends no expand POST and still logs out',
    () async {
      final adapter = FakeHtmlAdapter(
        (RequestOptions o) => script(hisInOneEmptyOverviewHtml, o),
      );

      final GradeReport report = await HisInOneGradesGateway(
        const HisInOneProfile(),
        adapter,
      ).fetchGrades(_creds);

      expect(report.isEmpty, isTrue);
      expect(
        adapter.requests.any(
          (RequestOptions o) =>
              o.method == 'POST' &&
              o.uri.toString().contains('personExamsReadonly.xhtml'),
        ),
        isFalse,
      );
      expect(adapter.urls.any((String u) => u.contains('auth.logout')), isTrue);
    },
  );

  test('a tree without an expand-all control is parsed as rendered, without an '
      'expand POST', () async {
    final adapter = FakeHtmlAdapter(
      (RequestOptions o) => script(hisInOneRenderedTreeNoExpandAllHtml, o),
    );

    final GradeReport report = await HisInOneGradesGateway(
      const HisInOneProfile(),
      adapter,
    ).fetchGrades(_creds);

    expect(report.entries, hasLength(3));
    expect(
      adapter.requests.any(
        (RequestOptions o) =>
            o.method == 'POST' &&
            o.uri.toString().contains('personExamsReadonly.xhtml'),
      ),
      isFalse,
    );
  });

  test('a rendered tree with Bescheinigungen populates both entries and '
      'examReports from the one fetch', () async {
    final adapter = FakeHtmlAdapter(
      (RequestOptions o) => script(hisInOneRenderedTreeWithExamReportsHtml, o),
    );

    final GradeReport report = await HisInOneGradesGateway(
      const HisInOneProfile(),
      adapter,
    ).fetchGrades(_creds);

    expect(report.entries, hasLength(3));
    expect(report.examReports, hasLength(1));
    expect(
      report.examReports.single.buttonId,
      'examsReadonly:exaReports:fieldset_exaReports:printReport_0',
    );
  });
}
