// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/matrix_database_key_store.dart';
import '../domain/matrix_failure.dart';

/// The Matrix SDK's SQLite database, only ever opened encrypted with
/// SQLite3MultipleCiphers (AGENTS.md §2).
///
/// It holds the session token, the device and room keys and the messages.
/// Its key lives only in the Keychain/Keystore ([MatrixDatabaseKeyStore]).
class EncryptedMatrixDatabase {
  EncryptedMatrixDatabase({
    required this._keyStore,
    DatabaseFactory? factory,
    Future<Directory> Function()? directory,
  }) : _factory = factory ?? databaseFactoryFfi,
       _directory = directory ?? getApplicationSupportDirectory;

  final MatrixDatabaseKeyStore _keyStore;
  final DatabaseFactory _factory;
  final Future<Directory> Function() _directory;

  static const String fileName = 'campus_chat.sqlite';

  /// SQLite's own side files next to the database.
  static const List<String> _sideFileSuffixes = <String>[
    '-journal',
    '-wal',
    '-shm',
  ];

  /// Whether a database key exists, i.e. whether a session may be stored.
  /// Creates nothing.
  Future<bool> hasKey() async => await _keyStore.read() != null;

  /// Opens the database, creating it (and its key) on first use.
  Future<Database> open() async {
    final String path = await _path();
    String? key = await _keyStore.read();
    if (key == null) {
      // A database whose key is gone can never be read again. Start clean
      // rather than fail forever on a file nobody can open.
      await _deleteFiles(path);
      key = await _keyStore.readOrCreate();
    }
    final String databaseKey = key;
    try {
      return await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          onConfigure: (Database db) => _applyKey(db, databaseKey),
        ),
      );
    } on MatrixFailure {
      rethrow;
    } catch (_) {
      throw const MatrixFailure(MatrixFailureKind.databaseUnavailable);
    }
  }

  /// Deletes the database and then its key, and verifies both are gone.
  ///
  /// The key is removed even when the files cannot be, so nothing left on
  /// the device stays readable.
  Future<void> wipe() async {
    MatrixFailure? failure;
    try {
      await _deleteFiles(await _path());
    } catch (_) {
      failure = const MatrixFailure(MatrixFailureKind.databaseUnavailable);
    }
    try {
      await _keyStore.clear();
    } on MatrixFailure catch (error) {
      failure ??= error;
    } catch (_) {
      failure ??= const MatrixFailure(
        MatrixFailureKind.secureStorageUnavailable,
      );
    }
    if (failure != null) throw failure;
  }

  Future<String> _path() async {
    try {
      final Directory directory = await _directory();
      return '${directory.path}${Platform.pathSeparator}$fileName';
    } catch (_) {
      throw const MatrixFailure(MatrixFailureKind.databaseUnavailable);
    }
  }

  Future<void> _deleteFiles(String path) async {
    await _factory.deleteDatabase(path);
    for (final String file in <String>[
      path,
      for (final String suffix in _sideFileSuffixes) '$path$suffix',
    ]) {
      final File entry = File(file);
      if (await entry.exists()) await entry.delete();
      if (await entry.exists()) {
        throw StateError('database file was not deleted');
      }
    }
  }

  /// Runs before anything else touches the file. No SQLite error escapes
  /// from here: those can quote the statement, and this one carries the key.
  static Future<void> _applyKey(Database db, String key) async {
    final List<Map<String, Object?>> cipher;
    try {
      cipher = await db.rawQuery('PRAGMA cipher');
    } catch (_) {
      throw const MatrixFailure(MatrixFailureKind.encryptionUnavailable);
    }
    // Plain SQLite ignores unknown pragmas silently, so an empty answer means
    // the database would be written unencrypted.
    if (cipher.isEmpty) {
      throw const MatrixFailure(MatrixFailureKind.encryptionUnavailable);
    }
    try {
      // The key is base64url, validated by the key store: no quote can occur.
      await db.rawQuery("PRAGMA key = '$key'");
      // A wrong key only shows on the first read.
      await db.rawQuery('SELECT count(*) FROM sqlite_master');
    } catch (_) {
      throw const MatrixFailure(MatrixFailureKind.databaseUnavailable);
    }
  }
}
