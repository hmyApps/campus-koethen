// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/app_secure_storage.dart';
import '../domain/matrix_database_key_store.dart';
import '../domain/matrix_failure.dart';

class SecureMatrixDatabaseKeyStore implements MatrixDatabaseKeyStore {
  SecureMatrixDatabaseKeyStore([FlutterSecureStorage? storage, Random? random])
    : _storage = storage ?? appSecureStorage(),
      _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _random;

  static const String databaseKeyKey = 'matrix.databaseKey';
  static const int _keyBytes = 32;

  @override
  Future<String?> read() async {
    final String? value;
    try {
      value = await _storage.read(key: databaseKeyKey);
    } catch (_) {
      throw const MatrixFailure(MatrixFailureKind.secureStorageUnavailable);
    }
    if (value == null) return null;
    if (!_isKey(value)) {
      // Never "repair" a broken value with a fresh key: that would silently
      // orphan an existing database. The caller decides to wipe and restart.
      throw const MatrixFailure(MatrixFailureKind.secureStorageUnavailable);
    }
    return value;
  }

  @override
  Future<String> readOrCreate() async {
    final String? existing = await read();
    if (existing != null) return existing;
    final String created = base64Url.encode(
      List<int>.generate(_keyBytes, (_) => _random.nextInt(256)),
    );
    try {
      await _storage.write(key: databaseKeyKey, value: created);
      if (await _storage.read(key: databaseKeyKey) != created) {
        throw StateError('secure storage write was not retained');
      }
    } catch (_) {
      try {
        await _storage.delete(key: databaseKeyKey);
      } catch (_) {}
      throw const MatrixFailure(MatrixFailureKind.secureStorageUnavailable);
    }
    return created;
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: databaseKeyKey);
      if (await _storage.read(key: databaseKeyKey) != null) {
        throw StateError('secure storage delete was not performed');
      }
    } catch (_) {
      throw const MatrixFailure(MatrixFailureKind.secureStorageUnavailable);
    }
  }

  static bool _isKey(String value) {
    try {
      return base64Url.decode(value).length == _keyBytes;
    } on FormatException {
      return false;
    }
  }
}
