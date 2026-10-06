// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/cache/encrypted_box.dart';
import '../domain/wallet_document.dart';

/// Per-document upper bound. Generated HISinOne PDFs are normally tiny; the
/// limit prevents a malformed response from turning an explicit offline save
/// into unbounded local storage.
const int kMaxDocumentWalletBytes = 25 * 1024 * 1024;

class EncryptedDocumentWalletStore implements DocumentWalletStore {
  EncryptedDocumentWalletStore([EncryptedBox? box])
    : _box =
          box ??
          EncryptedBox(
            boxName: 'campus_document_wallet_v1',
            keyStorageKey: 'document.wallet.key.v1',
          );

  final EncryptedBox _box;

  static String _key(WalletDocumentKind kind) =>
      'document.${kind.storageValue}';

  @override
  Future<List<WalletDocument>> readAll() async {
    final List<WalletDocument> documents = <WalletDocument>[];
    for (final WalletDocumentKind kind in WalletDocumentKind.values) {
      final String? raw = await _box.read(_key(kind));
      if (raw == null) continue;
      try {
        final WalletDocument? document = _decode(jsonDecode(raw));
        if (document != null && document.kind == kind) {
          documents.add(document);
        }
      } catch (_) {
        // One corrupt slot must not hide the other offline document.
      }
    }
    documents.sort(
      (WalletDocument a, WalletDocument b) => b.savedAt.compareTo(a.savedAt),
    );
    return List<WalletDocument>.unmodifiable(documents);
  }

  @override
  Future<void> save(WalletDocument document) async {
    if (!_isValidPdf(document)) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.invalidDocument,
      );
    }
    final String payload = jsonEncode(<String, Object>{
      'kind': document.kind.storageValue,
      'filename': document.filename,
      'mediaType': 'application/pdf',
      'savedAt': document.savedAt.toUtc().toIso8601String(),
      'bytes': base64Encode(document.bytes),
    });
    if (!await _box.writeChecked(_key(document.kind), payload)) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.storageUnavailable,
      );
    }
  }

  @override
  Future<void> delete(WalletDocumentKind kind) async {
    final String key = _key(kind);
    await _box.delete(key);
    if (await _box.read(key) != null) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.storageUnavailable,
      );
    }
  }

  @override
  Future<void> clear() async {
    final EncryptedBoxWipeResult result = await _box.wipeChecked();
    if (!result.isComplete) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.storageUnavailable,
      );
    }
  }

  static WalletDocument? _decode(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> map = Map<String, dynamic>.from(value);
    final WalletDocumentKind? kind = WalletDocumentKind.fromStorage(
      map['kind'] as String?,
    );
    final String? filename = map['filename'] as String?;
    final String? savedAtRaw = map['savedAt'] as String?;
    final String? encodedBytes = map['bytes'] as String?;
    final DateTime? savedAt = savedAtRaw == null
        ? null
        : DateTime.tryParse(savedAtRaw);
    if (kind == null ||
        filename == null ||
        savedAt == null ||
        encodedBytes == null) {
      return null;
    }
    // Reject an impossible encoded size before allocating the decoded byte
    // buffer. Base64 needs at most four characters for every three bytes.
    if (encodedBytes.length > ((kMaxDocumentWalletBytes + 2) ~/ 3) * 4) {
      return null;
    }
    final Uint8List bytes = base64Decode(encodedBytes);
    final WalletDocument document = WalletDocument(
      kind: kind,
      filename: filename,
      mediaType: 'application/pdf',
      bytes: bytes,
      savedAt: savedAt,
    );
    return _isValidPdf(document) ? document : null;
  }

  static bool _isValidPdf(WalletDocument document) {
    if (document.bytes.isEmpty ||
        document.bytes.length > kMaxDocumentWalletBytes ||
        document.mediaType.toLowerCase() != 'application/pdf' ||
        document.bytes.length < 5) {
      return false;
    }
    const List<int> signature = <int>[0x25, 0x50, 0x44, 0x46, 0x2d];
    for (int i = 0; i < signature.length; i++) {
      if (document.bytes[i] != signature[i]) return false;
    }
    return true;
  }
}
