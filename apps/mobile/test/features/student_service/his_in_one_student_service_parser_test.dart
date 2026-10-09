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
      // JSF's own internal name, distinct from the button's id — read from
      // the button's real `name` attribute, never assumed to match the id.
      expect(request.formData['studyserviceForm:content.5'], '');
      expect(
        request.formData.containsKey('studyserviceForm:newContactData_TabBtn'),
        isFalse,
      );
    });

    test('a real tab button has no value attribute at all — that still '
        'yields a request, not a missing-button failure', () {
      final TabSwitchRequest?
      request = HisInOneStudentServiceParser.buildTabSwitchRequest(
        '<html><body>'
            '<form id="studyserviceForm" method="post" '
            'action="/qisserver/pages/cm/stu/studyService/start.xhtml'
            '?_flowId=studyservice-flow&_flowExecutionKey=e9s1">'
            '<button type="submit" id="studyserviceForm:newContactData_TabBtn" '
            'name="studyserviceForm:content.5" role="tab">Kontaktdaten</button>'
            '</form></body></html>',
        'studyserviceForm:newContactData_TabBtn',
      );

      expect(request, isNotNull);
      expect(request!.formData['studyserviceForm:content.5'], '');
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

  group('readJobConfiguration', () {
    test('builds the full, non-AJAX submission with the pre-selected semester', () {
      const TabSwitchRequest base = TabSwitchRequest(
        action:
            '/qisserver/pages/cm/stu/studyService/start.xhtml'
            '?_flowId=studyservice-flow&_flowExecutionKey=e1s2',
        formData: <String, String>{
          'authenticity_token': 'auth-token',
          'javax.faces.ViewState': 'e1s2',
        },
      );
      final JobConfiguration configuration =
          HisInOneStudentServiceParser.readJobConfiguration(
            partialResponseNeedsConfiguration(),
            base,
          );

      expect(configuration, isA<JobConfigurationSubmit>());
      final TabSwitchRequest request =
          (configuration as JobConfigurationSubmit).request;
      expect(request.action, base.action);
      // Every hidden field from the original page is carried through.
      expect(request.formData['authenticity_token'], 'auth-token');
      // The portal's own pre-selected option (the current semester) is
      // submitted unchanged — never a guessed or hard-coded semester.
      expect(
        request
            .formData['studyserviceForm:report:reports:reportButtons:jobConfigurationButtonsOverlay:jobConfiguration:settingsContainer_0:setting_0:setting_focus'],
        '284',
      );
      const String startJobId =
          'studyserviceForm:report:reports:reportButtons:jobConfigurationButtonsOverlay:navigationBottom:startJob';
      expect(request.formData[startJobId], 'PDF erstellen');
      expect(request.formData['activePageElementId'], startJobId);
    });

    test('a job that starts directly (no configuration overlay) is reported as '
        'having none', () {
      const TabSwitchRequest base = TabSwitchRequest(
        action: '/qisserver/pages/cm/stu/studyService/start.xhtml',
        formData: <String, String>{},
      );
      for (final String response in <String>[
        partialResponseFinished(),
        partialResponseStarted(),
      ]) {
        expect(
          HisInOneStudentServiceParser.readJobConfiguration(response, base),
          isA<NoJobConfiguration>(),
        );
      }
    });

    // D-08: an overlay that is recognisably there but cannot be read
    // completely must never be mistaken for "the job started directly" —
    // that sent the app polling for a minute against a job never started.
    test(
      'a recognised but incomplete overlay is unrecognised, never absent',
      () {
        const TabSwitchRequest base = TabSwitchRequest(
          action: '/qisserver/pages/cm/stu/studyService/start.xhtml',
          formData: <String, String>{},
        );
        final String full = partialResponseNeedsConfiguration();
        final Map<String, String> incomplete = <String, String>{
          'no pre-selected option': full.replaceAll(' selected="selected"', ''),
          'no select': full.replaceAll(
            RegExp(r'<select.*?</select>', dotAll: true),
            '',
          ),
          'no start button': full.replaceAll(RegExp(r'<button[^\n]*'), ''),
          'start button without value': full.replaceAll(
            'value="PDF erstellen"',
            '',
          ),
        };
        for (final MapEntry<String, String> variant in incomplete.entries) {
          expect(
            HisInOneStudentServiceParser.readJobConfiguration(
              variant.value,
              base,
            ),
            isA<UnrecognisedJobConfiguration>(),
            reason: variant.key,
          );
        }
      },
    );
  });

  group('extractDownloadUrlFromPartialResponse', () {
    test('finds the one-time download link and unescapes its query string', () {
      final String? url =
          HisInOneStudentServiceParser.extractDownloadUrlFromPartialResponse(
            partialResponseFinished(docId: 'the-doc-id'),
          );
      // Site-relative, exactly as the real portal renders it — resolving
      // against the portal origin is the gateway's job, not the parser's.
      expect(url, '/qisserver/rds?state=docdownload&docId=the-doc-id');
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
