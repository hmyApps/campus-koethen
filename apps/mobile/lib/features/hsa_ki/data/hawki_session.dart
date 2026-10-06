// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../domain/hsa_ki_failure.dart';
import '../domain/hsa_ki_profile.dart';
import 'geant_tls_ecc_intermediate.dart';
import 'hawki_html_parser.dart';

/// One short-lived HTTPS session against [HsaKiProfile.host] only.
///
/// Unlike the JSF-based HISinOne portal this app also talks to, HAWKI is a
/// plain modern Laravel app: ordinary redirects and one CSRF convention
/// (`X-CSRF-TOKEN` read fresh off the page being posted to, confirmed
/// 2026-10-04 from the real login request). Redirects are nonetheless followed
/// by hand and each hop re-validated against [HsaKiProfile.allows] before any
/// credential header is replayed to it, exactly like the other direct
/// integrations. The cookie jar is in-memory and lives only as long as this
/// session.
class HawkiSession {
  HawkiSession({HttpClientAdapter? adapter}) {
    _jar = CookieJar();
    _dio = Dio(
      BaseOptions(
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
        validateStatus: (_) => true, // status handled explicitly below
        // Redirects are validated by hand (see [fetchHtml]) so no hop can
        // replay the session cookie, CSRF token or bearer token to another
        // host. This matches every other direct integration in this app
        // (grades, Nextcloud, EWS); the earlier reliance on Dio's default
        // auto-follow was the one outlier.
        followRedirects: false,
      ),
    );
    _dio.interceptors.add(CookieManager(_jar));
    _dio.httpClientAdapter = adapter ?? _defaultAdapter();
  }

  /// `ki.hs-anhalt.de` does not send its own intermediate certificate (see
  /// [geantTlsEcc1IntermediatePem]'s doc comment for the full, verified
  /// diagnosis). This supplies exactly that one missing, already-publicly-
  /// trusted certificate so the chain can still be validated properly —
  /// every other host and every other check remains exactly as strict as
  /// the platform default; nothing is disabled.
  static IOHttpClientAdapter _defaultAdapter() => IOHttpClientAdapter(
    createHttpClient: () {
      final SecurityContext context = SecurityContext(withTrustedRoots: true);
      context.setTrustedCertificatesBytes(
        utf8.encode(geantTlsEcc1IntermediatePem),
      );
      return HttpClient(context: context);
    },
  );

  static const Duration _timeout = Duration(seconds: 15);
  static const int _maxRedirects = 10;
  static const HsaKiProfile _profile = HsaKiProfile();

  late final Dio _dio;
  late final CookieJar _jar;

  Uri _validated(Uri uri) {
    if (!_profile.allows(uri)) {
      throw const HsaKiFailure(HsaKiFailureKind.tlsOrHostRejected);
    }
    return uri;
  }

  /// Fetches a page's HTML, following redirects **by hand** so every hop is
  /// re-validated against [HsaKiProfile.allows] BEFORE any header (session
  /// cookie, CSRF token) is replayed to it. A redirect to another host or to
  /// plain HTTP is rejected as [HsaKiFailureKind.tlsOrHostRejected], never
  /// silently followed.
  Future<String> fetchHtml(Uri uri) async {
    Uri target = _validated(uri);
    for (int hop = 0; hop < _maxRedirects; hop++) {
      final Response<dynamic> response = await _dio.getUri<dynamic>(
        target,
        options: Options(responseType: ResponseType.plain),
      );
      final int status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final String? location = response.headers.value('location');
        if (location == null || location.isEmpty) {
          throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
        }
        target = _validated(target.resolve(location));
        continue;
      }
      _requireOk(response);
      return response.data?.toString() ?? '';
    }
    throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
  }

  /// `POST /req/login`: the real form submits `multipart/form-data`, not
  /// JSON or url-encoded — confirmed 2026-10-04 from the real request.
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final String loginPageHtml = await fetchHtml(_profile.loginPageUri);
    final String? csrfToken = HawkiHtmlParser.loginFormToken(loginPageHtml);
    if (csrfToken == null) {
      throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
    }
    final FormData body = FormData.fromMap(<String, dynamic>{
      'account': username,
      'password': password,
    });
    final Response<dynamic> response = await _dio.postUri<dynamic>(
      _validated(_profile.loginUri),
      data: body,
      options: Options(
        headers: <String, String>{
          'X-CSRF-TOKEN': csrfToken,
          'Accept': 'application/json',
        },
      ),
    );
    if (response.statusCode == 401 || response.statusCode == 422) {
      throw const HsaKiFailure(HsaKiFailureKind.invalidCredentials);
    }
    _requireOk(response);
    final dynamic json = response.data;
    if (json is! Map<String, dynamic> || json['success'] != true) {
      throw const HsaKiFailure(HsaKiFailureKind.invalidCredentials);
    }
    // Confirmed from HAWKI's own `handleLogin` source: `Auth::login()` is
    // only ever called on the branch that redirects to `/handshake`. A
    // `/register` redirect means the credentials were valid but no HAWKI
    // user exists yet for this account — the session was never actually
    // authenticated, so every later session-authenticated call would fail.
    if (json['redirectUri'] == '/register') {
      throw const HsaKiFailure(HsaKiFailureKind.notRegistered);
    }
    return json;
  }

  /// A JSON POST to an already-authenticated `/req/*` route, with a CSRF
  /// token read fresh from [csrfSourcePage] — never reused across requests,
  /// since Laravel rotates the session's token at points such as login.
  Future<Map<String, dynamic>> postJsonWithFreshCsrf(
    Uri target, {
    required Uri csrfSourcePage,
    required Map<String, dynamic> body,
  }) async {
    final String pageHtml = await fetchHtml(_validated(csrfSourcePage));
    final String? csrfToken = HawkiHtmlParser.pageMetaToken(pageHtml);
    if (csrfToken == null) {
      throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
    }
    final Response<dynamic> response = await _dio.postUri<dynamic>(
      _validated(target),
      data: body,
      options: Options(
        headers: <String, String>{
          'X-CSRF-TOKEN': csrfToken,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    if (response.statusCode == 401) {
      throw const HsaKiFailure(HsaKiFailureKind.notConnected);
    }
    _requireOk(response);
    final dynamic json = response.data;
    if (json is! Map<String, dynamic> || json['success'] != true) {
      throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
    }
    return json;
  }

  /// A bearer-token call against `/api/hawki/v1/*` — no cookies, no CSRF,
  /// just `Authorization: Bearer <token>`, confirmed from the real
  /// `StreamController::handleExternalRequest`/JSON:API route contract.
  Future<Map<String, dynamic>> postBearerJson(
    Uri target, {
    required String token,
    required Map<String, dynamic> body,
  }) async {
    final Response<dynamic> response = await _dio.postUri<dynamic>(
      _validated(target),
      data: body,
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    _mapBearerStatus(response.statusCode);
    final dynamic json = response.data;
    if (json is! Map<String, dynamic>) {
      throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
    }
    return json;
  }

  Future<Map<String, dynamic>> getBearerJson(
    Uri target, {
    required String token,
  }) async {
    final Response<dynamic> response = await _dio.getUri<dynamic>(
      _validated(target),
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.api+json',
        },
      ),
    );
    _mapBearerStatus(response.statusCode);
    final dynamic json = response.data;
    if (json is! Map<String, dynamic>) {
      throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
    }
    return json;
  }

  void _mapBearerStatus(int? status) {
    if (status == 401) {
      throw const HsaKiFailure(HsaKiFailureKind.notConnected);
    }
    if (status == 403) {
      throw const HsaKiFailure(HsaKiFailureKind.externalAccessDisabled);
    }
    if (status != null && status >= 200 && status < 300) return;
    throw const HsaKiFailure(HsaKiFailureKind.portalUnavailable);
  }

  void _requireOk(Response<dynamic> response) {
    final int status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    if (status >= 500) {
      throw const HsaKiFailure(HsaKiFailureKind.portalUnavailable);
    }
    throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
  }

  static HsaKiFailure mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const HsaKiFailure(HsaKiFailureKind.timeout);
      case DioExceptionType.connectionError:
        return const HsaKiFailure(HsaKiFailureKind.networkUnavailable);
      case DioExceptionType.badCertificate:
        return const HsaKiFailure(HsaKiFailureKind.tlsOrHostRejected);
      case DioExceptionType.badResponse:
        return const HsaKiFailure(HsaKiFailureKind.portalUnavailable);
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        final Object? inner = e.error;
        if (inner is Exception &&
            inner.runtimeType.toString().contains('Handshake')) {
          return const HsaKiFailure(HsaKiFailureKind.tlsOrHostRejected);
        }
        return const HsaKiFailure(HsaKiFailureKind.networkUnavailable);
    }
  }

  void close() => _dio.close(force: true);
}
