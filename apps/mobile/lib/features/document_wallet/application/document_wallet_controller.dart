// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/documents/app_document.dart';
import '../../../core/security/session_guard.dart';
import '../../grades/application/grade_account_controller.dart';
import '../data/encrypted_document_wallet_store.dart';
import '../domain/wallet_document.dart';

final Provider<DocumentWalletStore> documentWalletStoreProvider =
    Provider<DocumentWalletStore>((Ref ref) => EncryptedDocumentWalletStore());

final Provider<SessionGuard<String>> documentWalletSessionGuardProvider =
    Provider<SessionGuard<String>>((Ref ref) => SessionGuard<String>());

class DocumentWalletController extends AsyncNotifier<List<WalletDocument>> {
  DocumentWalletStore get _store => ref.read(documentWalletStoreProvider);
  SessionGuard<String> get _sessions =>
      ref.read(documentWalletSessionGuardProvider);

  @override
  Future<List<WalletDocument>> build() async {
    // Await the authoritative account build. When a previous account wipe was
    // interrupted, that build performs the catch-up wipe before publishing a
    // signed-out state; reading in parallel could briefly expose stale PDFs.
    final GradeAccountState account = await ref.watch(
      gradeAccountControllerProvider.future,
    );
    if (account.username case final String username) {
      _sessions.activate(username);
    } else {
      await _sessions.invalidateAndWait();
    }
    // Reading stays independent from network and sign-in state. A temporary
    // portal outage must never make an already stored offline PDF disappear.
    return _store.readAll();
  }

  Future<void> save({
    required WalletDocumentKind kind,
    required AppDocument document,
  }) async {
    // The session is (re-)activated only in build(). Saving straight from a
    // document viewer — the wallet never opened in this session, or opened
    // before a portal/account switch invalidated the guard — otherwise found
    // an inactive guard and failed. `future` flushes a pending rebuild and
    // waits for it; `initializeIfNeeded` would not revive an invalidated
    // guard by design.
    await future;
    final String? username = ref
        .read(gradeAccountControllerProvider)
        .value
        ?.username;
    if (username == null) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.storageUnavailable,
      );
    }
    final SessionLease<String>? lease = _sessions.capture(username);
    if (lease == null) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.storageUnavailable,
      );
    }
    await _sessions.track<void>(lease, () async {
      if (!_isCurrent(lease)) return;
      await _store.save(
        WalletDocument.fromAppDocument(
          kind: kind,
          document: document,
          savedAt: DateTime.now(),
        ),
      );
      if (!_isCurrent(lease)) return;
      state = AsyncData<List<WalletDocument>>(await _store.readAll());
    });
  }

  Future<void> delete(WalletDocumentKind kind) async {
    await _store.delete(kind);
    state = AsyncData<List<WalletDocument>>(await _store.readAll());
  }

  bool _isCurrent(SessionLease<String> lease) =>
      _sessions.isCurrent(lease) &&
      ref.read(gradeAccountControllerProvider).value?.username ==
          lease.identity;
}

final AsyncNotifierProvider<DocumentWalletController, List<WalletDocument>>
documentWalletControllerProvider =
    AsyncNotifierProvider<DocumentWalletController, List<WalletDocument>>(
      DocumentWalletController.new,
      retry: (_, _) => null,
    );
