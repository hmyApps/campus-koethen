// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/app_secure_storage.dart';
import '../domain/moodle_account.dart';
import '../domain/moodle_failure.dart';

/// [MoodleTokenStore] backed by the device keychain/keystore.
///
/// The token exists nowhere else: no SharedPreferences, no plain Hive, no
/// plaintext file, no Riverpod state, no static field and no log line. If the
/// secure backend is unavailable, [write] throws so the caller refuses to store
/// rather than downgrading to insecure storage.
class SecureMoodleTokenStore implements MoodleTokenStore {
  SecureMoodleTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? appSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _tokenKey = 'moodle.token';
  static const String _userIdKey = 'moodle.userid';
  static const String _usernameKey = 'moodle.username';
  static const String _siteNameKey = 'moodle.sitename';

  /// Returns null only when no complete token is stored.
  ///
  /// A keychain that cannot be read is a different state and throws
  /// [MoodleFailureKind.secureStorageUnavailable]. Reporting it as "absent"
  /// made a stored connection look gone, and reconnecting then treated the
  /// unreadable account as a different identity and wiped the encrypted cache.
  @override
  Future<MoodleToken?> read() async {
    try {
      final String? token = await _storage.read(key: _tokenKey);
      final String? userIdRaw = await _storage.read(key: _userIdKey);
      final int? userId = userIdRaw == null ? null : int.tryParse(userIdRaw);
      if (token == null || userId == null) return null;
      return MoodleToken(
        value: token,
        userId: userId,
        username: await _storage.read(key: _usernameKey),
        siteName: await _storage.read(key: _siteNameKey),
      );
    } catch (_) {
      throw const MoodleFailure(MoodleFailureKind.secureStorageUnavailable);
    }
  }

  @override
  Future<void> write(MoodleToken token) async {
    try {
      await _storage.write(key: _tokenKey, value: token.value);
      await _storage.write(key: _userIdKey, value: '${token.userId}');
      await _writeOptional(_usernameKey, token.username);
      await _writeOptional(_siteNameKey, token.siteName);

      final Map<String, String?> expected = <String, String?>{
        _tokenKey: token.value,
        _userIdKey: '${token.userId}',
        _usernameKey: token.username,
        _siteNameKey: token.siteName,
      };
      for (final MapEntry<String, String?> entry in expected.entries) {
        if (await _storage.read(key: entry.key) != entry.value) {
          throw StateError('secure storage write was not retained');
        }
      }
    } catch (_) {
      await _deleteUnchecked();
      throw const MoodleFailure(MoodleFailureKind.secureStorageUnavailable);
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
      throw const MoodleFailure(MoodleFailureKind.secureStorageUnavailable);
    }
  }

  static const List<String> _keys = <String>[
    _tokenKey,
    _userIdKey,
    _usernameKey,
    _siteNameKey,
  ];

  Future<void> _writeOptional(String key, String? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);

  Future<void> _deleteUnchecked() async {
    for (final String key in _keys) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
  }
}
