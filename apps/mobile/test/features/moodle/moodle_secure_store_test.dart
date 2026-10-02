// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/features/moodle/data/encrypted_moodle_cache.dart';
import 'package:campus_koethen/features/moodle/data/secure_moodle_token_store.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_failure.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const MoodleToken _token = MoodleToken(
  value: 'new-token',
  userId: 7,
  username: 'student',
  siteName: 'Moodle',
);

void main() {
  test('token write rejects a silently retained older token', () async {
    final _ControlledStorage storage = _ControlledStorage(
      values: <String, String>{
        'moodle.token': 'old-token',
        'moodle.userid': '7',
      },
      droppedWrites: <String>{'moodle.token'},
    );

    await expectLater(
      SecureMoodleTokenStore(storage).write(_token),
      throwsA(const MoodleFailure(MoodleFailureKind.secureStorageUnavailable)),
    );
  });

  test('token write removes stale optional account metadata', () async {
    final _ControlledStorage storage = _ControlledStorage(
      values: <String, String>{
        'moodle.username': 'old-user',
        'moodle.sitename': 'Old Moodle',
      },
    );

    await SecureMoodleTokenStore(
      storage,
    ).write(const MoodleToken(value: 'token', userId: 9));

    expect(storage.values['moodle.username'], isNull);
    expect(storage.values['moodle.sitename'], isNull);
  });

  test('token clear rejects a silently retained secret', () async {
    final _ControlledStorage storage = _ControlledStorage(
      values: <String, String>{
        'moodle.token': 'secret-token',
        'moodle.userid': '7',
      },
      droppedDeletes: <String>{'moodle.token'},
    );

    await expectLater(
      SecureMoodleTokenStore(storage).clear(),
      throwsA(const MoodleFailure(MoodleFailureKind.secureStorageUnavailable)),
    );
  });

  test('Moodle cache clear rejects an incomplete encrypted wipe', () async {
    final EncryptedMoodleCache cache = EncryptedMoodleCache(
      _WipeBox(const EncryptedBoxWipeResult(keyAbsent: true, boxAbsent: false)),
    );

    await expectLater(
      cache.clear(),
      throwsA(const MoodleFailure(MoodleFailureKind.cacheUnavailable)),
    );
  });
}

class _WipeBox extends EncryptedBox {
  _WipeBox(this.result) : super(boxName: 'unused', keyStorageKey: 'unused-key');

  final EncryptedBoxWipeResult result;

  @override
  Future<EncryptedBoxWipeResult> wipeChecked() async => result;
}

class _ControlledStorage extends FlutterSecureStorage {
  _ControlledStorage({
    Map<String, String>? values,
    Set<String>? droppedWrites,
    Set<String>? droppedDeletes,
  }) : values = values ?? <String, String>{},
       droppedWrites = droppedWrites ?? <String>{},
       droppedDeletes = droppedDeletes ?? <String>{};

  final Map<String, String> values;
  final Set<String> droppedWrites;
  final Set<String> droppedDeletes;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

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
    if (droppedWrites.contains(key)) return;
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
    if (!droppedDeletes.contains(key)) values.remove(key);
  }
}
