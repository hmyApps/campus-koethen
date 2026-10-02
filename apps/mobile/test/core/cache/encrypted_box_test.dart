// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const FlutterSecureStorage _storage = FlutterSecureStorage();

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

  EncryptedBox box({FlutterSecureStorage storage = _storage}) => EncryptedBox(
    boxName: 'checked-write-test',
    keyStorageKey: 'checked-write-test-key',
    storage: storage,
    hive: Hive,
    initializeHive: () async {},
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
