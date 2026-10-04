// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/app_secure_storage.dart';
import '../domain/nextcloud_account.dart';
import '../domain/nextcloud_failure.dart';
import '../domain/nextcloud_profile.dart';

class SecureNextcloudCredentialStore implements NextcloudCredentialStore {
  SecureNextcloudCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? appSecureStorage();

  final FlutterSecureStorage _storage;

  static const String serverKey = 'nextcloud.server';
  static const String loginNameKey = 'nextcloud.loginName';
  static const String userIdKey = 'nextcloud.userId';
  static const String appPasswordKey = 'nextcloud.appPassword';

  static const List<String> _keys = <String>[
    serverKey,
    loginNameKey,
    userIdKey,
    appPasswordKey,
  ];

  @override
  Future<NextcloudCredential?> read() async {
    try {
      final List<String?> values = await Future.wait(
        _keys.map((String key) => _storage.read(key: key)),
      );
      if (values.every((String? value) => value == null)) return null;
      if (values.any((String? value) => value == null)) {
        await clear();
        return null;
      }
      final NextcloudCredential credential = NextcloudCredential(
        server: values[0]!,
        loginName: values[1]!,
        userId: values[2]!,
        appPassword: values[3]!,
      );
      if (!_isValid(credential)) {
        await clear();
        return null;
      }
      return credential;
    } on NextcloudFailure {
      rethrow;
    } catch (_) {
      throw const NextcloudFailure(
        NextcloudFailureKind.secureStorageUnavailable,
      );
    }
  }

  @override
  Future<void> write(NextcloudCredential credential) async {
    if (!_isValid(credential)) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    final Map<String, String> expected = <String, String>{
      serverKey: credential.server,
      loginNameKey: credential.loginName,
      userIdKey: credential.userId,
      appPasswordKey: credential.appPassword,
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
      throw const NextcloudFailure(
        NextcloudFailureKind.secureStorageUnavailable,
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
      throw const NextcloudFailure(
        NextcloudFailureKind.secureStorageUnavailable,
      );
    }
  }

  bool _isValid(NextcloudCredential value) {
    final Uri? server = Uri.tryParse(value.server);
    const NextcloudProfile profile = NextcloudProfile();
    final bool scalarFieldsValid =
        server != null &&
        profile.allows(server) &&
        (server.path.isEmpty || server.path == '/') &&
        server.query.isEmpty &&
        server.fragment.isEmpty &&
        _validText(value.loginName, 512) &&
        _validText(value.userId, 512) &&
        _validText(value.appPassword, 4096);
    if (!scalarFieldsValid) return false;
    try {
      profile.davUri(userId: value.userId, path: '/');
      return true;
    } on ArgumentError {
      return false;
    }
  }

  bool _validText(String value, int maxLength) =>
      value.isNotEmpty &&
      value.length <= maxLength &&
      !_controlCharacters.hasMatch(value);

  Future<void> _deleteUnchecked() async {
    for (final String key in _keys) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
  }
}

final RegExp _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');
