// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Configuration of the Campus API connection.
///
/// The base URL is supplied **exclusively** via
/// `--dart-define=API_BASE_URL=…`. There is no other source, no build flavour
/// file and no hard-coded production host. DEV and PROD differ by environment
/// only.
abstract final class ApiConfig {
  /// Origin of the Campus API, e.g. `https://api.example.org`.
  ///
  /// The plaintext localhost default is for development only. It used to be
  /// accepted silently in any build: a release without `--dart-define` started
  /// against `http://localhost:3000`, where the platform's own cleartext rules
  /// (iOS ATS, Android's cleartext default) block every request — so an
  /// unconfigured build did not announce itself, it just failed at everything
  /// (S-11). [isConfigured] and [configurationProblem] make that state
  /// visible instead.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _developmentDefault,
  );

  static const String _developmentDefault = 'http://localhost:3000';

  /// Whether [baseUrl] came from a Dart define rather than the fallback.
  ///
  /// Comparing the value with [_developmentDefault] is insufficient: a local
  /// developer may deliberately configure that exact origin. `hasEnvironment`
  /// distinguishes that from an APK which silently inherited the fallback.
  static const bool _hasExplicitBaseUrl = bool.hasEnvironment('API_BASE_URL');

  /// Explicit opt-in for a loopback endpoint during local work.
  ///
  /// This is deliberately independent from the build mode. A debug APK is
  /// still installable on a real phone, where `localhost` points at the phone
  /// itself; being a debug build must not silently make an invalid endpoint
  /// trustworthy.
  static const bool _allowLocalApi = bool.fromEnvironment(
    'ALLOW_LOCAL_API',
    defaultValue: false,
  );

  /// Why this build's [baseUrl] is unusable, or `null` when it is fine.
  ///
  /// * Not HTTPS and not an explicitly local address → refused. There is no
  ///   silent upgrade: guessing at a scheme is how a plaintext endpoint ends
  ///   up in a release.
  /// * Left at the development default → reported, because a build that was
  ///   never pointed anywhere is a configuration mistake, not a working app.
  static ApiConfigProblem? get configurationProblem => validateBaseUrl(
    baseUrl,
    isExplicitlyConfigured: _hasExplicitBaseUrl,
    allowLoopback: _allowLocalApi,
  );

  /// Validates that [value] is one exact Campus API origin.
  ///
  /// Production origins are HTTPS. Plain HTTP is available solely for an
  /// explicitly opted-in loopback origin during local development. Paths,
  /// query strings and fragments are rejected so callers cannot accidentally
  /// produce `/v1/v1`, tenant-dependent requests or ambiguous cache keys.
  static ApiConfigProblem? validateBaseUrl(
    String value, {
    required bool isExplicitlyConfigured,
    required bool allowLoopback,
  }) {
    if (!isExplicitlyConfigured) return ApiConfigProblem.notConfigured;
    if (value.isEmpty || value != value.trim()) {
      return ApiConfigProblem.malformed;
    }

    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.isAbsolute ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return ApiConfigProblem.malformed;
    }

    final bool isLoopback = _isLoopback(uri.host);
    if (isLoopback && !allowLoopback) {
      return uri.scheme == 'http'
          ? ApiConfigProblem.insecureScheme
          : ApiConfigProblem.malformed;
    }
    if (uri.scheme == 'https') return null;
    // Plain HTTP is tolerated only against an explicitly opted-in loopback
    // address, which is what local development actually needs.
    if (uri.scheme == 'http' && isLoopback) {
      return null;
    }
    return ApiConfigProblem.insecureScheme;
  }

  /// True when this build has a usable Campus API address.
  static bool get isConfigured => configurationProblem == null;

  static bool _isLoopback(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  /// Versioned base path of all content endpoints.
  static const String basePath = '/v1';

  /// Full prefix used by the API client.
  static String get root => '${_stripTrailingSlash(baseUrl)}$basePath';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// Turns a media reference from the API into a URL that can be fetched.
  ///
  /// Editorial images are published as API-relative paths (`/v1/media/…`)
  /// rather than absolute links: the CMS address is configuration and must
  /// never travel in a payload (AGENTS.md §2.4), and the app is forbidden from
  /// talking to the CMS at all (§2.1). Resolving happens here, once, against
  /// the very API the response came from.
  ///
  /// Only the API's own media route is accepted. An absolute URL is refused
  /// even when it uses HTTPS: public/editorial data has exactly one network
  /// boundary, and letting a response name another host would permit tracking
  /// pixels and silently reintroduce a direct third-party data path.
  static String? resolveMediaUrl(String? value) {
    final String path = (value ?? '').trim();
    if (path.isEmpty) return null;

    const String mediaPrefix = '$basePath/media/uploads/';
    if (!path.startsWith(mediaPrefix) || path.length > 512) return null;
    final String filename = path.substring(mediaPrefix.length);
    if (filename.isEmpty || filename == '.' || filename == '..') return null;
    if (!_safeMediaFilename.hasMatch(filename)) return null;

    return '${_stripTrailingSlash(baseUrl)}$path';
  }

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

/// What a media filename may consist of.
///
/// Hoisted out of [ApiConfig.resolveMediaUrl]: `RegExp` parses its pattern on
/// construction, and this one is asked once per image the feed shows.
final RegExp _safeMediaFilename = RegExp(r'^[A-Za-z0-9._-]+$');

/// Why [ApiConfig.baseUrl] cannot be used.
enum ApiConfigProblem {
  /// No `--dart-define=API_BASE_URL` was given, so the development default is
  /// still in place.
  notConfigured,

  /// Not a parseable absolute URL, or one carrying credentials.
  malformed,

  /// Plain HTTP against something other than loopback.
  insecureScheme,
}
