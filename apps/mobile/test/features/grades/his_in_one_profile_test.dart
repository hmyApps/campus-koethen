// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/domain/his_in_one_profile.dart';
import 'package:flutter_test/flutter_test.dart';

const String _bounce =
    'https://sscportal.ssc.hs-anhalt.de/qisserver/pages/sul/'
    'examAssessment/personExamsReadonly.xhtml'
    '?_flowId=examsOverviewForPerson-flow&_flowExecutionKey=e1s2';
const String _entry =
    'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
    '?state=docdownload&docId=abc';
const String _redirect =
    'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
    '?state=docdownload&accountId=52153&hash=abc'
    '&timestamp=20261004125245&docId=abc'
    '&docName=Geb%C3%BChrenbescheinigung.pdf';

void main() {
  const HisInOneProfile profile = HisInOneProfile();

  // D-09: every redirect a print button's POST answers with is checked
  // against an ORDERED route — never a flat set of hosts.
  group('exam report download route', () {
    test('the real chain: exam-overview bounce, portal-host docdownload, '
        'untrust- redirect (confirmed 2026-10-04 on the real device)', () {
      final bool Function(Uri) route = profile.examReportDownloadRoute();
      expect(route(Uri.parse(_bounce)), isTrue);
      expect(route(Uri.parse(_entry)), isTrue);
      expect(route(Uri.parse(_redirect)), isTrue);
    });

    test('the bounce is optional', () {
      final bool Function(Uri) route = profile.examReportDownloadRoute();
      expect(route(Uri.parse(_entry)), isTrue);
      expect(route(Uri.parse(_redirect)), isTrue);
    });

    test('never reaches the untrust- host before the portal-host entry', () {
      final bool Function(Uri) direct = profile.examReportDownloadRoute();
      expect(direct(Uri.parse(_redirect)), isFalse);

      final bool Function(Uri) afterBounce = profile.examReportDownloadRoute();
      expect(afterBounce(Uri.parse(_bounce)), isTrue);
      expect(afterBounce(Uri.parse(_redirect)), isFalse);
    });

    test('after the entry only the untrust- redirect follows', () {
      final bool Function(Uri) backToBounce = profile.examReportDownloadRoute();
      expect(backToBounce(Uri.parse(_entry)), isTrue);
      expect(backToBounce(Uri.parse(_bounce)), isFalse);

      final bool Function(Uri) entryAgain = profile.examReportDownloadRoute();
      expect(entryAgain(Uri.parse(_entry)), isTrue);
      expect(entryAgain(Uri.parse(_entry)), isFalse);

      final bool Function(Uri) backToPortal = profile.examReportDownloadRoute();
      expect(backToPortal(Uri.parse(_entry)), isTrue);
      expect(backToPortal(Uri.parse(_redirect)), isTrue);
      expect(backToPortal(Uri.parse(_entry)), isFalse);
    });

    test('rejects a different path, state, host, port, or user-info', () {
      const List<String> rejected = <String>[
        'https://sscportal.ssc.hs-anhalt.de/other?state=docdownload',
        'https://sscportal.ssc.hs-anhalt.de/qisserver/rds?state=other',
        'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload&state=other',
        'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload#fragment',
        'http://sscportal.ssc.hs-anhalt.de/qisserver/rds?state=docdownload',
        'https://sscportal.ssc.hs-anhalt.de:8443/qisserver/rds'
            '?state=docdownload',
        'https://user@sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload',
        'http://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload',
        'https://untrust-sscportal.ssc.hs-anhalt.de:8443/qisserver/rds'
            '?state=docdownload',
        'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/pages/sul/'
            'examAssessment/personExamsReadonly.xhtml',
        'https://evil.untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload',
        'https://evil.example.com/qisserver/rds?state=docdownload',
      ];
      for (final String raw in rejected) {
        final bool Function(Uri) beforeEntry = profile
            .examReportDownloadRoute();
        expect(beforeEntry(Uri.parse(raw)), isFalse, reason: raw);
        final bool Function(Uri) afterEntry = profile.examReportDownloadRoute();
        expect(afterEntry(Uri.parse(_entry)), isTrue);
        expect(afterEntry(Uri.parse(raw)), isFalse, reason: raw);
      }
    });
  });
}
