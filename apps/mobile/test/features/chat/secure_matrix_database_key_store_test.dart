// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:campus_koethen/features/chat/data/secure_matrix_database_key_store.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_matrix.dart';

Matcher _failure(MatrixFailureKind kind) => throwsA(
  isA<MatrixFailure>().having((MatrixFailure f) => f.kind, 'kind', kind),
);

void main() {
  const String key = SecureMatrixDatabaseKeyStore.databaseKeyKey;

  test('creates a random 256-bit key once and returns it afterwards', () async {
    final MemorySecureStorage storage = MemorySecureStorage();
    final SecureMatrixDatabaseKeyStore store = SecureMatrixDatabaseKeyStore(
      storage,
    );

    expect(await store.read(), isNull);
    final String created = await store.readOrCreate();

    expect(base64Url.decode(created), hasLength(32));
    expect(await store.readOrCreate(), created);
    expect(storage.values[key], created);
  });

  test('two stores never share a key', () async {
    final String a = await SecureMatrixDatabaseKeyStore(
      MemorySecureStorage(),
    ).readOrCreate();
    final String b = await SecureMatrixDatabaseKeyStore(
      MemorySecureStorage(),
    ).readOrCreate();

    expect(a, isNot(b));
  });

  test('a keystore that cannot be read is a classified failure, never a new '
      'key that would orphan the database', () async {
    final MemorySecureStorage storage = MemorySecureStorage(
      values: <String, String>{key: base64Url.encode(List<int>.filled(32, 7))},
    )..readFails = true;
    final SecureMatrixDatabaseKeyStore store = SecureMatrixDatabaseKeyStore(
      storage,
    );

    await expectLater(
      store.readOrCreate(),
      _failure(MatrixFailureKind.secureStorageUnavailable),
    );
  });

  test('a write the keystore does not keep is reported and leaves nothing '
      'behind', () async {
    final MemorySecureStorage storage = MemorySecureStorage()
      ..droppedWrites.add(key);
    final SecureMatrixDatabaseKeyStore store = SecureMatrixDatabaseKeyStore(
      storage,
    );

    await expectLater(
      store.readOrCreate(),
      _failure(MatrixFailureKind.secureStorageUnavailable),
    );
    expect(storage.values, isEmpty);
  });

  test('a stored value that is not a 256-bit key is refused', () async {
    final SecureMatrixDatabaseKeyStore store = SecureMatrixDatabaseKeyStore(
      MemorySecureStorage(values: <String, String>{key: 'not-a-key'}),
    );

    await expectLater(
      store.readOrCreate(),
      _failure(MatrixFailureKind.secureStorageUnavailable),
    );
  });

  test('clear removes the key and verifies it is gone', () async {
    final MemorySecureStorage storage = MemorySecureStorage();
    final SecureMatrixDatabaseKeyStore store = SecureMatrixDatabaseKeyStore(
      storage,
    );
    await store.readOrCreate();

    await store.clear();

    expect(storage.values, isEmpty);
    expect(await store.read(), isNull);
  });

  test('a delete the keystore does not perform is reported', () async {
    final MemorySecureStorage storage = MemorySecureStorage();
    final SecureMatrixDatabaseKeyStore store = SecureMatrixDatabaseKeyStore(
      storage,
    );
    await store.readOrCreate();
    storage.droppedDeletes.add(key);

    await expectLater(
      store.clear(),
      _failure(MatrixFailureKind.secureStorageUnavailable),
    );
  });
}
