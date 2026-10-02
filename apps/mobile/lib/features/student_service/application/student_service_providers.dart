// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/session_guard.dart';
import '../../grades/domain/clock.dart';
import '../data/encrypted_student_service_cache.dart';
import '../data/his_in_one_student_service_gateway.dart';
import '../domain/student_service_cache_store.dart';
import '../domain/student_service_gateway.dart';

/// The HISinOne student-service gateway. Overridden in tests.
final Provider<StudentServiceGateway> studentServiceGatewayProvider =
    Provider<StudentServiceGateway>(
      (Ref ref) => HisInOneStudentServiceGateway(),
    );

/// The encrypted local overview cache. Overridden in tests.
final Provider<StudentServiceCacheStore> studentServiceCacheStoreProvider =
    Provider<StudentServiceCacheStore>(
      (Ref ref) => EncryptedStudentServiceCache(),
    );

/// Injectable clock so the auto-sync interval is testable.
final Provider<Clock> studentServiceClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// Coordinates student-service sync work with the grades connection being
/// disconnected or switched to another account — same primitive, same
/// reasoning as `gradeSessionGuardProvider`/`moodleSessionGuardProvider`.
/// Keyed by grades' username rather than a dedicated student-service
/// identity: this feature has no sign-in of its own.
final Provider<SessionGuard<String>> studentServiceSessionGuardProvider =
    Provider<SessionGuard<String>>((Ref ref) => SessionGuard<String>());
