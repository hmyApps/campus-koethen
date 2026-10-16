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
    'keeps user-saved files of any type apart from the grade slots',
    () async {
      final _MemoryBox box = _MemoryBox();
      final EncryptedDocumentWalletStore store = EncryptedDocumentWalletStore(
        box,
      );
      const String id = '0123456789abcdef0123456789abcdef';
      await store.save(
        WalletDocument.custom(
          document: AppDocument(
            filename: '../Skript.docx',
            mediaType: 'application/vnd.openxmlformats',
            bytes: Uint8List.fromList(<int>[9, 8, 7]),
          ),
          savedAt: DateTime.utc(2026, 10, 16),
          id: id,
        ),
      );
      await store.save(
        WalletDocument(
          kind: WalletDocumentKind.transcript,
          filename: 'L.pdf',
          mediaType: 'application/pdf',
          bytes: pdf('t'),
          savedAt: DateTime.utc(2026, 10, 15),
        ),
      );

      final List<WalletDocument> all = await store.readAll();
      expect(all, hasLength(2));
      final WalletDocument custom = all.firstWhere(
        (WalletDocument d) => d.customId == id,
      );
      expect(custom.filename, 'Skript.docx');
      expect(custom.bytes, <int>[9, 8, 7]);

      await store.clearGradeLinked();
      expect((await store.readAll()).single.customId, id);

      await store.deleteCustom(id);
      expect(await store.readAll(), isEmpty);
    },
  );

  test('clear removes user-saved files too and a bad id is refused', () async {
    final _MemoryBox box = _MemoryBox();
    final EncryptedDocumentWalletStore store = EncryptedDocumentWalletStore(
      box,
    );
    final WalletDocument ok = WalletDocument.custom(
      document: AppDocument(
        filename: 'a.txt',
        mediaType: 'text/plain',
        bytes: Uint8List.fromList(<int>[1]),
      ),
      savedAt: DateTime.utc(2026),
      id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await store.save(ok);
    await store.clear();
    expect(box.values, isEmpty);

    expect(
      () => store.save(
        WalletDocument.custom(
          document: AppDocument(
            filename: 'a.txt',
            mediaType: 'text/plain',
            bytes: Uint8List.fromList(<int>[1]),
          ),
          savedAt: DateTime.utc(2026),
          id: '../evil',
        ),
      ),
      throwsA(isA<DocumentWalletFailure>()),
    );
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

  test('an unreadable box is a storage failure, not an empty wallet', () async {
    final _MemoryBox box = _MemoryBox();
    final EncryptedDocumentWalletStore store = EncryptedDocumentWalletStore(
      box,
    );
    await store.save(
      WalletDocument(
        kind: WalletDocumentKind.transcript,
        filename: 'Leistungsuebersicht.pdf',
        mediaType: 'application/pdf',
        bytes: pdf('grades'),
        savedAt: DateTime.utc(2026),
      ),
    );
    box.unavailable = true;

    await expectLater(
      store.readAll(),
      throwsA(
        isA<DocumentWalletFailure>().having(
          (DocumentWalletFailure f) => f.kind,
          'kind',
          DocumentWalletFailureKind.storageUnavailable,
        ),
      ),
    );
    // A deletion that cannot be checked is not confirmed either.
    await expectLater(
      store.delete(WalletDocumentKind.transcript),
      throwsA(isA<DocumentWalletFailure>()),
    );
  });
}

class _MemoryBox extends EncryptedBox {
  _MemoryBox() : super(boxName: 'unused', keyStorageKey: 'unused');

  final Map<String, String> values = <String, String>{};

  /// A box that cannot be opened: plain reads fold that into "absent",
  /// checked reads report it, deletes do nothing.
  bool unavailable = false;

  @override
  Future<String?> read(String key) async => unavailable ? null : values[key];

  @override
  Future<String?> readChecked(String key) async {
    if (unavailable) throw const EncryptedBoxUnavailable();
    return values[key];
  }

  @override
  Future<bool> writeChecked(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<Iterable<String>> keys() async =>
      unavailable ? const <String>[] : values.keys.toList();

  @override
  Future<void> delete(String key) async {
    if (!unavailable) values.remove(key);
  }

  @override
  Future<EncryptedBoxWipeResult> wipeChecked() async {
    values.clear();
    return const EncryptedBoxWipeResult(keyAbsent: true, boxAbsent: true);
  }
}
