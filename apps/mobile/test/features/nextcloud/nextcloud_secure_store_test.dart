// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/nextcloud/data/secure_nextcloud_credential_store.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_account.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_failure.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const NextcloudCredential _credential = NextcloudCredential(
  server: 'https://cloud.hs-anhalt.de',
  loginName: 'ab123',
  userId: 'AB123',
  appPassword: 'secret-app-password',
);

void main() {
  test(
    'round-trips credentials without exposing the secret in account',
    () async {
      final _ControlledStorage storage = _ControlledStorage();
      final SecureNextcloudCredentialStore store =
          SecureNextcloudCredentialStore(storage);

      await store.write(_credential);

      expect(await store.read(), _credential);
      expect(
        (await store.read())!.toAccount().toString(),
        isNot(contains('secret')),
      );
    },
  );

  test('failed verified write removes every partially written value', () async {
    final _ControlledStorage storage = _ControlledStorage(
      droppedWrites: <String>{SecureNextcloudCredentialStore.appPasswordKey},
    );

    await expectLater(
      SecureNextcloudCredentialStore(storage).write(_credential),
      throwsA(
        const NextcloudFailure(NextcloudFailureKind.secureStorageUnavailable),
      ),
    );
    expect(storage.values, isEmpty);
  });

  test('clear rejects a secret that survives deletion', () async {
    final _ControlledStorage storage = _ControlledStorage(
      values: <String, String>{
        SecureNextcloudCredentialStore.appPasswordKey: 'secret',
      },
      droppedDeletes: <String>{SecureNextcloudCredentialStore.appPasswordKey},
    );

    await expectLater(
      SecureNextcloudCredentialStore(storage).clear(),
      throwsA(
        const NextcloudFailure(NextcloudFailureKind.secureStorageUnavailable),
      ),
    );
  });

  test(
    'read reports secure-storage failure instead of looking signed out',
    () async {
      final _ControlledStorage storage = _ControlledStorage(readFails: true);

      await expectLater(
        SecureNextcloudCredentialStore(storage).read(),
        throwsA(
          const NextcloudFailure(NextcloudFailureKind.secureStorageUnavailable),
        ),
      );
    },
  );

  test(
    'incomplete credential is wiped and a retained secret is reported',
    () async {
      final _ControlledStorage storage = _ControlledStorage(
        values: <String, String>{
          SecureNextcloudCredentialStore.serverKey:
              'https://cloud.hs-anhalt.de',
          SecureNextcloudCredentialStore.appPasswordKey: 'orphaned-secret',
        },
        droppedDeletes: <String>{SecureNextcloudCredentialStore.appPasswordKey},
      );

      await expectLater(
        SecureNextcloudCredentialStore(storage).read(),
        throwsA(
          const NextcloudFailure(NextcloudFailureKind.secureStorageUnavailable),
        ),
      );
    },
  );
}

class _ControlledStorage extends FlutterSecureStorage {
  _ControlledStorage({
    Map<String, String>? values,
    Set<String>? droppedWrites,
    Set<String>? droppedDeletes,
    this.readFails = false,
  }) : values = values ?? <String, String>{},
       droppedWrites = droppedWrites ?? <String>{},
       droppedDeletes = droppedDeletes ?? <String>{};

  final Map<String, String> values;
  final Set<String> droppedWrites;
  final Set<String> droppedDeletes;
  final bool readFails;

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
    if (readFails) throw StateError('secure storage unavailable');
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
