// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import '../../../core/cache/encrypted_box.dart';
import '../domain/student_service_cache_store.dart';
import '../domain/student_service_failure.dart';
import '../domain/student_service_overview.dart';
import 'student_service_cache_codec.dart';

/// [StudentServiceCacheStore] backed by the shared [EncryptedBox] — same
/// pattern as `EncryptedGradeCache`. Reads are best effort; only a
/// successfully fetched overview is ever written, so the last good cache
/// always survives a failed sync.
class EncryptedStudentServiceCache implements StudentServiceCacheStore {
  EncryptedStudentServiceCache([EncryptedBox? box])
    : _box =
          box ??
          EncryptedBox(
            boxName: 'campus_student_service_cache_v1',
            keyStorageKey: 'student_service.cache.key.v1',
          );

  final EncryptedBox _box;

  static const String _overviewKey = 'overview';
  static const String _lastSuccessKey = 'lastSuccess';
  static const String _lastAttemptKey = 'lastAttempt';

  @override
  Future<StudentServiceOverview?> readOverview() async {
    final String? raw = await _box.read(_overviewKey);
    if (raw == null) return null;
    try {
      return StudentServiceCacheCodec.overviewFrom(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeOverview(StudentServiceOverview overview) => _box.write(
    _overviewKey,
    jsonEncode(StudentServiceCacheCodec.overview(overview)),
  );

  @override
  Future<DateTime?> readLastSuccessfulSync() => _readDate(_lastSuccessKey);

  @override
  Future<void> writeLastSuccessfulSync(DateTime at) =>
      _writeDate(_lastSuccessKey, at);

  @override
  Future<DateTime?> readLastAttemptedSync() => _readDate(_lastAttemptKey);

  @override
  Future<void> writeLastAttemptedSync(DateTime at) =>
      _writeDate(_lastAttemptKey, at);

  Future<DateTime?> _readDate(String key) async {
    final String? raw = await _box.read(key);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> _writeDate(String key, DateTime at) =>
      _box.write(key, at.toUtc().toIso8601String());

  @override
  Future<void> clear() async {
    final EncryptedBoxWipeResult result = await _box.wipeChecked();
    if (!result.isComplete) {
      throw const StudentServiceFailure(
        StudentServiceFailureKind.cacheUnavailable,
      );
    }
  }
}
