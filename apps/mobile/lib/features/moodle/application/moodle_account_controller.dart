// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/moodle_account.dart';
import '../domain/moodle_failure.dart';
import 'moodle_providers.dart';

/// The publicly observable Moodle connection state.
///
/// Null means "not connected". This never carries a token or password — the
/// token lives only in secure storage behind the repository.
class MoodleAccountController extends AsyncNotifier<MoodleAccount?> {
  @override
  Future<MoodleAccount?> build() =>
      ref.read(moodleRepositoryProvider).currentAccount();

  bool get isConnected => state.value != null;

  /// Verifies credentials and, only on success, stores the token. The password
  /// is never persisted. Throws a [MoodleFailure] on failure.
  Future<void> connect({
    required String username,
    required String password,
  }) async {
    final bool wasConnected = state.value != null;
    final MoodleAccount account;
    try {
      account = await ref
          .read(moodleRepositoryProvider)
          .connect(username: username, password: password);
    } catch (error, stackTrace) {
      if (wasConnected &&
          error is MoodleFailure &&
          (error.kind == MoodleFailureKind.secureStorageUnavailable ||
              error.kind == MoodleFailureKind.cacheUnavailable)) {
        // Credential rejection happens before mutation and keeps the old
        // account. These failures happen at the local replacement boundary,
        // which must no longer be shown as a healthy old connection.
        state = AsyncError<MoodleAccount?>(error, stackTrace);
      }
      rethrow;
    }
    // A new account must not inherit anything the previous one left in
    // memory, even if disconnect() was never called in between.
    ref.read(moodleSessionGenerationProvider.notifier).advance();
    state = AsyncData<MoodleAccount?>(account);
  }

  /// Wipes token, user id, encrypted cache, cache key and sync timestamps.
  ///
  /// Advances the session generation FIRST, so the in-memory course bundles go
  /// at the same moment as the stored ones. They used to outlive the wipe.
  Future<void> disconnect() async {
    ref.read(moodleSessionGenerationProvider.notifier).advance();
    await ref.read(moodleRepositoryProvider).disconnect();
    state = const AsyncData<MoodleAccount?>(null);
  }
}

final AsyncNotifierProvider<MoodleAccountController, MoodleAccount?>
moodleAccountControllerProvider =
    AsyncNotifierProvider<MoodleAccountController, MoodleAccount?>(
      MoodleAccountController.new,
      retry: (_, _) => null,
    );
