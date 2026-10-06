// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/features/document_wallet/data/encrypted_document_wallet_store.dart';
import 'package:campus_koethen/features/document_wallet/domain/wallet_document.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pdf(String marker) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$marker'));

void main() {
  test('stores PDFs encrypted by slot and replaces an older version', () async {
    final _MemoryBox box = _MemoryBox();
    final EncryptedDocumentWalletStore store = EncryptedDocumentWalletStore(
      box,
    );

    await store.save(
      WalletDocument.fromAppDocument(
        kind: WalletDocumentKind.enrollmentCertificate,
        document: AppDocument(
          filename: '../Immatrikulation.pdf',
          mediaType: 'application/pdf',
          bytes: pdf('first'),
        ),
        savedAt: DateTime.utc(2026, 10, 6, 10),
      ),
    );
    await store.save(
      WalletDocument.fromAppDocument(
        kind: WalletDocumentKind.enrollmentCertificate,
        document: AppDocument(
          filename: 'Immatrikulation-neu.pdf',
          mediaType: 'application/pdf',
          bytes: pdf('second'),
        ),
        savedAt: DateTime.utc(2026, 10, 6, 11),
      ),
    );

    final List<WalletDocument> documents = await store.readAll();
    expect(documents, hasLength(1));
    expect(documents.single.filename, 'Immatrikulation-neu.pdf');
    expect(utf8.decode(documents.single.bytes), contains('second'));
    expect(box.values.values.single, isNot(contains('../')));
  });

  test(
    'rejects non-PDF content and oversized documents before writing',
    () async {
      final _MemoryBox box = _MemoryBox();
      final EncryptedDocumentWalletStore store = EncryptedDocumentWalletStore(
        box,
      );

      expect(
        () => store.save(
          WalletDocument(
            kind: WalletDocumentKind.transcript,
            filename: 'fake.pdf',
            mediaType: 'application/pdf',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            savedAt: DateTime.utc(2026),
          ),
        ),
        throwsA(isA<DocumentWalletFailure>()),
      );
      expect(box.values, isEmpty);
    },
  );

  test(
    'malformed ciphertext payload is ignored and verified deletion works',
    () async {
      final _MemoryBox box = _MemoryBox()
        ..values['document.transcript'] = '{broken';
      final EncryptedDocumentWalletStore store = EncryptedDocumentWalletStore(
        box,
      );

      expect(await store.readAll(), isEmpty);
      await store.save(
        WalletDocument(
          kind: WalletDocumentKind.transcript,
          filename: 'Leistungsuebersicht.pdf',
          mediaType: 'application/pdf',
          bytes: pdf('grades'),
          savedAt: DateTime.utc(2026),
        ),
      );
      await store.delete(WalletDocumentKind.transcript);
      expect(await store.readAll(), isEmpty);
    },
  );
}

class _MemoryBox extends EncryptedBox {
  _MemoryBox() : super(boxName: 'unused', keyStorageKey: 'unused');

  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> writeChecked(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<EncryptedBoxWipeResult> wipeChecked() async {
    values.clear();
    return const EncryptedBoxWipeResult(keyAbsent: true, boxAbsent: true);
  }
}
