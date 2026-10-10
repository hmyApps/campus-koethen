// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/app_secure_storage.dart';
import '../domain/grade_failure.dart';
import '../domain/grade_portal.dart';
import '../domain/grade_portal_store.dart';

/// [GradePortalStore] backed by the device keychain/keystore — the same
/// secure-storage mechanism as [SecureGradeCredentialStore], so deleting the
/// account removes the portal choice in the same step.
class SecureGradePortalStore implements GradePortalStore {
  SecureGradePortalStore([FlutterSecureStorage? storage])
    : _storage = storage ?? appSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _portalKey = 'grades.active.portal';

  /// Returns `null` ONLY when no choice is stored — an account set up before
  /// the portal choice existed, which the account controller deliberately
  /// maps to the legacy portal. A keystore that fails to read, or a stored
  /// value this version does not recognise, throws
  /// [GradeFailureKind.secureStorageUnavailable] instead: silently reading
  /// either as "no choice" moved HISinOne accounts onto the legacy portal.
  @override
  Future<GradePortal?> read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _portalKey);
    } catch (_) {
      throw const GradeFailure(GradeFailureKind.secureStorageUnavailable);
    }
    if (raw == null) return null;
    for (final GradePortal p in GradePortal.values) {
      if (p.name == raw) return p;
    }
    throw const GradeFailure(GradeFailureKind.secureStorageUnavailable);
  }

  @override
  Future<void> write(GradePortal portal) async {
    try {
      await _storage.write(key: _portalKey, value: portal.name);
      if (await _storage.read(key: _portalKey) != portal.name) {
        throw StateError('secure storage write was not retained');
      }
    } catch (_) {
      throw const GradeFailure(GradeFailureKind.secureStorageUnavailable);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _portalKey);
      if (await _storage.read(key: _portalKey) != null) {
        throw StateError('secure storage value survived deletion');
      }
    } catch (_) {
      throw const GradeFailure(GradeFailureKind.secureStorageUnavailable);
    }
  }
}
