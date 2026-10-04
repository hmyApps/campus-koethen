// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/session_guard.dart';
import '../data/encrypted_grade_cache.dart';
import '../data/his_in_one_grades_gateway.dart';
import '../data/legacy_qis_gateway.dart';
import '../data/secure_grade_credential_store.dart';
import '../data/secure_grade_portal_store.dart';
import '../domain/clock.dart';
import '../domain/exam_report_gateway.dart';
import '../domain/grade_cache_store.dart';
import '../domain/grade_credential_store.dart';
import '../domain/grade_portal.dart';
import '../domain/grade_portal_store.dart';
import '../domain/grades_gateway.dart';
import '../domain/his_in_one_profile.dart';
import '../domain/legacy_qis_profile.dart';
import 'grade_account_controller.dart';

/// One personal-data store whose lifetime is tied to the grades account.
///
/// The callback must first invalidate and drain its own in-flight writers and
/// only then perform a verified wipe. Runtime wiring registers the HISinOne
/// student-service cache; the empty default keeps the grades feature reusable
/// and makes the dependency explicit in tests.
typedef GradeLinkedPersonalDataWiper = Future<void> Function();

final Provider<List<GradeLinkedPersonalDataWiper>>
gradeLinkedPersonalDataWipersProvider =
    Provider<List<GradeLinkedPersonalDataWiper>>(
      (Ref ref) => const <GradeLinkedPersonalDataWiper>[],
    );

/// The pinned legacy HIS-QIS endpoints (host allowlist).
final Provider<LegacyQisProfile> legacyQisProfileProvider =
    Provider<LegacyQisProfile>((Ref ref) => const LegacyQisProfile());

/// The pinned HISinOne endpoints (own, separate host allowlist).
final Provider<HisInOneProfile> hisInOneProfileProvider =
    Provider<HisInOneProfile>((Ref ref) => const HisInOneProfile());

/// QIS credentials in the device keychain/keystore. Overridden in tests.
final Provider<GradeCredentialStore> gradeCredentialStoreProvider =
    Provider<GradeCredentialStore>((Ref ref) => SecureGradeCredentialStore());

/// The active portal choice, in the same secure storage as the credentials.
/// Overridden in tests.
final Provider<GradePortalStore> gradePortalStoreProvider =
    Provider<GradePortalStore>((Ref ref) => SecureGradePortalStore());

/// The legacy HIS-QIS gateway.
final Provider<GradesGateway> legacyQisGatewayProvider =
    Provider<GradesGateway>(
      (Ref ref) => LegacyQisGradesGateway(ref.watch(legacyQisProfileProvider)),
    );

/// The HISinOne gateway.
final Provider<GradesGateway> hisInOneGatewayProvider = Provider<GradesGateway>(
  (Ref ref) => HisInOneGradesGateway(ref.watch(hisInOneProfileProvider)),
);

/// The exam-overview page's own "Bescheinigungen" print buttons — HISinOne
/// only, exactly like `studentServiceGatewayProvider` is HISinOne only. The
/// UI gates on `GradeAccountState.activePortal == GradePortal.hisInOne`
/// before ever using this, the same way it gates student-service.
final Provider<ExamReportGateway> examReportGatewayProvider =
    Provider<ExamReportGateway>(
      (Ref ref) => HisInOneGradesGateway(ref.watch(hisInOneProfileProvider)),
    );

/// The gateway for the account's ACTIVE portal (falls back to the legacy
/// portal while no choice has been persisted, e.g. before the first sign-in).
/// A single Riverpod override on this provider (as tests do) replaces the
/// whole resolution, so existing gateway fakes keep working unchanged.
final Provider<GradesGateway> gradesGatewayProvider = Provider<GradesGateway>((
  Ref ref,
) {
  final GradePortal portal =
      ref.watch(gradeAccountControllerProvider).value?.activePortal ??
      GradePortal.hisQisLegacy;
  return portal == GradePortal.hisInOne
      ? ref.watch(hisInOneGatewayProvider)
      : ref.watch(legacyQisGatewayProvider);
});

/// The encrypted local grade cache. Overridden in tests.
final Provider<GradeCacheStore> gradeCacheStoreProvider =
    Provider<GradeCacheStore>((Ref ref) => EncryptedGradeCache());

/// Injectable clock so the 24-hour policy is testable.
final Provider<Clock> gradeClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// Coordinates portal work with account removal/replacement.
final Provider<SessionGuard<({String username, GradePortal portal})>>
gradeSessionGuardProvider =
    Provider<SessionGuard<({String username, GradePortal portal})>>(
      (Ref ref) => SessionGuard<({String username, GradePortal portal})>(),
    );
