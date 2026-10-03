// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Campus API origin validation', () {
    test('requires an explicitly supplied value', () {
      expect(
        ApiConfig.validateBaseUrl(
          'http://localhost:3000',
          isExplicitlyConfigured: false,
          allowLoopback: true,
        ),
        ApiConfigProblem.notConfigured,
      );
    });

    test('accepts only an exact HTTPS origin', () {
      for (final String value in <String>[
        'https://api.example.org',
        'https://api.example.org/',
        'https://api.example.org:8443',
        'https://[2001:db8::1]:8443',
      ]) {
        expect(
          ApiConfig.validateBaseUrl(
            value,
            isExplicitlyConfigured: true,
            allowLoopback: false,
          ),
          isNull,
          reason: value,
        );
      }
    });

    test('rejects path, query, fragment, credentials and whitespace', () {
      for (final String value in <String>[
        'https://api.example.org/v1',
        'https://api.example.org?tenant=campus',
        'https://api.example.org/#fragment',
        'https://user:secret@api.example.org',
        'https://api.example.org:invalid',
        ' https://api.example.org',
        'https://api.example.org ',
      ]) {
        expect(
          ApiConfig.validateBaseUrl(
            value,
            isExplicitlyConfigured: true,
            allowLoopback: false,
          ),
          ApiConfigProblem.malformed,
          reason: value,
        );
      }
    });

    test('allows plaintext loopback only after an explicit local opt-in', () {
      for (final String value in <String>[
        'http://localhost:3000',
        'http://127.0.0.1:3000',
        'http://[::1]:3000',
      ]) {
        expect(
          ApiConfig.validateBaseUrl(
            value,
            isExplicitlyConfigured: true,
            allowLoopback: false,
          ),
          ApiConfigProblem.insecureScheme,
          reason: value,
        );
        expect(
          ApiConfig.validateBaseUrl(
            value,
            isExplicitlyConfigured: true,
            allowLoopback: true,
          ),
          isNull,
          reason: value,
        );
      }
    });

    test('requires the local opt-in for HTTPS loopback as well', () {
      expect(
        ApiConfig.validateBaseUrl(
          'https://localhost:3443',
          isExplicitlyConfigured: true,
          allowLoopback: false,
        ),
        ApiConfigProblem.malformed,
      );
      expect(
        ApiConfig.validateBaseUrl(
          'https://localhost:3443',
          isExplicitlyConfigured: true,
          allowLoopback: true,
        ),
        isNull,
      );
    });

    test('never permits non-loopback plaintext origins', () {
      expect(
        ApiConfig.validateBaseUrl(
          'http://api.example.org',
          isExplicitlyConfigured: true,
          allowLoopback: true,
        ),
        ApiConfigProblem.insecureScheme,
      );
    });
  });
}
