// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/app_secure_storage.dart';
import '../domain/hsa_ki_account.dart';
import '../domain/hsa_ki_failure.dart';

class SecureHsaKiCredentialStore implements HsaKiCredentialStore {
  SecureHsaKiCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? appSecureStorage();

  final FlutterSecureStorage _storage;

  static const String tokenKey = 'hsaKi.token';
  static const String tokenIdKey = 'hsaKi.tokenId';
  static const String usernameKey = 'hsaKi.username';

  static const List<String> _keys = <String>[
    tokenKey,
    tokenIdKey,
    usernameKey,
  ];

  @override
  Future<HsaKiCredential?> read() async {
    try {
      final List<String?> values = await Future.wait(
        _keys.map((String key) => _storage.read(key: key)),
      );
      if (values.every((String? value) => value == null)) return null;
      if (values.any((String? value) => value == null)) {
        await clear();
        return null;
      }
      return HsaKiCredential(
        token: values[0]!,
        tokenId: values[1]!,
        username: values[2]!,
      );
    } catch (_) {
      throw const HsaKiFailure(HsaKiFailureKind.secureStorageUnavailable);
    }
  }

  @override
  Future<void> write(HsaKiCredential credential) async {
    final Map<String, String> expected = <String, String>{
      tokenKey: credential.token,
      tokenIdKey: credential.tokenId,
      usernameKey: credential.username,
    };
    try {
      for (final MapEntry<String, String> entry in expected.entries) {
        await _storage.write(key: entry.key, value: entry.value);
      }
      for (final MapEntry<String, String> entry in expected.entries) {
        if (await _storage.read(key: entry.key) != entry.value) {
          throw StateError('secure storage write was not retained');
        }
      }
    } catch (_) {
      await _deleteUnchecked();
      throw const HsaKiFailure(HsaKiFailureKind.secureStorageUnavailable);
    }
  }

  @override
  Future<void> clear() async {
    Object? failure;
    for (final String key in _keys) {
      try {
        await _storage.delete(key: key);
      } catch (error) {
        failure ??= error;
      }
    }
    for (final String key in _keys) {
      try {
        if (await _storage.read(key: key) != null) {
          failure ??= StateError('secure storage value survived deletion');
        }
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) {
      throw const HsaKiFailure(HsaKiFailureKind.secureStorageUnavailable);
    }
  }

  Future<void> _deleteUnchecked() async {
    for (final String key in _keys) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
  }
}
