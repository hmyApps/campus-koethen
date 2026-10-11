// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The pinned Moodle endpoints of Hochschule Anhalt.
///
/// The single source of truth for the ONE host the token and personal data may
/// ever reach. Every request is validated with [allows]; anything that is not
/// HTTPS on exactly [host] is refused, and the token is only ever sent there.
class MoodleProfile {
  const MoodleProfile();

  String get scheme => 'https';

  /// The only host the Moodle token may be sent to.
  String get host => 'moodle.hs-anhalt.de';

  String get baseUrl => 'https://moodle.hs-anhalt.de';

  /// `POST` form-urlencoded token endpoint (`username`, `password`, `service`).
  String get tokenUrl => 'https://moodle.hs-anhalt.de/login/token.php';

  /// `POST` REST endpoint (`wstoken`, `wsfunction`, `moodlewsrestformat=json`).
  String get restUrl =>
      'https://moodle.hs-anhalt.de/webservice/rest/server.php';

  /// The mobile web service the token is issued for.
  String get service => 'moodle_mobile_app';

  /// "Open in browser" target.
  String get webUrl => 'https://moodle.hs-anhalt.de';

  /// The token-free Moodle Web page of one activity,
  /// `/mod/<modName>/view.php?id=<cmid>`, or `null` when it cannot be built
  /// safely.
  ///
  /// For what the app does not show itself (a quiz, a forum, handing in an
  /// assignment): the reader signs in to Moodle Web in their own browser. No
  /// token, user id or other personal value ever goes into the link, and
  /// [modName] — the module type Moodle reported — must be a plain plugin
  /// name, so it cannot step out of `/mod/`.
  Uri? moduleWebUri({required String modName, required int? cmid}) {
    if (cmid == null || cmid <= 0) return null;
    if (!_pluginName.hasMatch(modName)) return null;
    final Uri uri = Uri.parse(webUrl).replace(
      path: '/mod/$modName/view.php',
      queryParameters: <String, String>{'id': '$cmid'},
    );
    return allows(uri) ? uri : null;
  }

  static final RegExp _pluginName = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

  /// True only for the exact HTTPS origin represented by [baseUrl].
  ///
  /// A hostname check alone is not enough for token-bearing requests: a
  /// different service can listen on a non-default port of the same host, and
  /// user-info must never be accepted as part of a credential-bearing URL.
  bool allows(Uri uri) =>
      uri.isAbsolute &&
      uri.scheme == scheme &&
      uri.host.toLowerCase() == host &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;
}
