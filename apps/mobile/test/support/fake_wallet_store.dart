// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/document_wallet/domain/wallet_document.dart';

/// A wallet store that keeps nothing, for tests that only need the full wipe
/// to succeed without opening the encrypted box.
class NoopWalletStore implements DocumentWalletStore {
  @override
  Future<List<WalletDocument>> readAll() async => const <WalletDocument>[];

  @override
  Future<void> save(WalletDocument document) async {}

  @override
  Future<void> delete(WalletDocumentKind kind) async {}

  @override
  Future<void> deleteCustom(String id) async {}

  @override
  Future<void> clearGradeLinked() async {}

  @override
  Future<void> clear() async {}
}
