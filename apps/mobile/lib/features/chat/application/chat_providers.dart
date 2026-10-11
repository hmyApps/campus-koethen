// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/encrypted_matrix_database.dart';
import '../data/sdk_matrix_gateway.dart';
import '../data/secure_matrix_database_key_store.dart';
import '../domain/chat_key_backup.dart';
import '../domain/chat_models.dart';
import '../domain/matrix_failure.dart';
import '../domain/matrix_gateway.dart';
import '../domain/matrix_homeserver.dart';

/// The homeserver of this build, or `null` when the chat is not part of it.
final Provider<MatrixHomeserver?> matrixHomeserverProvider =
    Provider<MatrixHomeserver?>((Ref ref) => MatrixConfig.homeserver);

final Provider<MatrixGateway> matrixGatewayProvider = Provider<MatrixGateway>((
  Ref ref,
) {
  final SdkMatrixGateway gateway = SdkMatrixGateway(
    homeserver: ref.watch(matrixHomeserverProvider),
    database: EncryptedMatrixDatabase(keyStore: SecureMatrixDatabaseKeyStore()),
  );
  ref.onDispose(() => unawaited(gateway.dispose()));
  return gateway;
});

/// The Matrix session: `null` while signed out.
class ChatSessionController extends AsyncNotifier<MatrixAccount?> {
  @override
  Future<MatrixAccount?> build() {
    final MatrixGateway gateway = ref.read(matrixGatewayProvider);
    final StreamSubscription<void> changes = gateway.changes.listen(
      (_) => _noticeEndedSession(gateway),
    );
    ref.onDispose(changes.cancel);
    return gateway.restore();
  }

  bool _loggingIn = false;
  bool _endingSession = false;

  /// The server can end the session on its own (signed out from another
  /// device, token revoked). The SDK then forgets it; this wipes what is
  /// left on the device and says what happened.
  void _noticeEndedSession(MatrixGateway gateway) {
    if (_endingSession || _loggingIn || state.isLoading) return;
    if (chatAccountOf(state) == null || gateway.account != null) return;
    unawaited(_endSession(gateway));
  }

  Future<void> _endSession(MatrixGateway gateway) async {
    _endingSession = true;
    try {
      await gateway.logout();
      state = AsyncError<MatrixAccount?>(
        const MatrixFailure(MatrixFailureKind.sessionEnded),
        StackTrace.current,
      );
    } catch (error, stackTrace) {
      state = AsyncError<MatrixAccount?>(error, stackTrace);
    } finally {
      _endingSession = false;
    }
  }

  /// A failed login ends up as the state's error. The state is deliberately
  /// not set to loading meanwhile, so the login form (and what was typed)
  /// stays on screen; the form shows its own progress.
  Future<void> login({
    required String username,
    required String password,
  }) async {
    if (_loggingIn || state.isLoading) return;
    _loggingIn = true;
    try {
      state = await AsyncValue.guard(
        () => ref
            .read(matrixGatewayProvider)
            .login(username: username, password: password),
      );
    } finally {
      _loggingIn = false;
    }
  }

  /// `−`: signs the device out at the server (best effort) and wipes the
  /// local database and key (verified). A failed wipe stays visible and can
  /// be retried.
  Future<void> logout() async {
    state = const AsyncLoading<MatrixAccount?>();
    try {
      await ref.read(matrixGatewayProvider).logout();
      state = const AsyncData<MatrixAccount?>(null);
    } catch (error, stackTrace) {
      state = AsyncError<MatrixAccount?>(error, stackTrace);
      rethrow;
    }
  }
}

/// The signed-in account a session state stands for. An error never counts
/// as signed in: Riverpod keeps the previous value on an `AsyncError`, and an
/// ended session or a failed wipe must not keep showing the old account.
MatrixAccount? chatAccountOf(AsyncValue<MatrixAccount?> session) =>
    session.hasError ? null : session.value;

final AsyncNotifierProvider<ChatSessionController, MatrixAccount?>
chatSessionControllerProvider =
    AsyncNotifierProvider<ChatSessionController, MatrixAccount?>(
      ChatSessionController.new,
      retry: (_, _) => null,
    );

/// The key backup of the signed-in account; `null` while signed out.
class ChatKeyBackupController extends AsyncNotifier<ChatKeyBackupState?> {
  @override
  Future<ChatKeyBackupState?> build() async {
    final MatrixAccount? account = chatAccountOf(
      ref.watch(chatSessionControllerProvider),
    );
    if (account == null) return null;
    return ref.read(matrixGatewayProvider).keyBackupState();
  }

  /// Returns the new recovery key, for the caller to show exactly once.
  Future<String> setUp({String? password}) async {
    final MatrixGateway gateway = ref.read(matrixGatewayProvider);
    final String recoveryKey = await gateway.setUpKeyBackup(password: password);
    state = AsyncData<ChatKeyBackupState?>(await gateway.keyBackupState());
    return recoveryKey;
  }

  Future<void> unlock(String recoveryKey) async {
    final MatrixGateway gateway = ref.read(matrixGatewayProvider);
    await gateway.unlockKeyBackup(recoveryKey);
    state = AsyncData<ChatKeyBackupState?>(await gateway.keyBackupState());
  }

  /// Returns the new recovery key, for the caller to show exactly once.
  Future<String> reset({required String password}) async {
    final MatrixGateway gateway = ref.read(matrixGatewayProvider);
    final String recoveryKey = await gateway.resetKeyBackup(password: password);
    state = AsyncData<ChatKeyBackupState?>(await gateway.keyBackupState());
    return recoveryKey;
  }
}

final AsyncNotifierProvider<ChatKeyBackupController, ChatKeyBackupState?>
chatKeyBackupControllerProvider =
    AsyncNotifierProvider<ChatKeyBackupController, ChatKeyBackupState?>(
      ChatKeyBackupController.new,
      retry: (_, _) => null,
    );

/// The rooms of the signed-in account, refreshed on every sync.
final StreamProvider<List<ChatRoomSummary>> chatRoomsProvider =
    StreamProvider<List<ChatRoomSummary>>((Ref ref) async* {
      final MatrixAccount? account = await ref.watch(
        chatSessionControllerProvider.future,
      );
      if (account == null) {
        yield const <ChatRoomSummary>[];
        return;
      }
      final MatrixGateway gateway = ref.watch(matrixGatewayProvider);
      // Subscribed before the first value goes out, so no change between the
      // two is lost.
      final StreamController<List<ChatRoomSummary>> rooms =
          StreamController<List<ChatRoomSummary>>();
      final StreamSubscription<void> changes = gateway.changes.listen(
        (_) => rooms.add(gateway.rooms),
      );
      ref.onDispose(() {
        unawaited(changes.cancel());
        unawaited(rooms.close());
      });
      rooms.add(gateway.rooms);
      yield* rooms.stream;
    }, retry: (_, _) => null);
