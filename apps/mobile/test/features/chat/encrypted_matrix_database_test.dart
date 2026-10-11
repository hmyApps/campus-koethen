// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/features/chat/data/encrypted_matrix_database.dart';
import 'package:campus_koethen/features/chat/data/secure_matrix_database_key_store.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_matrix.dart';

void main() {
  late Directory directory;
  late MemorySecureStorage storage;
  late EncryptedMatrixDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('campus_chat_test');
    storage = MemorySecureStorage();
    database = EncryptedMatrixDatabase(
      keyStore: SecureMatrixDatabaseKeyStore(storage),
      factory: databaseFactoryFfiNoIsolate,
      directory: () async => directory,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  File databaseFile() =>
      File('${directory.path}/${EncryptedMatrixDatabase.fileName}');

  Matcher failure(MatrixFailureKind kind) => throwsA(
    isA<MatrixFailure>().having((MatrixFailure f) => f.kind, 'kind', kind),
  );

  test('creates a key and never writes the database in plain text', () async {
    final Database db = await database.open();
    await db.execute('CREATE TABLE probe (value TEXT)');
    await db.insert('probe', <String, Object?>{'value': 'room secret'});
    await db.close();

    expect(
      storage.values[SecureMatrixDatabaseKeyStore.databaseKeyKey],
      isNotNull,
    );
    final List<int> bytes = await databaseFile().readAsBytes();
    expect(
      ascii.decode(bytes.take(15).toList(), allowInvalid: true),
      isNot('SQLite format 3'),
    );
    expect(
      latin1.decode(bytes, allowInvalid: true),
      isNot(contains('room secret')),
    );
  });

  test('reopens the same database with the stored key', () async {
    final Database first = await database.open();
    await first.execute('CREATE TABLE probe (value TEXT)');
    await first.insert('probe', <String, Object?>{'value': 'kept'});
    await first.close();

    final Database second = await database.open();
    final List<Map<String, Object?>> rows = await second.query('probe');
    await second.close();

    expect(rows.single['value'], 'kept');
  });

  test('refuses a database the stored key does not open', () async {
    final Database db = await database.open();
    await db.execute('CREATE TABLE probe (value TEXT)');
    await db.close();
    storage.values[SecureMatrixDatabaseKeyStore.databaseKeyKey] = base64Url
        .encode(List<int>.filled(32, 7));

    await expectLater(
      database.open(),
      failure(MatrixFailureKind.databaseUnavailable),
    );
    expect(await databaseFile().exists(), isTrue);
  });

  test('starts clean when the key is gone but a database is left', () async {
    final Database db = await database.open();
    await db.execute('CREATE TABLE probe (value TEXT)');
    await db.close();
    storage.values.clear();

    final Database reopened = await database.open();
    final List<Map<String, Object?>> tables = await reopened.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'probe'",
    );
    await reopened.close();

    expect(tables, isEmpty);
  });

  test('does not open when the keystore cannot be read', () async {
    storage.readFails = true;

    await expectLater(
      database.open(),
      failure(MatrixFailureKind.secureStorageUnavailable),
    );
    expect(await databaseFile().exists(), isFalse);
  });

  test('wipe deletes the database and its key', () async {
    final Database db = await database.open();
    await db.execute('CREATE TABLE probe (value TEXT)');
    await db.close();

    await database.wipe();

    expect(await databaseFile().exists(), isFalse);
    expect(storage.values, isEmpty);
  });

  test('wipe still removes the key when there is no database', () async {
    await SecureMatrixDatabaseKeyStore(storage).readOrCreate();

    await database.wipe();

    expect(storage.values, isEmpty);
  });

  test('wipe reports a key that could not be removed', () async {
    final Database db = await database.open();
    await db.close();
    storage.droppedDeletes.add(SecureMatrixDatabaseKeyStore.databaseKeyKey);

    await expectLater(
      database.wipe(),
      failure(MatrixFailureKind.secureStorageUnavailable),
    );
    expect(await databaseFile().exists(), isFalse);
  });
}
