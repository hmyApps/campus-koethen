// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'hsa_ki_account.dart';
import 'hsa_ki_chat.dart';

abstract interface class HsaKiGateway {
  /// Logs in with the central university identity ONCE and immediately
  /// mints a personal, revocable API token in exchange for it. The password
  /// is used only for this single request and is never retained — only the
  /// returned [HsaKiCredential.token] is.
  Future<HsaKiCredential> connect({
    required String username,
    required String password,
  });

  /// Best effort: revokes [credential] server-side. HAWKI's token-revoke
  /// route is a web-session one, not a bearer-token one (confirmed from the
  /// real source: `ProfileController::revokeToken` sits behind the session
  /// `auth` guard, not `auth:sanctum`) — so this needs [password] again, read
  /// fresh by the caller from the still-present central identity, never
  /// stored by this feature itself. A caller with no password available
  /// (central identity already gone) must skip this and wipe the local
  /// credential on its own — never block a disconnect on it.
  Future<void> revoke(
    HsaKiCredential credential, {
    required String password,
  });

  Future<List<HsaKiModel>> listModels(HsaKiCredential credential);

  /// One stateless request/response turn. HAWKI's external endpoint keeps no
  /// conversation of its own, so every call carries the full message history
  /// the caller wants the model to see.
  Future<String> sendMessage(
    HsaKiCredential credential, {
    required String modelId,
    required List<HsaKiMessage> messages,
  });
}
