// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/student_service/domain/student_service_profile.dart';
import 'package:flutter_test/flutter_test.dart';

const String _entry =
    'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
    '?state=docdownload&docId=abc';
const String _redirect =
    'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
    '?state=docdownload&accountId=52153&hash=abc'
    '&timestamp=20261004125245&docId=abc'
    '&docName=Geb%C3%BChrenbescheinigung.pdf';

/// Shapes neither hop may ever take, whatever the order.
const List<String> _rejectedShapes = <String>[
  'https://sscportal.ssc.hs-anhalt.de/other?state=docdownload',
  'https://sscportal.ssc.hs-anhalt.de/qisserver/rds?state=other',
  'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
      '?state=docdownload&state=other',
  'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
      '?state=docdownload#fragment',
  'http://sscportal.ssc.hs-anhalt.de/qisserver/rds'
      '?state=docdownload',
  'https://sscportal.ssc.hs-anhalt.de:8443/qisserver/rds'
      '?state=docdownload',
  'https://user@sscportal.ssc.hs-anhalt.de/qisserver/rds'
      '?state=docdownload',
  'http://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
      '?state=docdownload',
  'https://untrust-sscportal.ssc.hs-anhalt.de:8443/qisserver/rds'
      '?state=docdownload',
  'https://untrust-sscportal.ssc.hs-anhalt.de/other?state=docdownload',
  // Neither confirmed host is a prefix/suffix match for an unrelated one.
  'https://evil.untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
      '?state=docdownload',
  'https://evil.example.com/qisserver/rds?state=docdownload',
];

void main() {
  group('document download allowlist', () {
    test('the entry is the job link on the portal host itself', () {
      expect(
        StudentServiceProfile.allowsDocumentDownloadEntry(Uri.parse(_entry)),
        isTrue,
      );
    });

    test('the separate untrust- host is never an entry point', () {
      expect(
        StudentServiceProfile.allowsDocumentDownloadEntry(Uri.parse(_redirect)),
        isFalse,
      );
    });

    test('rejects a different path, state, host, port, or user-info', () {
      for (final String raw in _rejectedShapes) {
        expect(
          StudentServiceProfile.allowsDocumentDownloadEntry(Uri.parse(raw)),
          isFalse,
          reason: raw,
        );
        final bool Function(Uri) route =
            StudentServiceProfile.documentDownloadRoute();
        expect(route(Uri.parse(_entry)), isTrue);
        expect(route(Uri.parse(raw)), isFalse, reason: raw);
      }
    });
  });

  // D-09: AGENTS.md §2 pins the ORDER of the two hops — first the portal
  // host, then the server-side redirect to the separate untrust- host.
  group('document download route', () {
    test('portal host first, then the untrust- redirect (confirmed '
        '2026-10-04 from a real Location header)', () {
      final bool Function(Uri) route =
          StudentServiceProfile.documentDownloadRoute();
      expect(route(Uri.parse(_entry)), isTrue);
      expect(route(Uri.parse(_redirect)), isTrue);
    });

    test('never starts on the untrust- host', () {
      final bool Function(Uri) route =
          StudentServiceProfile.documentDownloadRoute();
      expect(route(Uri.parse(_redirect)), isFalse);
    });

    test('a redirect never leads back to the portal host', () {
      final bool Function(Uri) afterEntry =
          StudentServiceProfile.documentDownloadRoute();
      expect(afterEntry(Uri.parse(_entry)), isTrue);
      expect(afterEntry(Uri.parse(_entry)), isFalse);

      final bool Function(Uri) afterRedirect =
          StudentServiceProfile.documentDownloadRoute();
      expect(afterRedirect(Uri.parse(_entry)), isTrue);
      expect(afterRedirect(Uri.parse(_redirect)), isTrue);
      expect(afterRedirect(Uri.parse(_entry)), isFalse);
    });

    test('each download starts its own route', () {
      final bool Function(Uri) first =
          StudentServiceProfile.documentDownloadRoute();
      expect(first(Uri.parse(_entry)), isTrue);
      final bool Function(Uri) second =
          StudentServiceProfile.documentDownloadRoute();
      expect(second(Uri.parse(_entry)), isTrue);
    });
  });
}
