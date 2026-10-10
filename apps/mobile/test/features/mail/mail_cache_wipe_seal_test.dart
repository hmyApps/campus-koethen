// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// C-13: a mail read path that was already running when the cache was wiped
/// must not bring the encrypted box — and its key — back to life.
library;

import 'dart:io';

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const FlutterSecureStorage _storage = FlutterSecureStorage();

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mail-wipe-seal-test-');
    Hive.init(directory.path);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('a stale read path cannot recreate the wiped mail cache', () async {
    final EncryptedBox box = EncryptedBox(
      boxName: MailCacheManager.secureBoxName,
      keyStorageKey: MailCacheManager.keyStorageKey,
      storage: _storage,
      hive: Hive,
      initializeHive: () async {},
    );
    final MailCacheManager manager = MailCacheManager(
      encryptedBox: box,
      hive: Hive,
      initializeHive: () async {},
    );
    await manager.activate();
    // The delegate a read path captured before the wipe began.
    final EncryptedMailCache stale = EncryptedMailCache(box);
    await stale.saveHeaders(const []);

    expect((await manager.wipe()).isComplete, isTrue);

    // That read path now finishes and writes its access index back.
    expect(await stale.readHeaders(), isEmpty);
    await box.write('metadata.v1', '{}');

    expect(await Hive.boxExists(MailCacheManager.secureBoxName), isFalse);
    expect(await _storage.read(key: MailCacheManager.keyStorageKey), isNull);

    // Signing in again is the explicit activation that reopens it.
    await manager.activate();
    expect(manager.isMemoryOnly, isFalse);
    expect(await Hive.boxExists(MailCacheManager.secureBoxName), isTrue);
  });
}
