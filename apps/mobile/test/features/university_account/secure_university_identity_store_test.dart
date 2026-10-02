// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/university_account/data/secure_university_identity_store.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const UniversityIdentity _identity = UniversityIdentity(
  identifier: 'student@hs-anhalt.de',
  password: 'secret',
);

void main() {
  test('round-trips both fields through secure storage', () async {
    final _ControlledStorage storage = _ControlledStorage();
    final SecureUniversityIdentityStore store = SecureUniversityIdentityStore(
      storage,
    );

    await store.write(_identity);

    expect(await store.read(), _identity);
    expect(storage.values.keys, <String>{
      'university.identity.identifier',
      'university.identity.password',
    });
  });

  test('accepts a bare username just as well as an email address', () async {
    const UniversityIdentity byUsername = UniversityIdentity(
      identifier: 'student',
      password: 'secret',
    );
    final _ControlledStorage storage = _ControlledStorage();
    final SecureUniversityIdentityStore store = SecureUniversityIdentityStore(
      storage,
    );

    await store.write(byUsername);

    expect(await store.read(), byUsername);
  });

  test(
    'an identity from the retired three-field schema is fully wiped',
    () async {
      final _ControlledStorage storage = _ControlledStorage(
        values: <String, String>{
          'university.identity.username': 'student',
          'university.identity.email': 'student@hs-anhalt.de',
          'university.identity.password': 'secret',
        },
      );
      final SecureUniversityIdentityStore store = SecureUniversityIdentityStore(
        storage,
      );

      expect(await store.read(), isNull);
      expect(storage.values, isEmpty);
    },
  );

  test(
    'rejects a silently dropped write and removes the partial identity',
    () async {
      final _ControlledStorage storage = _ControlledStorage(
        droppedWrites: <String>{'university.identity.password'},
      );

      await expectLater(
        SecureUniversityIdentityStore(storage).write(_identity),
        throwsA(
          const UniversityAccountFailure(
            UniversityAccountFailureKind.secureStorageUnavailable,
          ),
        ),
      );
      expect(storage.values, isEmpty);
    },
  );

  test('rejects a silently retained password on clear', () async {
    final _ControlledStorage storage = _ControlledStorage(
      values: <String, String>{
        'university.identity.identifier': 'student@hs-anhalt.de',
        'university.identity.password': 'secret',
      },
      droppedDeletes: <String>{'university.identity.password'},
    );

    await expectLater(
      SecureUniversityIdentityStore(storage).clear(),
      throwsA(
        const UniversityAccountFailure(
          UniversityAccountFailureKind.secureStorageUnavailable,
        ),
      ),
    );
  });

  test('clear also verifies removal of every retired schema key', () async {
    final _ControlledStorage storage = _ControlledStorage(
      values: <String, String>{
        'university.identity.username': 'student',
        'university.identity.email': 'student@hs-anhalt.de',
      },
      droppedDeletes: <String>{'university.identity.email'},
    );

    await expectLater(
      SecureUniversityIdentityStore(storage).clear(),
      throwsA(
        const UniversityAccountFailure(
          UniversityAccountFailureKind.secureStorageUnavailable,
        ),
      ),
    );
  });
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
