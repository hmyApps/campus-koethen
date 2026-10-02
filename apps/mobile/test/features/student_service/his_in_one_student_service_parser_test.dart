// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/student_service/data/his_in_one_student_service_parser.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_overview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'student_service_fixtures.dart';

void main() {
  group('isStudyServicePage', () {
    test('recognises the real form id', () {
      expect(
        HisInOneStudentServiceParser.isStudyServicePage(
          studyServiceStgStudentHtml(),
        ),
        isTrue,
      );
    });

    test('a page without the form is not recognised', () {
      expect(
        HisInOneStudentServiceParser.isStudyServicePage(
          '<html><body>no form</body></html>',
        ),
        isFalse,
      );
    });
  });

  group('buildTabSwitchRequest', () {
    test('collects every hidden field plus the real button name/value', () {
      final TabSwitchRequest? request =
          HisInOneStudentServiceParser.buildTabSwitchRequest(
            studyServiceStgStudentHtml(flowExecutionKey: 'e7s3'),
            'studyserviceForm:newContactData_TabBtn',
          );

      expect(request, isNotNull);
      expect(request!.action, contains('e7s3'));
      expect(request.formData['javax.faces.ViewState'], 'view-state-token');
      expect(request.formData['authenticity_token'], 'auth-token');
      expect(
        request.formData['studyserviceForm:newContactData_TabBtn'],
        'Kontaktdaten',
      );
    });

    test('a button that is not on the page yields null, never a guess', () {
      final TabSwitchRequest? request =
          HisInOneStudentServiceParser.buildTabSwitchRequest(
            studyServiceStgStudentHtml(),
            'studyserviceForm:agreements_TabBtn',
          );
      expect(request, isNull);
    });
  });

  group('readPersonalData / hoererstatusOf', () {
    test('reads label/value pairs by the label text, not by position', () {
      final List<PersonalDataField> fields =
          HisInOneStudentServiceParser.readPersonalData(
            studyServiceStgStudentHtml(),
          );

      expect(
        fields.map((PersonalDataField f) => f.label),
        containsAll(<String>['Matrikelnummer', 'Hörerstatus', 'Geburtsdatum']),
      );
      expect(HisInOneStudentServiceParser.hoererstatusOf(fields), 'Student');
    });
  });

  group('readContactTiles', () {
    test('reads filled and empty tiles alike', () {
      final List<ContactTile> tiles =
          HisInOneStudentServiceParser.readContactTiles(
            studyServiceContactDataHtml(),
          );

      final ContactTile address = tiles.firstWhere(
        (ContactTile t) => t.heading == 'Semesteranschrift',
      );
      expect(address.lines, isNotEmpty);

      final ContactTile empty = tiles.firstWhere(
        (ContactTile t) => t.heading == 'Companyaddress for paying study-fees',
      );
      expect(empty.lines, isEmpty);
    });
  });

  group('readProgrammes', () {
    test('requires all four headers before reading any row', () {
      final List<ProgrammeEntry>? entries =
          HisInOneStudentServiceParser.readProgrammes(
            studyServiceStgStudentHtml(),
          );

      expect(entries, isNotNull);
      expect(entries!.single.subject, 'Informatik');
      expect(entries.single.subjectSemester, '3');
      expect(entries.single.examinationVersion, '2023');
    });

    test(
      'a table missing a required header is not mistaken for the programme table',
      () {
        const String html = '''
        <html><body><form id="studyserviceForm">
        <table class="tableWithSelect table"><thead><tr>
          <th class="tableHeader"><span>Fach</span></th>
        </tr></thead></table>
        </form></body></html>
      ''';
        expect(HisInOneStudentServiceParser.readProgrammes(html), isNull);
      },
    );

    test('maps cells by their headers when the portal reorders columns', () {
      const String html = '''
        <html><body><form id="studyserviceForm">
        <table class="tableWithSelect"><thead><tr>
          <th class="tableHeader">Fachsemester</th>
          <th class="tableHeader">Prüfungsordnungsversion</th>
          <th class="tableHeader">Fach</th>
          <th class="tableHeader">Fachkennzeichen</th>
        </tr></thead><tbody><tr class="listRowOdd">
          <td>5</td><td>2024</td><td>Medieninformatik</td><td>H</td>
        </tr></tbody></table>
        </form></body></html>
      ''';

      final List<ProgrammeEntry>? entries =
          HisInOneStudentServiceParser.readProgrammes(html);

      expect(entries, isNotNull);
      expect(entries!.single.subject, 'Medieninformatik');
      expect(entries.single.subjectSemester, '5');
      expect(entries.single.subjectIndicator, 'H');
      expect(entries.single.examinationVersion, '2024');
    });
  });

  group('readCertificateOffers', () {
    test('reads every offered certificate with its real job button id', () {
      final List<CertificateOffer> offers =
          HisInOneStudentServiceParser.readCertificateOffers(
            studyServiceReportHtml(),
          );

      expect(offers, hasLength(2));
      expect(offers[0].name, 'Gebührenbescheinigung');
      expect(
        offers[0].jobButtonId,
        'studyserviceForm:report:reports:reportButtons:jobConfigurationButtons:0:jobConfigurationButtons:0:job2',
      );
      expect(offers[1].name, 'Studienverlaufsbescheinigung');
    });
  });

  group('readPaymentHint', () {
    test('the exact empty-state text is read as "no open items"', () {
      final PaymentHint hint = HisInOneStudentServiceParser.readPaymentHint(
        studyServiceBillsAndPaymentHtml(),
      );
      expect(hint.kind, PaymentHintKind.noneOpen);
    });

    test('a populated table is read as "open", with a row count', () {
      final PaymentHint hint = HisInOneStudentServiceParser.readPaymentHint(
        studyServiceBillsAndPaymentHtml(hasOpenItems: true),
      );
      expect(hint.kind, PaymentHintKind.open);
      expect(hint.openItemCount, 1);
    });

    test(
      'neither shape present is reported as unrecognised, never guessed',
      () {
        final PaymentHint hint = HisInOneStudentServiceParser.readPaymentHint(
          '<html><body><form id="studyserviceForm"></form></body></html>',
        );
        expect(hint.kind, PaymentHintKind.unrecognised);
      },
    );
  });

  group('readPollButtonId', () {
    test('reads the poll marker out of a CDATA-wrapped partial response', () {
      final String? pollId = HisInOneStudentServiceParser.readPollButtonId(
        partialResponseStarted(),
      );
      expect(
        pollId,
        'studyserviceForm:report:reports:reportButtons:jobDownloadPoll',
      );
    });

    test('an HTML5 parser would otherwise swallow the first real tag after '
        '<![CDATA[ as a bogus comment — this must not happen here', () {
      // Regression for the exact failure mode: parsing the raw XML
      // envelope directly (instead of through `cdataContentOf`) loses the
      // `<span data-poll-button-client-id="...">` tag entirely, because an
      // HTML5 tokenizer treats `<![CDATA[` as a bogus comment that runs to
      // the very next `>` — which is this span's own opening tag.
      final String xml = partialResponseStarted(pollButtonId: 'x:y:z');
      expect(HisInOneStudentServiceParser.readPollButtonId(xml), 'x:y:z');
    });
  });

  group('viewStateFromPartialResponse', () {
    test('reads the rotated JSF view state for the next poll', () {
      expect(
        HisInOneStudentServiceParser.viewStateFromPartialResponse(
          partialResponseStarted(viewState: 'rotated-token'),
        ),
        'rotated-token',
      );
    });
  });

  group('extractDownloadUrlFromPartialResponse', () {
    test('finds the one-time download link emitted by an eval block', () {
      final String? url =
          HisInOneStudentServiceParser.extractDownloadUrlFromPartialResponse(
            partialResponseFinished(),
          );
      expect(url, isNotNull);
      expect(url, contains('untrust-sscportal.ssc.hs-anhalt.de'));
      expect(url, contains('state=docdownload'));
    });

    test('a still-running job yields no link, never a fabricated one', () {
      final String? url =
          HisInOneStudentServiceParser.extractDownloadUrlFromPartialResponse(
            partialResponseStarted(),
          );
      expect(url, isNull);
    });
  });
}
