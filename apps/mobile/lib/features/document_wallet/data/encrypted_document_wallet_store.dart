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

  static const String _customPrefix = 'document.custom.';

  static String _key(WalletDocumentKind kind) =>
      'document.${kind.storageValue}';

  static String _customKey(String id) => '$_customPrefix$id';

  /// Ids come from this app (random hex); anything else never reaches a key.
  static final RegExp _customId = RegExp(r'^[0-9a-f]{16,64}$');

  @override
  Future<List<WalletDocument>> readAll() async {
    final List<WalletDocument> documents = <WalletDocument>[];
    for (final WalletDocumentKind kind in WalletDocumentKind.values) {
      if (kind == WalletDocumentKind.custom) continue;
      // Checked: a box that cannot be opened is a storage failure the screen
      // reports, not an empty wallet.
      final String? raw = await _readChecked(_key(kind));
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
    for (final String key in await _box.keys()) {
      if (!key.startsWith(_customPrefix)) continue;
      final String id = key.substring(_customPrefix.length);
      if (!_customId.hasMatch(id)) continue;
      final String? raw = await _readChecked(key);
      if (raw == null) continue;
      try {
        final WalletDocument? document = _decode(jsonDecode(raw));
        if (document != null && document.customId == id) {
          documents.add(document);
        }
      } catch (_) {
        // One corrupt file must not hide the others.
      }
    }
    documents.sort(
      (WalletDocument a, WalletDocument b) => b.savedAt.compareTo(a.savedAt),
    );
    return List<WalletDocument>.unmodifiable(documents);
  }

  @override
  Future<void> save(WalletDocument document) async {
    final bool custom = document.kind == WalletDocumentKind.custom;
    final String? customId = document.customId;
    if (custom
        ? !_isValidCustom(document) ||
              customId == null ||
              !_customId.hasMatch(customId)
        : !_isValidPdf(document)) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.invalidDocument,
      );
    }
    final String payload = jsonEncode(<String, Object>{
      'kind': document.kind.storageValue,
      if (customId != null) 'id': customId,
      'filename': document.filename,
      'mediaType': custom ? document.mediaType : 'application/pdf',
      'savedAt': document.savedAt.toUtc().toIso8601String(),
      'bytes': base64Encode(document.bytes),
    });
    final String key = customId != null
        ? _customKey(customId)
        : _key(document.kind);
    if (!await _box.writeChecked(key, payload)) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.storageUnavailable,
      );
    }
  }

  @override
  Future<void> delete(WalletDocumentKind kind) => _deleteKey(_key(kind));

  @override
  Future<void> deleteCustom(String id) async {
    if (!_customId.hasMatch(id)) return;
    await _deleteKey(_customKey(id));
  }

  @override
  Future<void> clearGradeLinked() async {
    for (final WalletDocumentKind kind in WalletDocumentKind.values) {
      if (kind == WalletDocumentKind.custom) continue;
      await _deleteKey(_key(kind));
    }
  }

  Future<void> _deleteKey(String key) async {
    await _box.delete(key);
    // Confirmed only by a read that can tell "gone" from "unreadable".
    if (await _readChecked(key) != null) {
      throw const DocumentWalletFailure(
        DocumentWalletFailureKind.storageUnavailable,
      );
    }
  }

  Future<String?> _readChecked(String key) async {
    try {
      return await _box.readChecked(key);
    } on EncryptedBoxUnavailable {
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
    final String? customId = map['id'] as String?;
    final String? filename = map['filename'] as String?;
    final String? savedAtRaw = map['savedAt'] as String?;
    final String? encodedBytes = map['bytes'] as String?;
    final DateTime? savedAt = savedAtRaw == null
        ? null
        : DateTime.tryParse(savedAtRaw);
    if (kind == null ||
        (kind == WalletDocumentKind.custom) != (customId != null) ||
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
      mediaType: kind == WalletDocumentKind.custom
          ? (map['mediaType'] as String? ?? 'application/octet-stream')
          : 'application/pdf',
      bytes: bytes,
      savedAt: savedAt,
      customId: customId,
    );
    return (kind == WalletDocumentKind.custom
            ? _isValidCustom(document)
            : _isValidPdf(document))
        ? document
        : null;
  }

  static bool _isValidCustom(WalletDocument document) =>
      document.bytes.isNotEmpty &&
      document.bytes.length <= kMaxDocumentWalletBytes;

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
