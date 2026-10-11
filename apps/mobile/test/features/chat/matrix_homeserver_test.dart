// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/chat/domain/matrix_homeserver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatrixHomeserver.parse', () {
    test('accepts exactly one HTTPS origin', () {
      final MatrixHomeserver? server = MatrixHomeserver.parse(
        'https://Matrix.Example.test/',
      );

      expect(server, isNotNull);
      expect(server!.host, 'matrix.example.test');
      expect(server.port, 443);
      expect(server.baseUri, Uri.parse('https://matrix.example.test'));
    });

    test('keeps a non-default port', () {
      expect(
        MatrixHomeserver.parse('https://matrix.example.test:8448')!.baseUri,
        Uri.parse('https://matrix.example.test:8448'),
      );
    });

    test('refuses anything that is not a bare HTTPS origin', () {
      for (final String? value in <String?>[
        null,
        '',
        '   ',
        'matrix.example.test',
        'http://matrix.example.test',
        'https://user:pass@matrix.example.test',
        'https://matrix.example.test/_matrix',
        'https://matrix.example.test/?x=1',
        'https://matrix.example.test/#frag',
        'https://',
      ]) {
        expect(MatrixHomeserver.parse(value), isNull, reason: '$value');
      }
    });
  });

  group('MatrixHomeserver.allows', () {
    final MatrixHomeserver server = MatrixHomeserver.parse(
      'https://matrix.example.test',
    )!;

    test('allows any path on the exact origin', () {
      expect(
        server.allows(
          Uri.parse('https://matrix.example.test/_matrix/client/versions'),
        ),
        isTrue,
      );
      expect(
        server.allows(Uri.parse('https://MATRIX.example.test:443/x')),
        isTrue,
      );
    });

    test('refuses every other origin, including look-alikes', () {
      for (final String value in <String>[
        'http://matrix.example.test/_matrix',
        'https://matrix.example.test:8448/_matrix',
        'https://matrix.example.test.attacker.test/_matrix',
        'https://evil.matrix.example.test/_matrix',
        'https://user@matrix.example.test/_matrix',
        'https://example.test/_matrix',
      ]) {
        expect(server.allows(Uri.parse(value)), isFalse, reason: value);
      }
    });
  });

  test('describes itself by origin only', () {
    expect(
      MatrixHomeserver.parse('https://matrix.example.test').toString(),
      'MatrixHomeserver(https://matrix.example.test)',
    );
  });
}
