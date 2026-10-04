// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/domain/his_in_one_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('allowsDocumentDownload', () {
    const HisInOneProfile profile = HisInOneProfile();

    test('allows the first-hop link on the portal host itself', () {
      expect(
        profile.allowsDocumentDownload(
          Uri.parse(
            'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload&docId=abc',
          ),
        ),
        isTrue,
      );
    });

    test('allows the exam-overview page itself — the real chain bounces '
        'back through it (a standard POST/redirect/GET) before that page '
        'redirects to the actual download, confirmed 2026-10-04 on the '
        'real device', () {
      expect(
        profile.allowsDocumentDownload(
          Uri.parse(
            'https://sscportal.ssc.hs-anhalt.de/qisserver/pages/sul/'
            'examAssessment/personExamsReadonly.xhtml'
            '?_flowId=examsOverviewForPerson-flow&_flowExecutionKey=e1s2',
          ),
        ),
        isTrue,
      );
    });

    test('allows the second-hop redirect target on the separate untrust- '
        'host — the same document-download mechanism used by Studienservice, '
        'confirmed 2026-10-04 from a real Location header there', () {
      expect(
        profile.allowsDocumentDownload(
          Uri.parse(
            'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload&accountId=52153&hash=abc'
            '&timestamp=20261004125245&docId=abc'
            '&docName=Geb%C3%BChrenbescheinigung.pdf',
          ),
        ),
        isTrue,
      );
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
        'https://evil.untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload',
        'https://evil.example.com/qisserver/rds?state=docdownload',
      ];
      for (final String raw in rejected) {
        expect(
          profile.allowsDocumentDownload(Uri.parse(raw)),
          isFalse,
          reason: raw,
        );
      }
    });
  });
}
