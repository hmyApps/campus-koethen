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
  ///
  /// Completing normally always means HAWKI has just accepted exactly these
  /// credentials, because the university connector treats a returned
  /// `connect` as a successful credential check before it retains or replaces
  /// the central identity. Therefore every failure is rethrown, and an
  /// existing connection is never accepted unchecked: it is re-verified by
  /// minting a fresh token, which then replaces the previous one.
  Future<void> connect({
    required String username,
    required String password,
  }) async {
    final HsaKiCredentialStore store = ref.read(hsaKiCredentialStoreProvider);
    final HsaKiAccount? previousAccount = state.value;
    state = const AsyncLoading<HsaKiAccount?>();

    final HsaKiCredential credential;
    HsaKiCredential? superseded;
    try {
      credential = await ref
          .read(hsaKiGatewayProvider)
          .connect(username: username, password: password);
      superseded = await _readQuietly(store);
    } catch (error, stackTrace) {
      // Rejected before any local mutation: whatever was connected before
      // stays connected, and the caller learns that the check failed.
      state = AsyncData<HsaKiAccount?>(previousAccount);
      Error.throwWithStackTrace(error, stackTrace);
    }

    try {
      await store.write(credential);
    } catch (error, stackTrace) {
      // The secure store drops a partially written credential, which also
      // takes any previous token with it. Neither token may stay usable.
      await _discard(credential, password);
      if (superseded != null) await _discard(superseded, password);
      try {
        await store.clear();
      } catch (_) {
        // Best effort; the write failure below is what the caller reports.
      }
      ref.read(hsaKiSessionGenerationProvider.notifier).advance();
      state = const AsyncData<HsaKiAccount?>(null);
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (superseded != null && superseded.tokenId != credential.tokenId) {
      // The replaced token is no longer held locally; revoke it remotely so
      // it does not linger as a valid bearer credential on HAWKI.
      await _discard(superseded, password);
    }
    ref.read(hsaKiSessionGenerationProvider.notifier).advance();
    state = AsyncData<HsaKiAccount?>(credential.toAccount());
  }

  static Future<HsaKiCredential?> _readQuietly(
    HsaKiCredentialStore store,
  ) async {
    try {
      return await store.read();
    } catch (_) {
      return null;
    }
  }

  Future<void> _discard(HsaKiCredential credential, String password) async {
    try {
      await ref
          .read(hsaKiGatewayProvider)
          .revoke(credential, password: password);
    } catch (_) {
      // Best effort only; the local copy is gone either way.
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
