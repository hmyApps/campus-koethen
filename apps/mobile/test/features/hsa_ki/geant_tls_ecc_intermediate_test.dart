// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/features/hsa_ki/data/geant_tls_ecc_intermediate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the embedded GEANT TLS ECC 1 certificate is well-formed PEM that a '
    'SecurityContext accepts as a trusted certificate — a corrupted or '
    'truncated edit to the constant would throw here instead of silently '
    'breaking HawkiSession\'s TLS setup at runtime',
    () {
      final SecurityContext context = SecurityContext(withTrustedRoots: true);
      expect(
        () => context.setTrustedCertificatesBytes(
          utf8.encode(geantTlsEcc1IntermediatePem),
        ),
        returnsNormally,
      );
    },
  );
}
