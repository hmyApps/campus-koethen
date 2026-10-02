// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/app_secure_storage.dart';
import '../domain/university_identity.dart';
import '../domain/university_identity_store.dart';

/// Device-bound secure storage for the optional central university identity.
class SecureUniversityIdentityStore implements UniversityIdentityStore {
  SecureUniversityIdentityStore([FlutterSecureStorage? storage])
    : _storage = storage ?? appSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _identifierKey = 'university.identity.identifier';
  static const String _passwordKey = 'university.identity.password';
  static const String _legacyUsernameKey = 'university.identity.username';
  static const String _legacyEmailKey = 'university.identity.email';
  static const List<String> _legacyKeys = <String>[
    _legacyUsernameKey,
    _legacyEmailKey,
  ];
  static const List<String> _keys = <String>[
    _identifierKey,
    _passwordKey,
    ..._legacyKeys,
  ];

  @override
  Future<UniversityIdentity?> read() async {
    try {
      final List<String?> legacyValues = await Future.wait<String?>(
        _legacyKeys.map((String key) => _storage.read(key: key)),
      );
      if (legacyValues.any((String? value) => value != null)) {
        // The retired three-field model is deliberately not migrated. A bare
        // username and an email address can disagree, so choosing one would be
        // an invisible credential rewrite. The agreed upgrade behaviour is a
        // verified full wipe followed by an explicit fresh setup.
        await clear();
        return null;
      }
      final String? identifier = await _storage.read(key: _identifierKey);
      final String? password = await _storage.read(key: _passwordKey);
      if (identifier == null && password == null) return null;
      if (identifier == null || password == null) {
        await _deleteUnchecked();
        throw StateError('incomplete secure identity');
      }
      final UniversityIdentity identity = UniversityIdentity(
        identifier: identifier,
        password: password,
      );
      if (!identity.isValid) {
        await _deleteUnchecked();
        throw StateError('invalid secure identity');
      }
      return identity;
    } catch (_) {
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.secureStorageUnavailable,
      );
    }
  }

  @override
  Future<void> write(UniversityIdentity identity) async {
    final UniversityIdentity value = identity.normalized;
    if (!value.isValid) {
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.invalidIdentity,
      );
    }
    try {
      for (final String key in _legacyKeys) {
        await _storage.delete(key: key);
        if (await _storage.read(key: key) != null) {
          throw StateError('retired secure identity survived deletion');
        }
      }
      await _storage.write(key: _identifierKey, value: value.identifier);
      await _storage.write(key: _passwordKey, value: value.password);
      if (await _storage.read(key: _identifierKey) != value.identifier ||
          await _storage.read(key: _passwordKey) != value.password) {
        throw StateError('secure storage write was not retained');
      }
    } catch (_) {
      await _deleteUnchecked();
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.secureStorageUnavailable,
      );
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
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.secureStorageUnavailable,
      );
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
