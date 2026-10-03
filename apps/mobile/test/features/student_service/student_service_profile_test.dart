// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/student_service/domain/student_service_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('document download allowlist', () {
    test('allows only the exact HTTPS document endpoint and state', () {
      expect(
        StudentServiceProfile.allowsDocumentDownload(
          Uri.parse(
            'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload&docId=abc',
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
        'http://sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload',
        'https://sscportal.ssc.hs-anhalt.de:8443/qisserver/rds'
            '?state=docdownload',
        'https://user@sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload',
        // An earlier analysis wrongly claimed a separate "untrust-"
        // subdomain; a real capture confirmed it is the plain portal host,
        // so that invented subdomain must now be rejected like any other.
        'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload',
      ];
      for (final String raw in rejected) {
        expect(
          StudentServiceProfile.allowsDocumentDownload(Uri.parse(raw)),
          isFalse,
          reason: raw,
        );
      }
    });
  });
}
