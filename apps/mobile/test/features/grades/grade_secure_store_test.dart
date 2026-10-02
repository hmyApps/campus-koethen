// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/features/grades/data/encrypted_grade_cache.dart';
import 'package:campus_koethen/features/grades/data/secure_grade_credential_store.dart';
import 'package:campus_koethen/features/grades/data/secure_grade_portal_store.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/domain/grade_failure.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const GradeCredentials _credentials = GradeCredentials(
  username: 'student',
  password: 'secret',
);

void main() {
  test('credential write rejects a silently retained older value', () async {
    final _ControlledStorage storage = _ControlledStorage(
      values: <String, String>{
        'grades.qis.username': 'student',
        'grades.qis.password': 'old-secret',
      },
      droppedWrites: <String>{'grades.qis.password'},
    );

    await expectLater(
      SecureGradeCredentialStore(storage).write(_credentials),
      throwsA(const GradeFailure(GradeFailureKind.secureStorageUnavailable)),
    );
  });

  test('credential clear rejects a silently retained secret', () async {
    final _ControlledStorage storage = _ControlledStorage(
      values: <String, String>{
        'grades.qis.username': 'student',
        'grades.qis.password': 'secret',
      },
      droppedDeletes: <String>{'grades.qis.password'},
    );

    await expectLater(
      SecureGradeCredentialStore(storage).clear(),
      throwsA(const GradeFailure(GradeFailureKind.secureStorageUnavailable)),
    );
  });

  test('portal write and clear require an exact readback', () async {
    final _ControlledStorage writeStorage = _ControlledStorage(
      values: <String, String>{'grades.active.portal': 'hisQisLegacy'},
      droppedWrites: <String>{'grades.active.portal'},
    );
    await expectLater(
      SecureGradePortalStore(writeStorage).write(GradePortal.hisInOne),
      throwsA(const GradeFailure(GradeFailureKind.secureStorageUnavailable)),
    );

    final _ControlledStorage deleteStorage = _ControlledStorage(
      values: <String, String>{'grades.active.portal': 'hisInOne'},
      droppedDeletes: <String>{'grades.active.portal'},
    );
    await expectLater(
      SecureGradePortalStore(deleteStorage).clear(),
      throwsA(const GradeFailure(GradeFailureKind.secureStorageUnavailable)),
    );
  });

  test('grade cache clear rejects an incomplete encrypted wipe', () async {
    final EncryptedGradeCache cache = EncryptedGradeCache(
      _WipeBox(const EncryptedBoxWipeResult(keyAbsent: false, boxAbsent: true)),
    );

    await expectLater(
      cache.clear(),
      throwsA(const GradeFailure(GradeFailureKind.cacheUnavailable)),
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
