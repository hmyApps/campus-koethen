// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/chat/data/matrix_origin_http_client.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:campus_koethen/features/chat/domain/matrix_homeserver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Records what reaches the network and answers with an empty 200.
class _RecordingClient extends http.BaseClient {
  final List<http.BaseRequest> sent = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request);
    return http.StreamedResponse(Stream<List<int>>.value(<int>[]), 200);
  }
}

void main() {
  final MatrixHomeserver server = MatrixHomeserver.parse(
    'https://matrix.example.test',
  )!;

  test('passes requests to the configured origin and never follows '
      'redirects', () async {
    final _RecordingClient inner = _RecordingClient();
    final MatrixOriginHttpClient client = MatrixOriginHttpClient(server, inner);

    final http.Response response = await client.get(
      Uri.parse('https://matrix.example.test/_matrix/client/versions'),
    );

    expect(response.statusCode, 200);
    expect(inner.sent, hasLength(1));
    expect(inner.sent.single.followRedirects, isFalse);
  });

  test('refuses a request to any other origin before it is sent', () async {
    final _RecordingClient inner = _RecordingClient();
    final MatrixOriginHttpClient client = MatrixOriginHttpClient(server, inner);

    for (final String url in <String>[
      'https://matrix.example.test.attacker.test/_matrix/client/versions',
      'http://matrix.example.test/_matrix/client/versions',
      'https://media.example.test/_matrix/media/v3/download/x/y',
    ]) {
      await expectLater(
        client.get(Uri.parse(url)),
        throwsA(
          isA<MatrixFailure>().having(
            (MatrixFailure f) => f.kind,
            'kind',
            MatrixFailureKind.tlsOrHostRejected,
          ),
        ),
        reason: url,
      );
    }
    expect(inner.sent, isEmpty);
  });
}
