// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';
import 'dart:typed_data';

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const FlutterSecureStorage _storage = FlutterSecureStorage();

const String _boxName = 'checked-write-test';
const String _keyName = 'checked-write-test-key';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('encrypted-box-test-');
    Hive.init(directory.path);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  EncryptedBox box({
    FlutterSecureStorage storage = _storage,
    HiveInterface? hive,
    bool discardUnreadable = true,
  }) => EncryptedBox(
    boxName: _boxName,
    keyStorageKey: _keyName,
    storage: storage,
    hive: hive ?? Hive,
    initializeHive: () async {},
    discardUnreadable: discardUnreadable,
  );

  test('checked writes replace and confirm the exact payload', () async {
    final EncryptedBox store = box();

    expect(await store.writeChecked('case', 'old-payload'), isTrue);
    expect(await store.writeChecked('case', 'new-payload'), isTrue);
    expect(await store.read('case'), 'new-payload');
  });

  test('checked writes report unavailable secure storage', () async {
    expect(
      await box(
        storage: const _UnavailableStorage(),
      ).writeChecked('case', 'payload'),
      isFalse,
    );
  });

  group('parallel first opens (G-02)', () {
    test('two concurrent reads on a fresh box agree on one key', () async {
      // Two providers reading in the same frame: each used to generate its
      // own key. Hive kept the box opened with the first one, the keystore
      // ended up with the second — and the next start truncated the box.
      final _CountingStorage storage = _CountingStorage();
      final EncryptedBox first = box(storage: storage);

      await Future.wait(<Future<String?>>[
        first.read('drafts'),
        first.read('cases'),
      ]);
      expect(await first.writeChecked('cases', 'status-links'), isTrue);
      expect(storage.keyWrites, 1, reason: 'exactly one key may be created');

      // Next app start: same keystore, fresh instance.
      await Hive.close();
      expect(await box(storage: storage).read('cases'), 'status-links');
    });

    test('concurrent checked opens share one attempt', () async {
      final _CountingStorage storage = _CountingStorage();
      final EncryptedBox store = box(storage: storage);

      final List<EncryptedBoxOpenResult> results = await Future.wait(
        <Future<EncryptedBoxOpenResult>>[
          store.openChecked(),
          store.openChecked(),
          store.openChecked(),
        ],
      );

      expect(results.every((EncryptedBoxOpenResult r) => r.isOpen), isTrue);
      expect(storage.keyWrites, 1);
    });
  });

  group('checked reads (E-03)', () {
    test('an absent entry reads as null', () async {
      expect(await box().readChecked('cases'), isNull);
    });

    test('an unavailable keystore is reported, not folded into absent', () {
      expect(
        box(storage: const _UnavailableStorage()).readChecked('cases'),
        throwsA(isA<EncryptedBoxUnavailable>()),
      );
    });

    test('user data is never discarded when its box fails to open', () async {
      // A cache may be thrown away and rebuilt. Status links cannot: they are
      // the only access to a submitted case.
      final _CountingStorage storage = _CountingStorage();
      expect(
        await box(
          storage: storage,
          discardUnreadable: false,
        ).writeChecked('cases', 'status-links'),
        isTrue,
      );
      await Hive.close();

      final EncryptedBox failing = box(
        storage: storage,
        hive: _FailingOpenHive(Hive, failures: 2),
        discardUnreadable: false,
      );
      await expectLater(
        failing.readChecked('cases'),
        throwsA(isA<EncryptedBoxUnavailable>()),
      );
      expect(await Hive.boxExists(_boxName), isTrue);

      expect(
        await box(storage: storage, discardUnreadable: false).read('cases'),
        'status-links',
      );
    });
  });

  group('sealing after a wipe (C-13)', () {
    test(
      'a sealed box is not recreated by an implicit read or write',
      () async {
        final _CountingStorage storage = _CountingStorage();
        final EncryptedBox store = box(storage: storage);
        expect(await store.writeChecked('k', 'v'), isTrue);

        final EncryptedBoxWipeResult wiped = await store.wipeAndSeal();
        expect(wiped.isComplete, isTrue);

        expect(await store.read('k'), isNull);
        await store.write('k', 'late write from a read path');
        expect(await store.writeChecked('k', 'again'), isFalse);
        expect(await Hive.boxExists(_boxName), isFalse);
        expect(storage.values.containsKey(_keyName), isFalse);

        // Only an explicit open lifts the seal.
        expect((await store.openChecked()).isOpen, isTrue);
        expect(await store.writeChecked('k', 'fresh'), isTrue);
        expect(await store.read('k'), 'fresh');
      },
    );

    test('a read racing the wipe leaves nothing behind', () async {
      final _CountingStorage storage = _CountingStorage();
      final EncryptedBox store = box(storage: storage);

      final Future<String?> racing = store.read('k');
      final EncryptedBoxWipeResult wiped = await store.wipeAndSeal();
      await racing;
      await store.write('k', 'v');

      expect(wiped.isComplete, isTrue);
      expect(await Hive.boxExists(_boxName), isFalse);
      expect(storage.values.containsKey(_keyName), isFalse);
    });

    test('a plain wipe still reopens on demand for the other stores', () async {
      final EncryptedBox store = box();
      expect(await store.writeChecked('k', 'v'), isTrue);

      expect((await store.wipeChecked()).isComplete, isTrue);

      expect(await store.read('k'), isNull);
      expect(await store.writeChecked('k', 'again'), isTrue);
    });
  });
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

/// In-memory keystore with a real asynchronous gap on every call, so
/// concurrent callers genuinely interleave.
class _CountingStorage extends FlutterSecureStorage {
  _CountingStorage();

  final Map<String, String> values = <String, String>{};
  int keyWrites = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await Future<void>.delayed(Duration.zero);
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await Future<void>.delayed(Duration.zero);
    keyWrites++;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await Future<void>.delayed(Duration.zero);
    values.remove(key);
  }
}

/// Real Hive, except that the first opens throw — the shape of a transient
/// file-system error.
class _FailingOpenHive implements HiveInterface {
  _FailingOpenHive(this._inner, {required int failures}) : _left = failures;

  final HiveInterface _inner;
  int _left;

  @override
  Future<Box<E>> openBox<E>(
    String name, {
    HiveCipher? encryptionCipher,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
    String? path,
    Uint8List? bytes,
    String? collection,
    List<int>? encryptionKey,
  }) async {
    if (_left > 0) {
      _left--;
      throw const FileSystemException('transient');
    }
    return _inner.openBox<E>(name, encryptionCipher: encryptionCipher);
  }

  @override
  Future<void> deleteBoxFromDisk(String name, {String? path}) =>
      _inner.deleteBoxFromDisk(name, path: path);

  @override
  Future<bool> boxExists(String name, {String? path}) =>
      _inner.boxExists(name, path: path);

  @override
  List<int> generateSecureKey() => _inner.generateSecureKey();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by EncryptedBox');
}
