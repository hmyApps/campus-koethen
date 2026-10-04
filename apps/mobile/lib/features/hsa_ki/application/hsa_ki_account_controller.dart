// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../university_account/application/university_account_controller.dart';
import '../../university_account/domain/university_identity.dart';
import '../domain/hsa_ki_account.dart';
import 'hsa_ki_providers.dart';

/// Owns the HSA-GPT (HAWKI) connection: mints a personal API token in
/// exchange for the central identity once, keeps only that token.
class HsaKiAccountController extends AsyncNotifier<HsaKiAccount?> {
  @override
  Future<HsaKiAccount?> build() async =>
      (await ref.read(hsaKiCredentialStoreProvider).read())?.toAccount();

  /// Explicit `+`: logs in once with [username]/[password], mints a token,
  /// stores only the token. The password itself is never persisted.
  Future<void> connect({
    required String username,
    required String password,
  }) async {
    if (state.value != null) return;
    state = const AsyncLoading<HsaKiAccount?>();
    try {
      final HsaKiCredential credential = await ref
          .read(hsaKiGatewayProvider)
          .connect(username: username, password: password);
      try {
        await ref.read(hsaKiCredentialStoreProvider).write(credential);
      } catch (_) {
        await _discard(credential, password);
        rethrow;
      }
      ref.read(hsaKiSessionGenerationProvider.notifier).advance();
      state = AsyncData<HsaKiAccount?>(credential.toAccount());
    } catch (error, stackTrace) {
      state = AsyncError<HsaKiAccount?>(error, stackTrace);
    }
  }

  Future<void> _discard(HsaKiCredential credential, String password) async {
    try {
      await ref
          .read(hsaKiGatewayProvider)
          .revoke(credential, password: password);
    } catch (_) {
      // Best effort only; the credential was never exposed as connected.
    }
  }

  /// Explicit `−`: best-effort remote revoke (needs the central identity's
  /// password again, read fresh and never stored by this feature), but the
  /// local token wipe always happens regardless of whether that succeeds.
  Future<void> disconnect() async {
    final HsaKiCredentialStore store = ref.read(hsaKiCredentialStoreProvider);
    HsaKiCredential? credential;
    try {
      credential = await store.read();
    } catch (_) {
      // Fall through to the canonical wipe below even if the secure backend
      // cannot currently produce a coherent credential.
    }
    if (credential != null) {
      final UniversityIdentity? identity = await ref
          .read(universityIdentityStoreProvider)
          .read();
      if (identity != null) {
        try {
          await ref
              .read(hsaKiGatewayProvider)
              .revoke(credential, password: identity.password);
        } catch (_) {
          // A server outage or an already-expired token must not keep a
          // bearer credential on the device.
        }
      }
    }
    Object? localFailure;
    try {
      await store.clear();
    } catch (error) {
      localFailure = error;
    }
    ref.read(hsaKiSessionGenerationProvider.notifier).advance();
    state = const AsyncData<HsaKiAccount?>(null);
    if (localFailure != null) throw localFailure;
  }
}

final AsyncNotifierProvider<HsaKiAccountController, HsaKiAccount?>
hsaKiAccountControllerProvider =
    AsyncNotifierProvider<HsaKiAccountController, HsaKiAccount?>(
      HsaKiAccountController.new,
      retry: (_, _) => null,
    );
