// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The bearer credential this feature actually keeps: a personal, revocable
/// Sanctum access token minted once via HAWKI's own self-service "Access
/// Tokens" profile feature — never the central university password itself,
/// which is used only transiently during [tokenId]'s one-time creation.
class HsaKiCredential {
  const HsaKiCredential({
    required this.token,
    required this.tokenId,
    required this.username,
  });

  /// The literal `Authorization: Bearer <token>` value.
  final String token;

  /// The token's own server-side id, required to revoke it (`tokenId` in
  /// `POST /req/profile/revoke-token`) — distinct from the token string.
  final String tokenId;

  /// The HSA account identifier the token was minted for, kept only for
  /// display (e.g. "Verbunden als …") — never the password.
  final String username;

  HsaKiAccount toAccount() => HsaKiAccount(username: username);

  @override
  String toString() => 'HsaKiCredential(username: $username, «redacted»)';
}

abstract interface class HsaKiCredentialStore {
  Future<HsaKiCredential?> read();
  Future<void> write(HsaKiCredential credential);
  Future<void> clear();
}

/// The public, non-secret view of a connected account.
class HsaKiAccount {
  const HsaKiAccount({required this.username});

  final String username;

  @override
  bool operator ==(Object other) =>
      other is HsaKiAccount && other.username == username;

  @override
  int get hashCode => username.hashCode;
}
