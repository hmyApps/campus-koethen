// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Where drafts, cases and a student card actually end up on disk.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/features/requests/data/encrypted_attachment_store.dart';
import 'package:campus_koethen/features/requests/data/encrypted_request_store.dart';
import 'package:campus_koethen/features/requests/domain/request_drafts.dart';
import 'package:campus_koethen/features/requests/domain/submitted_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_gremio.dart';

final DateTime _now = DateTime(2026, 8, 6, 12);

/// An [EncryptedBox] stand-in that records what it was given.
///
/// The real box needs a keychain and a file system; what these tests are about
/// is the *protocol* around it — read back before reporting success, migrate
/// before clearing, never write plaintext anywhere else.
class RecordingBox implements EncryptedBox {
  RecordingBox({this.failWrites = false, this.failOnWriteNumber});

  final Map<String, String> entries = <String, String>{};
  bool failWrites;
  final int? failOnWriteNumber;
  int _writes = 0;

  /// Simulates a box that cannot be opened (keystore locked, I/O error):
  /// plain reads fold that into "absent", checked reads report it.
  bool unavailable = false;

  @override
  String get boxName => 'recording';

  @override
  String get keyStorageKey => 'recording-key';

  @override
  bool get discardUnreadable => false;

  @override
  Future<String?> read(String key) async => unavailable ? null : entries[key];

  @override
  Future<String?> readChecked(String key) async {
    if (unavailable) throw const EncryptedBoxUnavailable();
    return entries[key];
  }

  @override
  Future<EncryptedBoxWipeResult> wipeAndSeal() => wipeChecked();

  @override
  Future<void> write(String key, String value) async {
    _writes++;
    if (failWrites || _writes == failOnWriteNumber) {
      return; // silently drops, exactly like a full disk
    }
    entries[key] = value;
  }

  @override
  Future<bool> writeChecked(String key, String value) async {
    await write(key, value);
    return entries[key] == value;
  }

  @override
  Future<void> writeAll(Map<String, String> values) async {
    if (failWrites) return;
    entries.addAll(values);
  }

  @override
  Future<void> delete(String key) async => entries.remove(key);

  @override
  Future<Iterable<String>> keys() async => entries.keys;

  @override
  Future<void> wipe() async => entries.clear();

  @override
  Future<EncryptedBoxOpenResult> openChecked() async =>
      const EncryptedBoxOpenResult.opened();

  @override
  Future<EncryptedBoxWipeResult> wipeChecked() async {
    entries.clear();
    return const EncryptedBoxWipeResult(keyAbsent: true, boxAbsent: true);
  }
}

/// A legacy box whose contents the test controls.
class FakeLegacyBox implements LegacyDraftBox {
  FakeLegacyBox(this.contents);

  String? contents;
  bool cleared = false;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> clear() async {
    cleared = true;
    contents = null;
  }
}

FeedbackDraft _draft(String id) => FeedbackDraft(
  id: id,
  createdAt: _now,
  updatedAt: _now,
  idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
  areaId: 1,
  feedback: 'Ein Hinweis.',
);

SubmittedCase _case(String id) => SubmittedCase(
  id: id,
  kind: RequestKind.feedback,
  submittedAt: _now,
  statusUrl: kFakeStatusUrl,
  receiptPdfUrl: kFakeReceiptUrl,
);

void main() {
  group('the encrypted request store', () {
    test('keeps drafts and cases in the encrypted box only', () async {
      final RecordingBox box = RecordingBox();
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: box,
        legacy: FakeLegacyBox(null),
      );

      await store.writeDrafts(<RequestDraft>[_draft('d1')]);
      await store.writeCases(<SubmittedCase>[_case('c1')]);

      expect(await store.readDrafts(), hasLength(1));
      expect((await store.readCases()).single.statusUrl, kFakeStatusUrl);
      // Nothing lands anywhere else — these two keys are the whole footprint.
      expect(box.entries.keys.toSet(), <String>{'drafts', 'cases'});
    });

    test('reports a failed write instead of swallowing it', () async {
      // The caller is about to delete a draft; a silent failure would lose the
      // only link back to a case that already exists.
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: RecordingBox(failWrites: true),
        legacy: FakeLegacyBox(null),
      );

      expect(
        () => store.writeCases(<SubmittedCase>[_case('c1')]),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      expect(
        () => store.writeDrafts(<RequestDraft>[_draft('d1')]),
        throwsA(isA<RequestStoreUnavailable>()),
      );
    });

    test(
      'rejects a failed write when an older value is still present',
      () async {
        final RecordingBox box = RecordingBox();
        box.entries['cases'] = jsonEncode(<Map<String, dynamic>>[
          _case('old-case').toJson(),
        ]);
        box.failWrites = true;
        final EncryptedRequestStore store = EncryptedRequestStore(
          box: box,
          legacy: FakeLegacyBox(null),
        );

        expect(
          () => store.writeCases(<SubmittedCase>[_case('new-case')]),
          throwsA(isA<RequestStoreUnavailable>()),
        );
        expect(
          (jsonDecode(box.entries['cases']!) as List<Object?>).single,
          containsPair('id', 'old-case'),
        );
      },
    );

    // E-03: "could not read" used to come back as "nothing stored", and the
    // next write replaced every status link on the device with a list of one.
    test('reports an unreadable box instead of an empty list', () async {
      final RecordingBox box = RecordingBox();
      box.entries['cases'] = jsonEncode(<Map<String, dynamic>>[
        _case('old-case').toJson(),
      ]);
      box.unavailable = true;
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: box,
        legacy: FakeLegacyBox(null),
      );

      await expectLater(
        store.readCases(),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      await expectLater(
        store.readDrafts(),
        throwsA(isA<RequestStoreUnavailable>()),
      );
    });

    test('never writes over a stored list it cannot decode', () async {
      final RecordingBox box = RecordingBox();
      box.entries['cases'] = 'not json at all';
      box.entries['drafts'] = '{"not":"a list"}';
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: box,
        legacy: FakeLegacyBox(null),
      );

      await expectLater(
        store.readCases(),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      await expectLater(
        store.writeCases(<SubmittedCase>[_case('new-case')]),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      await expectLater(
        store.writeDrafts(<RequestDraft>[_draft('d1')]),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      // The raw bytes are left exactly as they were, for a later build or a
      // deliberate wipe to deal with.
      expect(box.entries['cases'], 'not json at all');
      expect(box.entries['drafts'], '{"not":"a list"}');
    });

    test('refuses to write while the box cannot be read', () async {
      final RecordingBox box = RecordingBox();
      box.entries['cases'] = jsonEncode(<Map<String, dynamic>>[
        _case('old-case').toJson(),
      ]);
      box.unavailable = true;
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: box,
        legacy: FakeLegacyBox(null),
      );

      await expectLater(
        store.writeCases(<SubmittedCase>[_case('new-case')]),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      box.unavailable = false;
      expect((await store.readCases()).single.id, 'old-case');
    });

    test('carries entries it cannot parse through every write', () async {
      // An entry this build does not understand — a kind from a newer
      // version, say — still holds a status link. Dropping it on the next
      // write would lose that case for good.
      final Map<String, dynamic> unknown = <String, dynamic>{
        ..._case('future-case').toJson(),
        'kind': 'kind-from-a-newer-build',
      };
      final RecordingBox box = RecordingBox();
      box.entries['cases'] = jsonEncode(<Object?>[
        _case('old-case').toJson(),
        unknown,
      ]);
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: box,
        legacy: FakeLegacyBox(null),
      );

      final List<SubmittedCase> visible = await store.readCases();
      expect(visible.map((SubmittedCase c) => c.id), <String>['old-case']);
      await store.writeCases(<SubmittedCase>[...visible, _case('new-case')]);

      final List<Object?> raw = jsonDecode(box.entries['cases']!) as List;
      expect(raw, hasLength(3));
      expect(raw, contains(equals(unknown)));
    });

    test('a draft it cannot parse survives a write as well', () async {
      final Map<String, dynamic> unknown = <String, dynamic>{
        'id': 'draft-future',
        'kind': 'kind-from-a-newer-build',
      };
      final RecordingBox box = RecordingBox();
      box.entries['drafts'] = jsonEncode(<Object?>[unknown]);
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: box,
        legacy: FakeLegacyBox(null),
      );

      expect(await store.readDrafts(), isEmpty);
      await store.writeDrafts(<RequestDraft>[_draft('d1')]);

      final List<Object?> raw = jsonDecode(box.entries['drafts']!) as List;
      expect(raw, hasLength(2));
      expect(raw, contains(equals(unknown)));
    });
  });

  group('migrating away from the plaintext box', () {
    test('moves old drafts across and only then clears the old box', () async {
      final RecordingBox box = RecordingBox();
      final FakeLegacyBox legacy = FakeLegacyBox(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'old-1',
            'kind': 'feedback',
            'idempotencyKey': '550e8400-e29b-41d4-a716-446655440000',
            'description': 'Alter Text',
          },
        ]),
      );
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: box,
        legacy: legacy,
      );

      final List<RequestDraft> drafts = await store.readDrafts();

      expect(drafts, hasLength(1));
      expect((drafts.single as FeedbackDraft).feedback, 'Alter Text');
      expect(legacy.cleared, isTrue, reason: 'the plaintext copy must go');
      expect(box.entries.containsKey('drafts'), isTrue);
    });

    test('leaves the old box alone when the encrypted write fails', () async {
      // A duplicate is recoverable; a lost draft is not.
      final FakeLegacyBox legacy = FakeLegacyBox(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'old-1',
            'kind': 'feedback',
            'idempotencyKey': '550e8400-e29b-41d4-a716-446655440000',
            'description': 'Alter Text',
          },
        ]),
      );
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: RecordingBox(failWrites: true),
        legacy: legacy,
      );

      await store.readDrafts();

      expect(legacy.cleared, isFalse);
    });

    test('does not duplicate a draft that was already migrated', () async {
      final RecordingBox box = RecordingBox();
      box.entries['drafts'] = jsonEncode(<Map<String, dynamic>>[
        _draft('old-1').toJson(),
      ]);
      final EncryptedRequestStore store = EncryptedRequestStore(
        box: box,
        legacy: FakeLegacyBox(
          jsonEncode(<Map<String, dynamic>>[_draft('old-1').toJson()]),
        ),
      );

      expect(await store.readDrafts(), hasLength(1));
    });
  });

  group('the encrypted attachment store', () {
    test('round-trips bytes without writing them anywhere else', () async {
      final RecordingBox box = RecordingBox();
      final EncryptedAttachmentStore store = EncryptedAttachmentStore(box: box);
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      final RequestAttachment? stored = await store.put('ausweis.pdf', bytes);

      expect(stored, isNotNull);
      expect(stored!.fileName, 'ausweis.pdf');
      expect(stored.sizeBytes, 4);
      expect(await store.read(stored), bytes);
      // The identifier is a store key, never a file-system path a crash could
      // leave behind in the clear.
      expect(stored.path, startsWith('attachment:'));
      expect(box.entries.keys, contains(stored.path));
      expect(
        box.entries.length,
        2,
        reason: 'metadata plus one encrypted chunk',
      );
    });

    test('stores a large attachment in bounded encrypted chunks', () async {
      final RecordingBox box = RecordingBox();
      final EncryptedAttachmentStore store = EncryptedAttachmentStore(box: box);
      final Uint8List bytes = Uint8List(
        EncryptedAttachmentStore.chunkBytes * 2 + 17,
      );

      final RequestAttachment stored = (await store.put('large.pdf', bytes))!;

      expect(box.entries.length, 4, reason: 'metadata plus three chunks');
      expect(box.entries.containsKey(stored.path), isTrue);
      expect(await store.read(stored), bytes);
    });

    test('reports a failed write rather than a dangling reference', () async {
      final EncryptedAttachmentStore store = EncryptedAttachmentStore(
        box: RecordingBox(failWrites: true),
      );

      expect(
        await store.put('ausweis.pdf', Uint8List.fromList(<int>[1])),
        isNull,
      );
    });

    test('removes chunks when committing their metadata fails', () async {
      final RecordingBox box = RecordingBox(failOnWriteNumber: 2);
      final EncryptedAttachmentStore store = EncryptedAttachmentStore(box: box);

      expect(
        await store.put('ausweis.pdf', Uint8List.fromList(<int>[1, 2, 3])),
        isNull,
      );
      expect(box.entries, isEmpty);
    });

    test('a missing entry reads as null, not as a crash', () async {
      final EncryptedAttachmentStore store = EncryptedAttachmentStore(
        box: RecordingBox(),
      );

      expect(
        await store.read(
          const RequestAttachment(fileName: 'x.pdf', path: 'attachment:gone'),
        ),
        isNull,
      );
    });

    test('deleting removes the bytes', () async {
      final RecordingBox box = RecordingBox();
      final EncryptedAttachmentStore store = EncryptedAttachmentStore(box: box);
      final RequestAttachment stored = (await store.put(
        'ausweis.pdf',
        Uint8List.fromList(<int>[1]),
      ))!;

      await store.deleteAll(<RequestAttachment>[stored]);

      expect(box.entries, isEmpty);
      expect(await store.read(stored), isNull);
    });

    test('an attachment never names its own path in a log line', () async {
      final RequestAttachment stored = (await EncryptedAttachmentStore(
        box: RecordingBox(),
      ).put('ausweis.pdf', Uint8List.fromList(<int>[1])))!;

      expect(stored.toString(), contains('ausweis.pdf'));
      expect(stored.toString(), isNot(contains(stored.path)));
    });
  });

  test('a stored case never names its links in a log line', () {
    expect(_case('c1').toString(), isNot(contains('testtoken')));
  });
}
