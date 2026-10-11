// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:http/http.dart' as http;

import '../domain/matrix_failure.dart';
import '../domain/matrix_homeserver.dart';

/// The Matrix SDK's only way onto the network.
///
/// Every request is checked against the configured homeserver **before** it is
/// sent, and redirects are never followed: a server answer that points the
/// client elsewhere would otherwise carry the access token to that host.
class MatrixOriginHttpClient extends http.BaseClient {
  MatrixOriginHttpClient(this._homeserver, [http.Client? inner])
    : _inner = inner ?? http.Client();

  final MatrixHomeserver _homeserver;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_homeserver.allows(request.url)) {
      throw const MatrixFailure(MatrixFailureKind.tlsOrHostRejected);
    }
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
