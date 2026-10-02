// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A scripted [HttpClientAdapter] that returns raw HTML (never JSON), so the QIS
/// gateway runs through the real dio + cookie pipeline. No real network.
class FakeHtmlAdapter implements HttpClientAdapter {
  FakeHtmlAdapter(this.responder);

  final FutureOr<FakeHtmlResponse> Function(RequestOptions options) responder;

  /// Every request that reached the adapter, in order.
  final List<RequestOptions> requests = <RequestOptions>[];

  List<String> get urls =>
      requests.map((RequestOptions o) => o.uri.toString()).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final FakeHtmlResponse r = await responder(options);
    return ResponseBody.fromString(r.body, r.statusCode, headers: r.headers);
  }

  @override
  void close({bool force = false}) {}
}

class FakeHtmlResponse {
  const FakeHtmlResponse(
    this.body, {
    this.statusCode = 200,
    this.location,
    this.setCookie,
    this.contentType = 'text/html; charset=utf-8',
  });

  /// A 3xx redirect to [location].
  const FakeHtmlResponse.redirect(
    this.location, {
    this.statusCode = 302,
    this.setCookie,
  }) : body = '',
       contentType = 'text/html; charset=utf-8';

  final String body;
  final int statusCode;
  final String? location;
  final String? setCookie;
  final String contentType;

  Map<String, List<String>> get headers => <String, List<String>>{
    Headers.contentTypeHeader: <String>[contentType],
    if (location != null) 'location': <String>[location!],
    if (setCookie != null) 'set-cookie': <String>[setCookie!],
  };
}
