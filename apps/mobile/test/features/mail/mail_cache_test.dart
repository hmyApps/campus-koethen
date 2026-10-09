// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/data/mail_local_data_coordinator.dart';
import 'package:campus_koethen/features/mail/data/secure_mail_credential_store.dart';
import 'package:campus_koethen/features/mail/domain/mail_cache_store.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const FlutterSecureStorage _storage = FlutterSecureStorage();

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mail-cache-test-');
    Hive.init(directory.path);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  MailCacheManager manager() {
    final EncryptedBox box = EncryptedBox(
      boxName: MailCacheManager.secureBoxName,
      keyStorageKey: MailCacheManager.keyStorageKey,
      storage: _storage,
      hive: Hive,
      initializeHive: () async {},
    );
    return MailCacheManager(
      encryptedBox: box,
      hive: Hive,
      initializeHive: () async {},
    );
  }

  MailMessageDetail detail() => MailMessageDetail(
    id: '42',
    subject: 'Confidential subject',
    from: const MailAddress(email: 'alice@example.test', name: 'Alice'),
    to: const <MailAddress>[MailAddress(email: 'student@example.test')],
    date: DateTime.utc(2026, 8, 19),
    body: 'Confidential body',
    attachments: <MailAttachment>[
      MailAttachment(
        filename: 'secret.txt',
        mediaType: 'text/plain',
        bytes: Uint8List.fromList(utf8.encode('attachment-secret')),
      ),
    ],
  );

  test(
    'roundtrips every mail data class through encrypted v2 storage',
    () async {
      final MailCacheManager cache = manager();
      final MailCacheInitResult initialized = await cache.initialize(
        accountExists: true,
      );
      expect(initialized.mode, MailCacheInitMode.encrypted);

      const MailMessageHeader header = MailMessageHeader(
        id: '42',
        subject: 'Confidential subject',
        from: MailAddress(email: 'alice@example.test', name: 'Alice'),
        date: null,
        isSeen: false,
        hasAttachments: true,
      );
      await cache.saveHeaders(const <MailMessageHeader>[header]);
      await cache.saveMessage(detail());

      expect((await cache.readHeaders()).single.subject, header.subject);
      final MailMessageDetail restored = (await cache.readMessage('42'))!;
      expect(restored.body, 'Confidential body');
      expect(restored.attachments.single.bytes, isNotNull);
      expect(
        (await cache.knownAddresses()).map((entry) => entry.email),
        containsAll(<String>['alice@example.test', 'student@example.test']),
      );

      await Hive.close();
      final List<int> bytes = <int>[
        for (final FileSystemEntity entity in directory.listSync())
          if (entity is File) ...await entity.readAsBytes(),
      ];
      final String persisted = latin1.decode(bytes, allowInvalid: true);
      expect(persisted, isNot(contains('Confidential body')));
      expect(persisted, isNot(contains('alice@example.test')));
      expect(
        await _storage.read(key: MailCacheManager.keyStorageKey),
        isNotNull,
      );
    },
  );

  test(
    'deletes a populated plaintext v1 box without using its values',
    () async {
      final Box<String> legacy = await Hive.openBox<String>(
        MailCacheManager.legacyBoxName,
      );
      await legacy.put('headers', 'plaintext legacy secret');
      await legacy.close();

      final MailCacheManager cache = manager();
      expect(
        (await cache.initialize(accountExists: true)).mode,
        MailCacheInitMode.encrypted,
      );
      expect(await Hive.boxExists(MailCacheManager.legacyBoxName), isFalse);
      expect(await cache.readHeaders(), isEmpty);

      expect(
        (await cache.initialize(accountExists: true)).mode,
        MailCacheInitMode.encrypted,
      );
      expect(await Hive.boxExists(MailCacheManager.legacyBoxName), isFalse);
    },
  );

  test('signed-out startup creates neither a box nor a key', () async {
    final MailCacheManager cache = manager();
    await cache.initialize(accountExists: false);

    expect(await Hive.boxExists(MailCacheManager.secureBoxName), isFalse);
    expect(await _storage.read(key: MailCacheManager.keyStorageKey), isNull);
  });

  test('an invalid key discards old ciphertext before re-keying', () async {
    final MailCacheManager first = manager();
    await first.initialize(accountExists: true);
    await first.saveMessage(detail());
    await Hive.close();

    FlutterSecureStorage.setMockInitialValues(<String, String>{
      MailCacheManager.keyStorageKey: 'not-valid-base64',
    });
    Hive.init(directory.path);
    final MailCacheManager recovered = manager();
    expect((await recovered.activate()).mode, MailCacheInitMode.encrypted);
    expect(await recovered.readMessage('42'), isNull);
    final String encoded = (await _storage.read(
      key: MailCacheManager.keyStorageKey,
    ))!;
    expect(base64Decode(encoded), hasLength(32));
  });

  test(
    'unavailable secure storage never creates a plaintext fallback',
    () async {
      final EncryptedBox box = EncryptedBox(
        boxName: MailCacheManager.secureBoxName,
        keyStorageKey: MailCacheManager.keyStorageKey,
        storage: const _UnavailableStorage(),
        hive: Hive,
        initializeHive: () async {},
      );
      final MailCacheManager cache = MailCacheManager(
        encryptedBox: box,
        hive: Hive,
        initializeHive: () async {},
      );

      final MailCacheInitResult result = await cache.initialize(
        accountExists: true,
      );
      expect(result.mode, MailCacheInitMode.memoryOnly);
      expect(result.failure, MailCacheInitFailure.secureStorageUnavailable);
      expect(await Hive.boxExists(MailCacheManager.secureBoxName), isFalse);
    },
  );

  test(
    'startup finishes a wipe that was interrupted after its marker',
    () async {
      final MailCacheManager cache = manager();
      await cache.initialize(accountExists: true);
      await cache.saveMessage(detail());
      final SecureMailCredentialStore credentials = SecureMailCredentialStore(
        _storage,
      );
      await credentials.write(
        const MailCredentials(
          emailAddress: 'student@example.test',
          password: 'test-password',
        ),
      );
      final SecureMailWipeIntentStore intent = SecureMailWipeIntentStore(
        _storage,
      );
      await intent.markPending();

      final MailLocalDataCoordinator restarted = MailLocalDataCoordinator(
        credentials: credentials,
        cache: cache,
        wipeIntent: intent,
      );
      await restarted.initialize();

      expect(await credentials.read(), isNull);
      expect(await intent.isPending(), isFalse);
      expect(await cache.readMessage('42'), isNull);
      expect(await Hive.boxExists(MailCacheManager.secureBoxName), isFalse);
    },
  );

  test('wipe removes key and both box artifacts idempotently', () async {
    final MailCacheManager cache = manager();
    await cache.initialize(accountExists: true);
    await cache.saveMessage(detail());

    final MailWipeResult first = await cache.wipe();
    expect(first.isComplete, isTrue);
    expect(await Hive.boxExists(MailCacheManager.secureBoxName), isFalse);
    expect(await Hive.boxExists(MailCacheManager.legacyBoxName), isFalse);
    expect(await _storage.read(key: MailCacheManager.keyStorageKey), isNull);

    expect((await cache.wipe()).isComplete, isTrue);
  });

  group('local search', () {
    MailMessageDetail message({
      required String id,
      String subject = 'Semesterinfo',
      String body = 'Kein besonderer Inhalt.',
      List<MailAddress> to = const <MailAddress>[
        MailAddress(email: 'student@example.test'),
      ],
      DateTime? date,
    }) => MailMessageDetail(
      id: id,
      subject: subject,
      from: const MailAddress(email: 'alice@example.test', name: 'Alice'),
      to: to,
      date: date ?? DateTime.utc(2026, 8, int.parse(id)),
      body: body,
    );

    MailMessageHeader headerOf(MailMessageDetail m) => MailMessageHeader(
      id: m.id,
      subject: m.subject,
      from: m.from,
      date: m.date,
      isSeen: false,
      hasAttachments: false,
    );

    Future<MailCacheManager> seeded(List<MailMessageDetail> messages) async {
      final MailCacheManager cache = manager();
      final MailCacheInitResult initialized = await cache.initialize(
        accountExists: true,
      );
      expect(initialized.mode, MailCacheInitMode.encrypted);
      await cache.saveHeaders(messages.map(headerOf).toList());
      await cache.saveMessages(messages);
      return cache;
    }

    test('matches subject, body and recipients, newest first', () async {
      final MailCacheManager cache = await seeded(<MailMessageDetail>[
        message(id: '1', body: 'Die Rechnung liegt bei.'),
        message(id: '2', subject: 'Rechnungsstelle', body: 'Nichts weiter.'),
        message(
          id: '3',
          body: 'Nichts weiter.',
          to: const <MailAddress>[MailAddress(email: 'rechnung@example.test')],
        ),
        message(id: '4', body: 'Die Mensa bleibt geschlossen.'),
      ]);

      final List<MailMessageHeader> hits = await cache.searchHeaders(
        '  RECHNUNG ',
      );

      final Iterable<String> hitIds = hits.map((MailMessageHeader h) => h.id);
      const String reason = 'newest first, case- and whitespace-robust';
      expect(hitIds, <String>['3', '2', '1'], reason: reason);
    });

    test('a blank term matches nothing', () async {
      final MailCacheManager cache = await seeded(<MailMessageDetail>[
        message(id: '1'),
      ]);
      expect(await cache.searchHeaders('   '), isEmpty);
    });

    test('never searches attachment bytes', () async {
      final MailCacheManager cache = manager();
      await cache.initialize(accountExists: true);
      final MailMessageDetail withAttachment = MailMessageDetail(
        id: '7',
        subject: 'Anhang',
        from: const MailAddress(email: 'alice@example.test'),
        to: const <MailAddress>[MailAddress(email: 'student@example.test')],
        date: DateTime.utc(2026, 8, 7),
        body: 'Siehe Anhang.',
        attachments: <MailAttachment>[
          MailAttachment(
            filename: 'notiz.txt',
            mediaType: 'text/plain',
            bytes: Uint8List.fromList(utf8.encode('geheimwort')),
          ),
        ],
      );
      await cache.saveHeaders(<MailMessageHeader>[headerOf(withAttachment)]);
      await cache.saveMessage(withAttachment);

      expect(await cache.searchHeaders('geheimwort'), isEmpty);
      expect(
        (await cache.searchHeaders('Anhang')).single.id,
        '7',
        reason: 'the message itself is still found by its own text',
      );
    });

    test(
      'reconstructs a header for a message missing from the index',
      () async {
        final MailCacheManager cache = manager();
        await cache.initialize(accountExists: true);
        final MailMessageDetail orphan = message(
          id: '8',
          body: 'Die Rechnung liegt bei.',
        );
        // Body cached, header index empty — a partially written cache.
        await cache.saveMessage(orphan);

        final MailMessageHeader hit = (await cache.searchHeaders(
          'rechnung',
        )).single;
        expect(hit.id, '8');
        expect(hit.subject, orphan.subject);
        expect(hit.from.email, orphan.from.email);
      },
    );

    test('a wiped cache answers nothing to the next account', () async {
      final MailCacheManager cache = await seeded(<MailMessageDetail>[
        message(id: '1', body: 'Die Rechnung liegt bei.'),
      ]);
      expect(await cache.searchHeaders('rechnung'), isNotEmpty);

      await cache.wipe();

      expect(await cache.searchHeaders('rechnung'), isEmpty);
    });
  });

  group('batched message writes', () {
    MailMessageDetail message(String id, String sender) => MailMessageDetail(
      id: id,
      subject: 'Subject $id',
      from: MailAddress(email: sender),
      to: const <MailAddress>[MailAddress(email: 'student@example.test')],
      date: DateTime.utc(2026, 8, 19),
      body: 'Body $id',
      attachments: const <MailAttachment>[],
    );

    _CountingBox openBox() => _CountingBox(
      boxName: MailCacheManager.secureBoxName,
      keyStorageKey: MailCacheManager.keyStorageKey,
      storage: _storage,
      hive: Hive,
      initializeHive: () async {},
    );

    test('rewrites the address index once for the whole batch', () async {
      final _CountingBox box = openBox();
      expect((await box.openChecked()).isOpen, isTrue);
      final EncryptedMailCache cache = EncryptedMailCache(box);

      box.writtenKeys.clear();
      await cache.saveMessages(<MailMessageDetail>[
        message('1', 'a@example.test'),
        message('2', 'b@example.test'),
        message('3', 'c@example.test'),
      ]);

      // One write per message body, and exactly ONE for the shared address
      // index — not one per message, which is what made a full prefetch cost
      // the whole index over and over.
      expect(
        box.writtenKeys.where((String k) => k == 'addresses'),
        hasLength(1),
      );
      expect(
        box.writtenKeys.where((String k) => k.startsWith('msg.')),
        hasLength(3),
      );
      expect(
        box.batchWriteCalls,
        1,
        reason: 'all message bodies share one encrypted Hive operation',
      );
    });

    test(
      'indexes every address of the batch, exactly as single saves did',
      () async {
        final _CountingBox batched = openBox();
        expect((await batched.openChecked()).isOpen, isTrue);
        await EncryptedMailCache(batched).saveMessages(<MailMessageDetail>[
          message('1', 'a@example.test'),
          message('2', 'b@example.test'),
        ]);
        final List<String> fromBatch =
            (await EncryptedMailCache(
                batched,
              ).knownAddresses()).map((MailAddressEntry e) => e.email).toList()
              ..sort();
        await Hive.close();

        final _CountingBox oneByOne = openBox();
        expect((await oneByOne.openChecked()).isOpen, isTrue);
        final EncryptedMailCache cache = EncryptedMailCache(oneByOne);
        await cache.saveMessage(message('1', 'a@example.test'));
        await cache.saveMessage(message('2', 'b@example.test'));
        final List<String> fromSingles =
            (await cache.knownAddresses())
                .map((MailAddressEntry e) => e.email)
                .toList()
              ..sort();

        expect(fromBatch, <String>[
          'a@example.test',
          'b@example.test',
          'student@example.test',
        ]);
        expect(fromBatch, fromSingles);
      },
    );

    test('an empty batch touches nothing', () async {
      final _CountingBox box = openBox();
      expect((await box.openChecked()).isOpen, isTrue);
      box.writtenKeys.clear();

      await EncryptedMailCache(box).saveMessages(const <MailMessageDetail>[]);

      expect(box.writtenKeys, isEmpty);
    });

    test(
      'search reads the compact index without decrypting message bodies',
      () async {
        final _CountingBox box = openBox();
        expect((await box.openChecked()).isOpen, isTrue);
        final EncryptedMailCache cache = EncryptedMailCache(box);
        await cache.saveMessage(message('1', 'a@example.test'));
        box.readKeys.clear();

        expect(await cache.searchHeaders('body 1'), hasLength(1));

        expect(
          box.readKeys.where((String key) => key.startsWith('msg.')),
          isEmpty,
        );
      },
    );

    test(
      'body count and bytes stay inside the configured retention budget',
      () async {
        final _CountingBox box = openBox();
        expect((await box.openChecked()).isOpen, isTrue);
        final EncryptedMailCache cache = EncryptedMailCache(
          box,
          policy: const MailCachePolicy(
            maxBodies: 2,
            maxBodyBytes: 1024 * 1024,
          ),
        );

        await cache.saveMessages(<MailMessageDetail>[
          message('1', 'a@example.test'),
          message('2', 'b@example.test'),
          message('3', 'c@example.test'),
        ]);

        expect(await cache.cachedMessageIds(), <String>{'2', '3'});
        expect((await cache.stats()).bodyCount, 2);
      },
    );

    test('retainsBody predicts exactly what the age pruning keeps', () async {
      final _CountingBox box = openBox();
      expect((await box.openChecked()).isOpen, isTrue);
      final EncryptedMailCache cache = EncryptedMailCache(
        box,
        now: () => DateTime.utc(2026, 9, 1),
      );
      MailMessageDetail dated(String id, DateTime date) => MailMessageDetail(
        id: id,
        subject: 'Subject $id',
        from: const MailAddress(email: 'a@example.test'),
        to: const <MailAddress>[],
        date: date,
        body: 'Body $id',
      );
      final MailMessageDetail recent = dated('3', DateTime.utc(2026, 8, 30));
      final MailMessageDetail old = dated('1', DateTime.utc(2025, 1, 1));

      expect(cache.retainsBody(recent.date), isTrue);
      expect(cache.retainsBody(old.date), isFalse);
      expect(cache.retainsBody(null), isTrue);

      await cache.saveMessages(<MailMessageDetail>[recent, old]);
      expect(await cache.cachedMessageIds(), <String>{'3'});
    });

    test(
      'clearing offline bodies retains the lightweight header list',
      () async {
        final _CountingBox box = openBox();
        expect((await box.openChecked()).isOpen, isTrue);
        final EncryptedMailCache cache = EncryptedMailCache(box);
        final MailMessageDetail cached = message('1', 'a@example.test');
        await cache.saveHeaders(<MailMessageHeader>[
          MailMessageHeader(
            id: cached.id,
            subject: cached.subject,
            from: cached.from,
            date: cached.date,
            isSeen: false,
            hasAttachments: false,
          ),
        ]);
        await cache.saveMessage(cached);

        await cache.clearCachedBodies();

        expect(await cache.cachedMessageIds(), isEmpty);
        expect(await cache.readHeaders(), hasLength(1));
      },
    );
  });

  group('message removal keeps the derived indexes consistent (C-07)', () {
    MailMessageDetail message(String id, String body) => MailMessageDetail(
      id: id,
      subject: 'Subject $id',
      from: const MailAddress(email: 'alice@example.test'),
      to: const <MailAddress>[MailAddress(email: 'student@example.test')],
      date: DateTime.utc(2026, 8, 19),
      body: body,
    );

    MailMessageHeader headerOf(MailMessageDetail m) => MailMessageHeader(
      id: m.id,
      subject: m.subject,
      from: m.from,
      date: m.date,
      isSeen: false,
      hasAttachments: false,
    );

    Future<EncryptedBox> openBox() async {
      final EncryptedBox box = EncryptedBox(
        boxName: MailCacheManager.secureBoxName,
        keyStorageKey: MailCacheManager.keyStorageKey,
        storage: _storage,
        hive: Hive,
        initializeHive: () async {},
      );
      expect((await box.openChecked()).isOpen, isTrue);
      return box;
    }

    test(
      'a removed message leaves neither search hits nor statistics',
      () async {
        final EncryptedBox box = await openBox();
        final EncryptedMailCache cache = EncryptedMailCache(
          box,
          now: () => DateTime.utc(2026, 9, 1),
        );
        final MailMessageDetail removed = message('1', 'Geheimes Protokoll');
        final MailMessageDetail kept = message('2', 'Offene Sprechstunde');
        await cache.saveHeaders(<MailMessageHeader>[
          headerOf(kept),
          headerOf(removed),
        ]);
        await cache.saveMessages(<MailMessageDetail>[removed, kept]);
        expect(await cache.searchHeaders('protokoll'), hasLength(1));

        await cache.removeMessage('1');

        expect(await cache.searchHeaders('protokoll'), isEmpty);
        expect(await cache.searchHeaders('sprechstunde'), hasLength(1));
        expect((await cache.stats()).bodyCount, 1);
        final Map<String, dynamic> search =
            jsonDecode((await box.read('search.v1'))!) as Map<String, dynamic>;
        final Map<String, dynamic> metadata =
            jsonDecode((await box.read('metadata.v1'))!)
                as Map<String, dynamic>;
        expect(search.keys, <String>['2']);
        expect(metadata.keys, <String>['2']);
      },
    );

    test('orphaned index entries without a body are discarded', () async {
      final EncryptedBox box = await openBox();
      final EncryptedMailCache cache = EncryptedMailCache(
        box,
        now: () => DateTime.utc(2026, 9, 1),
      );
      await cache.saveMessages(<MailMessageDetail>[
        message('1', 'Geheimes Protokoll'),
        message('2', 'Offene Sprechstunde'),
      ]);
      // An index written by an older build, whose body is already gone.
      await box.delete('msg.1');

      expect(await cache.searchHeaders('protokoll'), isEmpty);
      expect((await cache.stats()).bodyCount, 1);
      final Map<String, dynamic> search =
          jsonDecode((await box.read('search.v1'))!) as Map<String, dynamic>;
      expect(search.keys, <String>['2']);
    });
  });
}

/// Records which keys were written so the batching guarantee is observable.
class _CountingBox extends EncryptedBox {
  _CountingBox({
    required super.boxName,
    required super.keyStorageKey,
    super.storage,
    super.hive,
    super.initializeHive,
  });

  final List<String> writtenKeys = <String>[];
  final List<String> readKeys = <String>[];
  int batchWriteCalls = 0;

  @override
  Future<String?> read(String key) {
    readKeys.add(key);
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) {
    writtenKeys.add(key);
    return super.write(key, value);
  }

  @override
  Future<void> writeAll(Map<String, String> entries) {
    batchWriteCalls++;
    writtenKeys.addAll(entries.keys);
    return super.writeAll(entries);
  }
}

class _UnavailableStorage extends FlutterSecureStorage {
  const _UnavailableStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('secure storage unavailable');
}
