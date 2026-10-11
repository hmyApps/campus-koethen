// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Reads what someone typed as the person to chat with.
///
/// Accepts a full Matrix ID (`@name:server`) or just the name, which is then
/// completed with [ownServerName] — the server part of the signed-in
/// account, not the homeserver host (they can differ). Returns `null` for
/// anything that is not a user ID, so nothing is guessed at.
String? parseMatrixUserId(String input, {required String ownServerName}) {
  final String trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final String candidate = trimmed.startsWith('@')
      ? trimmed
      : '@$trimmed:$ownServerName';
  return _userId.hasMatch(candidate) ? candidate : null;
}

/// `@localpart:server_name`, server name a host name or IP with an optional
/// port. Localparts are kept permissive (historical IDs contain more than the
/// current grammar allows) but never whitespace or a colon.
final RegExp _userId = RegExp(
  r'^@[^\s:@]{1,255}:(?:[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*|\[[0-9A-Fa-f:.]+\])(?::[0-9]{1,5})?$',
);

/// The server part of a Matrix ID, or `null`.
String? matrixServerNameOf(String userId) {
  final int colon = userId.indexOf(':');
  if (!userId.startsWith('@') || colon < 2 || colon == userId.length - 1) {
    return null;
  }
  return userId.substring(colon + 1);
}
