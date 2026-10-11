// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

/// The one Matrix homeserver this build may talk to (AGENTS.md §2).
///
/// Supplied **exclusively** via `--dart-define=MATRIX_HOMESERVER_URL=…`: no
/// hard-coded host, no server the user types in and no `.well-known`
/// discovery. Without a usable value the chat says it is not configured
/// instead of guessing.
abstract final class MatrixConfig {
  static const String homeserverUrl = String.fromEnvironment(
    'MATRIX_HOMESERVER_URL',
  );

  /// The configured homeserver, or `null` when this build has none.
  static MatrixHomeserver? get homeserver =>
      MatrixHomeserver.parse(homeserverUrl);
}

/// An exact Matrix homeserver origin: scheme, host and port.
///
/// Not a suffix test — `matrix.example.test.attacker.test` ends with the
/// configured host and must still be refused.
@immutable
class MatrixHomeserver {
  const MatrixHomeserver._(this.host, this.port);

  final String host;
  final int port;

  /// Parses a bare HTTPS origin (an optional trailing `/` is accepted).
  ///
  /// Returns `null` for anything else: empty, relative, not HTTPS, with
  /// credentials, with a path, query or fragment. `http://` is refused rather
  /// than upgraded: tokens and room keys never travel in the clear.
  static MatrixHomeserver? parse(String? value) {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return null;
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.isAbsolute) return null;
    if (uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (uri.userInfo.isNotEmpty) return null;
    if (uri.path.isNotEmpty && uri.path != '/') return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    return MatrixHomeserver._(uri.host.toLowerCase(), uri.port);
  }

  /// The homeserver base the SDK is pointed at.
  Uri get baseUri =>
      Uri(scheme: 'https', host: host, port: port == 443 ? null : port);

  /// Whether [uri] targets exactly this origin. Paths are the server's own.
  bool allows(Uri uri) =>
      uri.isAbsolute &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.host.toLowerCase() == host &&
      uri.port == port;

  @override
  bool operator ==(Object other) =>
      other is MatrixHomeserver && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  /// The origin only.
  @override
  String toString() => 'MatrixHomeserver($baseUri)';
}
