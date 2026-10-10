// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

/// The secured Moodle session: the web service token plus the ids needed to
/// call the API. This object NEVER leaves [MoodleTokenStore] / secure storage.
/// [toString] deliberately redacts the token so it can never reach a log.
@immutable
class MoodleToken {
  const MoodleToken({
    required this.value,
    required this.userId,
    this.username,
    this.siteName,
  });

  /// The web service token. Only ever sent to `moodle.hs-anhalt.de`.
  final String value;

  /// The Moodle user id (needed by e.g. `core_enrol_get_users_courses`).
  final int userId;

  final String? username;
  final String? siteName;

  /// The public-facing view of this session, with the secret stripped.
  MoodleAccount toAccount() =>
      MoodleAccount(userId: userId, username: username, siteName: siteName);

  @override
  String toString() => 'MoodleToken(userId: $userId, token: «redacted»)';
}

/// The publicly observable connection state. Carries NO token and NO password —
/// only what the UI may show. This is what the account controller exposes.
@immutable
class MoodleAccount {
  const MoodleAccount({required this.userId, this.username, this.siteName});

  final int userId;
  final String? username;
  final String? siteName;

  @override
  bool operator ==(Object other) =>
      other is MoodleAccount &&
      other.userId == userId &&
      other.username == username &&
      other.siteName == siteName;

  @override
  int get hashCode => Object.hash(userId, username, siteName);
}

/// Basic site metadata returned by `core_webservice_get_site_info`, used to
/// verify a freshly issued token before it is ever stored.
@immutable
class MoodleSiteInfo {
  const MoodleSiteInfo({
    required this.userId,
    this.username,
    this.fullName,
    this.siteName,
  });

  final int userId;
  final String? username;
  final String? fullName;
  final String? siteName;
}

/// Port: at-rest storage for the secured [MoodleToken].
///
/// The only place a token may be persisted is a concrete implementation backed
/// by the platform secure storage. No SharedPreferences, no plain Hive, no
/// in-memory-only Riverpod state, no static field.
abstract interface class MoodleTokenStore {
  /// Null means "no token stored". A secure backend that cannot be read throws
  /// a `MoodleFailure` instead, so it is never mistaken for a disconnect.
  Future<MoodleToken?> read();
  Future<void> write(MoodleToken token);
  Future<void> clear();
}
