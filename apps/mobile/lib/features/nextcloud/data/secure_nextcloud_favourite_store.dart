// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/app_secure_storage.dart';
import '../domain/nextcloud_account.dart';
import '../domain/nextcloud_failure.dart';
import '../domain/nextcloud_favourite_store.dart';
import '../domain/nextcloud_profile.dart';

class SecureNextcloudFavouriteStore implements NextcloudFavouriteStore {
  SecureNextcloudFavouriteStore([FlutterSecureStorage? storage])
    : _storage = storage ?? appSecureStorage();

  static const int maximumFavourites = 100;
  static const String storageKey = 'nextcloud.favourites.v1';
  static const int _schemaVersion = 1;

  final FlutterSecureStorage _storage;

  @override
  Future<Set<String>> read(NextcloudAccount account) async {
    try {
      final String? encoded = await _storage.read(key: storageKey);
      if (encoded == null) return const <String>{};
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?> ||
          decoded['version'] != _schemaVersion ||
          decoded['userId'] != account.userId ||
          decoded['paths'] is! List<Object?>) {
        await clear();
        return const <String>{};
      }
      final List<Object?> rawPaths = decoded['paths']! as List<Object?>;
      if (rawPaths.length > maximumFavourites) {
        await clear();
        return const <String>{};
      }
      final Set<String> paths = <String>{};
      for (final Object? raw in rawPaths) {
        if (raw is! String || !_validPath(raw)) {
          await clear();
          return const <String>{};
        }
        paths.add(raw);
      }
      return Set<String>.unmodifiable(paths);
    } on NextcloudFailure {
      rethrow;
    } catch (_) {
      throw const NextcloudFailure(
        NextcloudFailureKind.secureStorageUnavailable,
      );
    }
  }

  @override
  Future<void> write(NextcloudAccount account, Set<String> paths) async {
    if (paths.length > maximumFavourites) {
      throw const NextcloudFailure(NextcloudFailureKind.favouriteLimitReached);
    }
    if (account.userId.isEmpty ||
        account.userId.length > 512 ||
        paths.any((String path) => !_validPath(path))) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    final List<String> ordered = paths.toList()..sort();
    final String encoded = jsonEncode(<String, Object?>{
      'version': _schemaVersion,
      'userId': account.userId,
      'paths': ordered,
    });
    try {
      await _storage.write(key: storageKey, value: encoded);
      if (await _storage.read(key: storageKey) != encoded) {
        throw StateError('secure storage write was not retained');
      }
    } catch (_) {
      try {
        await _storage.delete(key: storageKey);
      } catch (_) {}
      throw const NextcloudFailure(
        NextcloudFailureKind.secureStorageUnavailable,
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: storageKey);
      if (await _storage.read(key: storageKey) != null) {
        throw StateError('secure storage value survived deletion');
      }
    } catch (_) {
      throw const NextcloudFailure(
        NextcloudFailureKind.secureStorageUnavailable,
      );
    }
  }

  bool _validPath(String path) {
    if (path.length > 4096 || path == '/') return false;
    try {
      const NextcloudProfile profile = NextcloudProfile();
      return profile.normalizedPath(profile.normalizedSegments(path)) == path;
    } on ArgumentError {
      return false;
    }
  }
}
