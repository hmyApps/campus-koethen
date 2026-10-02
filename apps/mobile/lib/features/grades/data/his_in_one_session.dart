// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// One fetched page: its final URL and HTML body.
class HisInOnePage {
  const HisInOnePage(this.url, this.html);
  final String url;
  final String html;
}

/// Why a [HisInOneSession] request could not be completed.
///
/// Deliberately a small, portal-mechanics-only vocabulary — never the
/// feature-specific failures (`GradeFailure`, a future `StudentServiceFailure`,
/// …) a caller actually surfaces. Every caller maps this 1:1 onto its own type
/// at the boundary, so the session stays usable by more than one feature.
enum HisInOneSessionFailureKind {
  /// A request or redirect target was not the pinned HTTPS host.
  hostRejected,

  /// A non-redirect, non-2xx response, or a 5xx.
  unavailable,

  /// The portal positively told [login] this login did not work — the
  /// response matched [HisInOneSession.login]'s own `failureSignal`, or the
  /// landing page failed the positive `isAuthenticated` check. Distinct from
  /// [structureChanged]: this is a recognized "no" from the portal, which a
  /// caller maps onto its own "wrong credentials"-flavoured failure.
  loginRejected,

  /// A required signal (a `Location` header, a form) was missing or matched
  /// neither the expected success nor failure shape — the portal answered
  /// something this flow does not recognize at all.
  structureChanged,
  timeout,
  networkUnavailable,
  unknown,
}

class HisInOneSessionFailure implements Exception {
  const HisInOneSessionFailure(this.kind);
  final HisInOneSessionFailureKind kind;

  @override
  String toString() => 'HisInOneSessionFailure(${kind.name})';
}

/// One short-lived HISinOne session: login, zero or more page fetches/form
/// posts, then [close]. Portal-agnostic — a caller supplies the pinned origin
/// and the exact login/positive-authentication contract; this class owns only
/// the HTTP mechanics every HISinOne flow repeats:
///
///  - Every request and redirect target is validated against [allows] BEFORE
///    its response is inspected for a success/failure signal, so a malicious
///    redirect always surfaces as [HisInOneSessionFailureKind.hostRejected],
///    never reclassified as an ordinary portal failure.
///  - Certificate validation is never disabled; no [Dio] `LogInterceptor` —
///    credentials, cookies, tokens and HTML are never logged.
///  - The cookie jar is in-memory and lives only as long as this session.
class HisInOneSession {
  HisInOneSession({
    required this.baseUrl,
    required this.allows,
    HttpClientAdapter? adapter,
  }) {
    _jar = CookieJar();
    _dio = Dio(
      BaseOptions(
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
        responseType: ResponseType.plain,
        followRedirects: false, // redirects are validated by hand
        validateStatus: (_) => true, // status handled explicitly below
        headers: const <String, String>{'User-Agent': 'CampusKoethen/grades'},
      ),
    );
    _dio.interceptors.add(CookieManager(_jar));
    // Default IO adapter when none is injected — NO onBadCertificate override.
    _dio.httpClientAdapter = adapter ?? IOHttpClientAdapter();
  }

  /// The portal origin every request and redirect is validated against, e.g.
  /// `https://sscportal.ssc.hs-anhalt.de`.
  final String baseUrl;
  final bool Function(Uri uri) allows;

  late final CookieJar _jar;
  late final Dio _dio;

  static const Duration _timeout = Duration(seconds: 20);
  static const int _maxHops = 10;

  /// Logs in with a form-urlencoded `asdf`/`fdsa` POST, then validates the
  /// resulting page positively via [isAuthenticated] — never by checking for
  /// the ABSENCE of a login form, since HISinOne renders a hidden
  /// `sessionTimeoutLoginForm` on every page regardless of session state.
  ///
  /// [successSignal]/[failureSignal] are substrings of the login response's
  /// `Location` header that identify a successful versus a rejected login,
  /// e.g. `category=menu.browse` / `hisinoneStartPage.faces`. A `Location`
  /// matching neither is [HisInOneSessionFailureKind.structureChanged]: this
  /// flow does not know what the portal just told it, so it never guesses.
  Future<HisInOnePage> login({
    required String loginUrl,
    required String username,
    required String password,
    required String successSignal,
    required String failureSignal,
    required Future<bool> Function(String html) isAuthenticated,
  }) async {
    final Response<dynamic> loginResponse = await _dio.postUri(
      _validated(loginUrl),
      data: <String, String>{'asdf': username, 'fdsa': password},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final int loginStatus = loginResponse.statusCode ?? 0;
    if (loginStatus < 300 || loginStatus >= 400) {
      throw const HisInOneSessionFailure(
        HisInOneSessionFailureKind.unavailable,
      );
    }
    final String location = loginResponse.headers.value('location') ?? '';
    if (location.isEmpty) {
      throw const HisInOneSessionFailure(
        HisInOneSessionFailureKind.structureChanged,
      );
    }
    // Validate the redirect target BEFORE inspecting it for the
    // success/fail signal: a malicious redirect to another host or to HTTP
    // must always surface as hostRejected, never be reclassified as an
    // ordinary login failure just because it lacks the expected marker.
    final Uri target = _validated(
      location,
      relativeTo: loginResponse.requestOptions.uri,
    );
    if (location.contains(failureSignal)) {
      throw const HisInOneSessionFailure(
        HisInOneSessionFailureKind.loginRejected,
      );
    }
    if (!location.contains(successSignal)) {
      throw const HisInOneSessionFailure(
        HisInOneSessionFailureKind.structureChanged,
      );
    }
    final HisInOnePage landing = await _follow(_dio.getUri(target));
    if (!await isAuthenticated(landing.html)) {
      throw const HisInOneSessionFailure(
        HisInOneSessionFailureKind.loginRejected,
      );
    }
    return landing;
  }

  /// Fetches one page, following redirects, each hop re-validated.
  Future<HisInOnePage> fetchPage(String url) =>
      _follow(_dio.getUri(_validated(url)));

  /// Posts a form (every field taken from an already-loaded page — nothing
  /// hard-coded) to its own action URL.
  Future<HisInOnePage> postForm(String url, Map<String, String> formData) =>
      _follow(
        _dio.postUri(
          _validated(url),
          data: formData,
          options: Options(contentType: Headers.formUrlEncodedContentType),
        ),
      );

  /// Fetches one binary response through this session's in-memory cookie jar.
  ///
  /// Certificate links may use a deliberately separate, narrowly allowlisted
  /// host. The caller supplies that second allowlist; every redirect is still
  /// validated before it is followed. Keeping this on the session is
  /// important: opening a second [Dio] instance would silently drop the
  /// authenticated session cookies used by a real HISinOne download.
  Future<Response<ResponseBody>> fetchStream(
    String url, {
    required bool Function(Uri uri) allowsTarget,
  }) async {
    Uri target = _validatedWith(url, allowsTarget: allowsTarget);
    Response<ResponseBody> current = await _dio.getUri<ResponseBody>(
      target,
      options: Options(responseType: ResponseType.stream),
    );
    for (int hop = 0; hop < _maxHops; hop++) {
      final int code = current.statusCode ?? 0;
      if (code < 300 || code >= 400) return current;
      final String? location = current.headers.value('location');
      if (location == null) {
        throw const HisInOneSessionFailure(
          HisInOneSessionFailureKind.structureChanged,
        );
      }
      target = _validatedWith(
        location,
        allowsTarget: allowsTarget,
        relativeTo: current.requestOptions.uri,
      );
      current = await _dio.getUri<ResponseBody>(
        target,
        options: Options(responseType: ResponseType.stream),
      );
    }
    throw const HisInOneSessionFailure(HisInOneSessionFailureKind.unavailable);
  }

  /// Best effort: calls [logoutUrl], then wipes every session trace. Safe to
  /// call even when the session never fully logged in.
  Future<void> close(String logoutUrl) async {
    try {
      await _dio.getUri(_validated(logoutUrl));
    } catch (_) {}
    try {
      await _jar.deleteAll();
    } catch (_) {}
    _dio.close(force: true);
  }

  /// Validates a URL is HTTPS on the pinned host, resolving relative links
  /// against [baseUrl]. Refuses anything else.
  Uri _validated(String raw, {Uri? relativeTo}) =>
      _validatedWith(raw, allowsTarget: allows, relativeTo: relativeTo);

  Uri _validatedWith(
    String raw, {
    required bool Function(Uri uri) allowsTarget,
    Uri? relativeTo,
  }) {
    Uri uri = Uri.parse(raw);
    if (!uri.hasScheme) {
      uri = (relativeTo ?? Uri.parse(baseUrl)).resolveUri(uri);
    }
    if (!allowsTarget(uri)) {
      throw const HisInOneSessionFailure(
        HisInOneSessionFailureKind.hostRejected,
      );
    }
    return uri;
  }

  /// Follows redirects from an initial response to a 2xx HTML page,
  /// validating every hop's target.
  Future<HisInOnePage> _follow(Future<Response<dynamic>> initial) async {
    Response<dynamic> current = await initial;
    for (int hop = 0; hop < _maxHops; hop++) {
      final int code = current.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        return HisInOnePage(
          current.requestOptions.uri.toString(),
          current.data?.toString() ?? '',
        );
      }
      if (code >= 300 && code < 400) {
        final String? location = current.headers.value('location');
        if (location == null) {
          throw const HisInOneSessionFailure(
            HisInOneSessionFailureKind.structureChanged,
          );
        }
        current = await _dio.getUri(
          _validated(location, relativeTo: current.requestOptions.uri),
        );
        continue;
      }
      throw const HisInOneSessionFailure(
        HisInOneSessionFailureKind.unavailable,
      );
    }
    throw const HisInOneSessionFailure(HisInOneSessionFailureKind.unavailable);
  }

  /// Maps a transport-level [DioException] onto the same classification the
  /// hand-written checks above use.
  static HisInOneSessionFailure mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const HisInOneSessionFailure(HisInOneSessionFailureKind.timeout);
      case DioExceptionType.connectionError:
        return const HisInOneSessionFailure(
          HisInOneSessionFailureKind.networkUnavailable,
        );
      case DioExceptionType.badCertificate:
        return const HisInOneSessionFailure(
          HisInOneSessionFailureKind.hostRejected,
        );
      case DioExceptionType.badResponse:
        return const HisInOneSessionFailure(
          HisInOneSessionFailureKind.unavailable,
        );
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        final Object? inner = e.error;
        if (inner is Exception &&
            inner.runtimeType.toString().contains('Handshake')) {
          return const HisInOneSessionFailure(
            HisInOneSessionFailureKind.hostRejected,
          );
        }
        return const HisInOneSessionFailure(
          HisInOneSessionFailureKind.networkUnavailable,
        );
    }
  }
}
