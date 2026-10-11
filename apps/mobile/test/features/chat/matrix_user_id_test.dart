// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/chat/domain/matrix_user_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String server = 'matrix.example.test';

  test('keeps a full Matrix ID', () {
    expect(
      parseMatrixUserId(
        ' @demo-peer:other.example.test ',
        ownServerName: server,
      ),
      '@demo-peer:other.example.test',
    );
    expect(
      parseMatrixUserId(
        '@demo:matrix.example.test:8448',
        ownServerName: server,
      ),
      '@demo:matrix.example.test:8448',
    );
  });

  test('completes a bare name with the own server name', () {
    expect(
      parseMatrixUserId('demo-peer', ownServerName: server),
      '@demo-peer:matrix.example.test',
    );
  });

  test('refuses what is not a user ID', () {
    for (final String input in <String>[
      '',
      '   ',
      '@demo',
      '@:matrix.example.test',
      '@demo peer:matrix.example.test',
      '!room:matrix.example.test',
      '#alias:matrix.example.test',
      '@demo:',
      '@demo:exa mple.test',
      'demo@matrix.example.test',
    ]) {
      expect(
        parseMatrixUserId(input, ownServerName: server),
        isNull,
        reason: input,
      );
    }
  });

  test('reads the server part of an ID', () {
    expect(matrixServerNameOf('@demo:matrix.example.test'), server);
    expect(
      matrixServerNameOf('@demo:matrix.example.test:8448'),
      'matrix.example.test:8448',
    );
    expect(matrixServerNameOf('demo'), isNull);
    expect(matrixServerNameOf('@demo:'), isNull);
  });
}
