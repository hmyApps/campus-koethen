// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/student_service/data/his_in_one_student_service_gateway.dart';
import 'package:campus_koethen/features/student_service/data/his_in_one_student_service_parser.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_failure.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_gateway.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_overview.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_html_adapter.dart';
import '../grades/his_in_one_fixtures.dart'
    show hisInOneAuthenticatedLandingHtml;
import 'student_service_fixtures.dart';

const GradeCredentials _creds = GradeCredentials(
  username: 'testuser',
  password: 'test-pw',
);

const String _landingUrl =
    'https://sscportal.ssc.hs-anhalt.de/qisserver/rds?state=user&category=menu.browse';

/// The default happy-path script: login → landing → the four tabs in the
/// order [HisInOneStudentServiceGateway.fetchOverview] visits them.
FakeHtmlResponse _happyPath(RequestOptions o) {
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
  if (url.contains('studyService/start.xhtml')) {
    if (o.method == 'GET') {
      return FakeHtmlResponse(studyServiceStgStudentHtml());
    }
    final Map<String, String> body = Map<String, String>.from(o.data as Map);
    if (body.containsKey('studyserviceForm:content.5')) {
      return FakeHtmlResponse(studyServiceContactDataHtml());
    }
    if (body.containsKey('studyserviceForm:content.8')) {
      return FakeHtmlResponse(studyServiceBillsAndPaymentHtml());
    }
    if (body.containsKey('studyserviceForm:content.10')) {
      return FakeHtmlResponse(studyServiceReportHtml());
    }
  }
  return const FakeHtmlResponse('not found', statusCode: 404);
}

void main() {
  group('fetchOverview', () {
    test(
      'walks all four tabs and assembles one overview, logging out afterwards',
      () async {
        final adapter = FakeHtmlAdapter(_happyPath);
        final StudentServiceOverview overview =
            await HisInOneStudentServiceGateway(adapter).fetchOverview(_creds);

        expect(overview.hoererstatus, 'Student');
        expect(
          overview.personalData.map((PersonalDataField f) => f.label),
          contains('Matrikelnummer'),
        );
        expect(overview.contactTiles, isNotEmpty);
        expect(overview.programmes, hasLength(1));
        expect(overview.programmes.single.subject, 'Informatik');
        expect(overview.certificates, hasLength(2));
        expect(overview.paymentHint.kind, PaymentHintKind.noneOpen);

        expect(
          adapter.urls.any((String u) => u.contains('auth.logout')),
          isTrue,
        );
      },
    );

    test(
      'logs in form-urlencoded (asdf/fdsa) to the pinned HTTPS host',
      () async {
        final adapter = FakeHtmlAdapter(_happyPath);
        await HisInOneStudentServiceGateway(adapter).fetchOverview(_creds);

        final RequestOptions login = adapter.requests.firstWhere(
          (RequestOptions o) => o.uri.toString().contains('auth.login'),
        );
        expect(login.method, 'POST');
        expect(login.data, <String, String>{
          'asdf': 'testuser',
          'fdsa': 'test-pw',
        });
        expect(login.uri.scheme, 'https');
        expect(login.uri.host, 'sscportal.ssc.hs-anhalt.de');
      },
    );

    test('a landing page that is not recognisably the Studienservice page is '
        'reported as portalStructureChanged, never parsed as empty', () async {
      final adapter = FakeHtmlAdapter((RequestOptions o) {
        final String url = o.uri.toString();
        if (url.contains('auth.login')) {
          return const FakeHtmlResponse.redirect(_landingUrl);
        }
        if (url == _landingUrl) {
          return const FakeHtmlResponse(hisInOneAuthenticatedLandingHtml);
        }
        if (url.contains('studyService/start.xhtml') && o.method == 'GET') {
          return const FakeHtmlResponse('<html><body>no form</body></html>');
        }
        return const FakeHtmlResponse('bye');
      });

      await expectLater(
        HisInOneStudentServiceGateway(adapter).fetchOverview(_creds),
        throwsA(
          isA<StudentServiceFailure>()
              .having(
                (StudentServiceFailure f) => f.kind,
                'kind',
                StudentServiceFailureKind.portalStructureChanged,
              )
              .having((StudentServiceFailure f) => f.stage, 'stage', 'landing'),
        ),
      );
    });

    test('a recognised landing page missing the contact tab is diagnosed as '
        'the specific failing tab, not a generic message', () async {
      final adapter = FakeHtmlAdapter((RequestOptions o) {
        final String url = o.uri.toString();
        if (url.contains('auth.login')) {
          return const FakeHtmlResponse.redirect(_landingUrl);
        }
        if (url == _landingUrl) {
          return const FakeHtmlResponse(hisInOneAuthenticatedLandingHtml);
        }
        if (url.contains('studyService/start.xhtml')) {
          if (o.method == 'GET') {
            return FakeHtmlResponse(studyServiceStgStudentHtml());
          }
          final Map<String, String> body = Map<String, String>.from(
            o.data as Map,
          );
          if (body.containsKey('studyserviceForm:content.5')) {
            // Recognisable as the Studienservice page, but with none of
            // the contact tiles the real portal always has.
            return const FakeHtmlResponse(
              '<html><body><form id="studyserviceForm"></form></body></html>',
            );
          }
        }
        return const FakeHtmlResponse('bye');
      });

      await expectLater(
        HisInOneStudentServiceGateway(adapter).fetchOverview(_creds),
        throwsA(
          isA<StudentServiceFailure>()
              .having(
                (StudentServiceFailure f) => f.kind,
                'kind',
                StudentServiceFailureKind.portalStructureChanged,
              )
              .having(
                (StudentServiceFailure f) => f.stage,
                'stage',
                'contactTiles',
              ),
        ),
      );
    });

    test('rejected stored credentials surface as invalidCredentials, not a '
        'generic failure', () async {
      final adapter = FakeHtmlAdapter((RequestOptions o) {
        if (o.uri.toString().contains('auth.login')) {
          return const FakeHtmlResponse.redirect(
            'https://sscportal.ssc.hs-anhalt.de/hisinoneStartPage.faces',
          );
        }
        return const FakeHtmlResponse('bye');
      });

      await expectLater(
        HisInOneStudentServiceGateway(adapter).fetchOverview(_creds),
        throwsA(
          const StudentServiceFailure(
            StudentServiceFailureKind.invalidCredentials,
          ),
        ),
      );
    });

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
        HisInOneStudentServiceGateway(adapter).fetchOverview(_creds),
        throwsA(
          const StudentServiceFailure(
            StudentServiceFailureKind.tlsOrHostRejected,
          ),
        ),
      );
    });
  });

  group('downloadCertificate', () {
    test(
      'starts the real AJAX-shaped job and returns a verified PDF',
      () async {
        final adapter = FakeHtmlAdapter((RequestOptions o) {
          final String url = o.uri.toString();
          if (url.contains('auth.login')) {
            return const FakeHtmlResponse.redirect(
              _landingUrl,
              setCookie:
                  'student-session=fixture; Domain=ssc.hs-anhalt.de; '
                  'Path=/; Secure',
            );
          }
          if (url == _landingUrl) {
            return const FakeHtmlResponse(hisInOneAuthenticatedLandingHtml);
          }
          if (url.contains('auth.logout')) {
            return const FakeHtmlResponse('bye');
          }
          if (o.uri.queryParameters['state'] == 'docdownload') {
            expect(o.headers['cookie'], contains('student-session=fixture'));
            return const FakeHtmlResponse(
              '%PDF-1.7\nfixture',
              contentType: 'application/pdf',
            );
          }
          if (url.contains('studyService/start.xhtml') && o.method == 'GET') {
            return FakeHtmlResponse(studyServiceStgStudentHtml());
          }
          if (url.contains('studyService/start.xhtml') && o.method == 'POST') {
            final Map<String, String> body = Map<String, String>.from(
              o.data as Map,
            );
            if (body.containsKey('studyserviceForm:content.10')) {
              return FakeHtmlResponse(studyServiceReportHtml());
            }
            if (body['javax.faces.partial.ajax'] == 'true') {
              return FakeHtmlResponse(partialResponseFinished());
            }
          }
          return const FakeHtmlResponse('not found', statusCode: 404);
        });
        final CertificateOffer offer =
            HisInOneStudentServiceParser.readCertificateOffers(
              studyServiceReportHtml(),
            ).first;

        final CertificateDownloadResult result =
            await HisInOneStudentServiceGateway(
              adapter,
            ).downloadCertificate(_creds, offer);

        expect(result, isA<CertificateDownloadLoaded>());
        final CertificateDownloadLoaded loaded =
            result as CertificateDownloadLoaded;
        expect(loaded.filename, 'Gebührenbescheinigung.pdf');
        expect(
          loaded.bytes.take(5),
          orderedEquals(<int>[0x25, 0x50, 0x44, 0x46, 0x2d]),
        );
        expect(
          adapter.requests.any(
            (RequestOptions request) =>
                request.data is Map &&
                (request.data as Map)['javax.faces.source'] ==
                    offer.jobButtonId,
          ),
          isTrue,
        );
        // The real job button's own onclick asks the server to re-render
        // three components, not just the download slot — the overlay that
        // hosts the client poll widget's init marker among them. Rendering
        // fewer than that never gets the poll marker back at all.
        final RequestOptions jobStart = adapter.requests.firstWhere(
          (RequestOptions request) =>
              request.data is Map &&
              (request.data as Map)['javax.faces.source'] == offer.jobButtonId,
        );
        expect(
          (jobStart.data as Map)['javax.faces.partial.render'],
          allOf(
            contains(
              'studyserviceForm:report:reports:reportButtons:'
              'jobConfigurationButtonsOverlay',
            ),
            contains(
              'studyserviceForm:report:reports:reportButtons:jobDownload',
            ),
            contains('studyserviceForm:messages-infobox'),
          ),
        );
      },
    );

    test(
      'follows the real site-relative link through its same-host redirect',
      () async {
        // Confirmed 2026-10-04 from a real completed download: the entry
        // link the job-start response renders is relative and carries only
        // state/docId; the portal then redirects, same host, to a richer
        // URL (accountId/hash/timestamp/docName) before the actual bytes.
        final String redirectTarget = docDownloadRedirectTarget(
          docId: 'the-doc-id',
        );
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
          if (url == redirectTarget) {
            return const FakeHtmlResponse(
              '%PDF-1.7\nfixture',
              contentType: 'application/pdf',
            );
          }
          if (o.uri.queryParameters['state'] == 'docdownload') {
            return FakeHtmlResponse.redirect(redirectTarget);
          }
          if (url.contains('studyService/start.xhtml') && o.method == 'GET') {
            return FakeHtmlResponse(studyServiceStgStudentHtml());
          }
          if (url.contains('studyService/start.xhtml') && o.method == 'POST') {
            final Map<String, String> body = Map<String, String>.from(
              o.data as Map,
            );
            if (body.containsKey('studyserviceForm:content.10')) {
              return FakeHtmlResponse(studyServiceReportHtml());
            }
            if (body['javax.faces.partial.ajax'] == 'true') {
              return FakeHtmlResponse(
                partialResponseFinished(docId: 'the-doc-id'),
              );
            }
          }
          return const FakeHtmlResponse('not found', statusCode: 404);
        });
        final CertificateOffer offer =
            HisInOneStudentServiceParser.readCertificateOffers(
              studyServiceReportHtml(),
            ).first;

        final CertificateDownloadResult result =
            await HisInOneStudentServiceGateway(
              adapter,
            ).downloadCertificate(_creds, offer);

        expect(result, isA<CertificateDownloadLoaded>());
      },
    );

    test(
      'polls a running job with its rotated view state before downloading',
      () async {
        int ajaxCalls = 0;
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
          if (o.uri.queryParameters['state'] == 'docdownload') {
            return const FakeHtmlResponse(
              '%PDF-1.7\nfixture',
              contentType: 'application/pdf',
            );
          }
          if (url.contains('studyService/start.xhtml') && o.method == 'GET') {
            return FakeHtmlResponse(studyServiceStgStudentHtml());
          }
          if (url.contains('studyService/start.xhtml') && o.method == 'POST') {
            final Map<String, String> body = Map<String, String>.from(
              o.data as Map,
            );
            if (body.containsKey('studyserviceForm:content.10')) {
              return FakeHtmlResponse(studyServiceReportHtml());
            }
            if (body['javax.faces.partial.ajax'] == 'true') {
              ajaxCalls++;
              if (ajaxCalls == 1) {
                return FakeHtmlResponse(
                  partialResponseStarted(viewState: 'rotated-token'),
                );
              }
              // The real `<p:poll>` widget's own fixed source/render ids
              // (confirmed 2026-10-04 from a real poll request) — a
              // `:poll`-suffixed source distinct from the render target.
              expect(
                body['javax.faces.source'],
                'studyserviceForm:report:reports:reportButtons:'
                'jobDownloadPoll:poll',
              );
              expect(
                body['javax.faces.partial.render'],
                'studyserviceForm:report:reports:reportButtons:'
                'jobDownloadPoll',
              );
              expect(body['javax.faces.ViewState'], 'rotated-token');
              return FakeHtmlResponse(partialResponseFinished());
            }
          }
          return const FakeHtmlResponse('not found', statusCode: 404);
        });
        final CertificateOffer offer =
            HisInOneStudentServiceParser.readCertificateOffers(
              studyServiceReportHtml(),
            ).first;

        final CertificateDownloadResult result =
            await HisInOneStudentServiceGateway(
              adapter,
              Duration.zero,
            ).downloadCertificate(_creds, offer);

        expect(result, isA<CertificateDownloadLoaded>());
        expect(ajaxCalls, 2);
      },
    );

    test('an offer no longer listed on a fresh read is rejected before any '
        'AJAX attempt', () async {
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
        if (url.contains('studyService/start.xhtml') && o.method == 'GET') {
          return FakeHtmlResponse(studyServiceStgStudentHtml());
        }
        if (url.contains('studyService/start.xhtml') && o.method == 'POST') {
          final Map<String, String> body = Map<String, String>.from(
            o.data as Map,
          );
          if (body.containsKey('studyserviceForm:content.10')) {
            // A report page with NO certificate offers at all.
            return const FakeHtmlResponse(
              '<html><body><form id="studyserviceForm" method="post" '
              'action="/qisserver/pages/cm/stu/studyService/start.xhtml'
              '?_flowId=studyservice-flow&_flowExecutionKey=e1s4">'
              '</form></body></html>',
            );
          }
        }
        return const FakeHtmlResponse('not found', statusCode: 404);
      });

      final List<CertificateOffer> offers =
          HisInOneStudentServiceParser.readCertificateOffers(
            studyServiceReportHtml(),
          );
      final CertificateDownloadResult result =
          await HisInOneStudentServiceGateway(
            adapter,
          ).downloadCertificate(_creds, offers.first);

      expect(result, isA<CertificateUnavailable>());
      expect(
        (result as CertificateUnavailable).reason,
        'offer-no-longer-listed',
      );
    });

    test(
      'an AJAX job rejected by the portal is surfaced as portalUnavailable',
      () async {
        final adapter = FakeHtmlAdapter(_happyPath);
        final List<CertificateOffer> offers =
            HisInOneStudentServiceParser.readCertificateOffers(
              studyServiceReportHtml(),
            );

        await expectLater(
          HisInOneStudentServiceGateway(
            adapter,
          ).downloadCertificate(_creds, offers.first),
          throwsA(
            const StudentServiceFailure(
              StudentServiceFailureKind.portalUnavailable,
            ),
          ),
        );
      },
    );
  });
}
