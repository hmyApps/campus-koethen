// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Exact network boundary for the Hochschule Anhalt Nextcloud instance.
class NextcloudProfile {
  const NextcloudProfile();

  static const String host = 'cloud.hs-anhalt.de';
  static final Uri server = Uri.parse('https://$host');

  Uri get loginFlowUri => server.resolve('/index.php/login/v2');
  Uri get currentUserUri =>
      server.resolve('/ocs/v2.php/cloud/user?format=json');
  Uri get revokeAppPasswordUri =>
      server.resolve('/ocs/v2.php/core/apppassword?format=json');
  Uri get sharesUri => server.resolve(
    '/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json',
  );

  bool allows(Uri uri) =>
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == host &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;

  bool allowsLoginUri(Uri uri) =>
      allows(uri) &&
      uri.fragment.isEmpty &&
      (uri.path.startsWith('/login/v2/flow/') ||
          uri.path.startsWith('/index.php/login/v2/flow/'));

  bool allowsPollUri(Uri uri) =>
      allows(uri) &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty &&
      (uri.path == '/login/v2/poll' || uri.path == '/index.php/login/v2/poll');

  bool allowsPublicShareUri(Uri uri) {
    if (!allows(uri) ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !_isPublicSharePath(uri.pathSegments)) {
      return false;
    }
    try {
      _validateSegment(uri.pathSegments.last);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  bool _isPublicSharePath(List<String> segments) =>
      (segments.length == 2 && segments.first == 's') ||
      (segments.length == 3 &&
          segments.first == 'index.php' &&
          segments[1] == 's');

  Uri davUri({required String userId, required String path}) {
    final List<String> segments = <String>[
      'remote.php',
      'dav',
      'files',
      _validateSegment(userId),
      ...normalizedSegments(path),
    ];
    return Uri(scheme: 'https', host: host, pathSegments: segments);
  }

  List<String> normalizedSegments(String path) {
    if (!path.startsWith('/')) throw ArgumentError.value(path, 'path');
    if (path == '/') return const <String>[];
    final List<String> segments = path.substring(1).split('/');
    return segments.map(_validateSegment).toList(growable: false);
  }

  String normalizedPath(Iterable<String> segments) {
    final List<String> checked = segments.map(_validateSegment).toList();
    return checked.isEmpty ? '/' : '/${checked.join('/')}';
  }

  String _validateSegment(String value) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\') ||
        _controlCharacters.hasMatch(value)) {
      throw ArgumentError.value(value, 'path segment');
    }
    return value;
  }
}

final RegExp _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');
