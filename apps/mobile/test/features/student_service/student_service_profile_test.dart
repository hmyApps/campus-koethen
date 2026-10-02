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
            'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload&docId=abc',
          ),
        ),
        isTrue,
      );
    });

    test('rejects a different path, state, origin, port, or user-info', () {
      const List<String> rejected = <String>[
        'https://untrust-sscportal.ssc.hs-anhalt.de/other'
            '?state=docdownload',
        'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=other',
        'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload&state=other',
        'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload#fragment',
        'http://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
            '?state=docdownload',
        'https://untrust-sscportal.ssc.hs-anhalt.de:8443/qisserver/rds'
            '?state=docdownload',
        'https://user@untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds'
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
