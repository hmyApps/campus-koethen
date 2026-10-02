// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/session_guard.dart';
import '../../grades/application/grade_account_controller.dart';
import '../../grades/domain/grade_portal.dart';
import '../domain/student_service_cache_store.dart';
import '../domain/student_service_failure.dart';
import '../domain/student_service_gateway.dart';
import '../domain/student_service_overview.dart';
import 'student_service_providers.dart';

/// How long an automatic sync stays suppressed after the last attempt — same
/// policy as grades.
const Duration kStudentServiceAutoSyncInterval = Duration(hours: 24);

/// Everything the HISinOne student-service screen shows at once.
class StudentServiceViewState {
  const StudentServiceViewState({
    this.overview,
    this.lastSuccessfulSync,
    this.isSyncing = false,
    this.error,
  });

  final StudentServiceOverview? overview;
  final DateTime? lastSuccessfulSync;
  final bool isSyncing;
  final StudentServiceFailure? error;

  bool get hasCache => overview != null;

  StudentServiceViewState copyWith({
    StudentServiceOverview? overview,
    DateTime? lastSuccessfulSync,
    bool? isSyncing,
    StudentServiceFailure? error,
    bool clearError = false,
  }) => StudentServiceViewState(
    overview: overview ?? this.overview,
    lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
    isSyncing: isSyncing ?? this.isSyncing,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Serves the cached Studienservice overview and enforces the sync policy.
///
/// This feature has no sign-in of its own: it is only reachable, and only
/// ever reads, while grades is connected to the HISinOne portal. Losing that
/// connection (disconnect, portal switch, account switch) invalidates this
/// controller's session guard exactly like a sign-out would for a feature
/// that owns its own credentials — a sync already in flight at that moment
/// must not write a cache entry for an account that is no longer current.
class StudentServiceController extends AsyncNotifier<StudentServiceViewState> {
  Future<void>? _inFlight;

  StudentServiceCacheStore get _cache =>
      ref.read(studentServiceCacheStoreProvider);
  SessionGuard<String> get _sessions =>
      ref.read(studentServiceSessionGuardProvider);

  @override
  Future<StudentServiceViewState> build() async {
    final GradeAccountState? account = ref
        .watch(gradeAccountControllerProvider)
        .value;
    if (!_isUsable(account)) {
      await _sessions.invalidateAndWait();
      return const StudentServiceViewState();
    }
    // `initializeIfNeeded` deliberately cannot revive an invalidated guard.
    // A confirmed grades-account state is the authoritative activation event;
    // `activate` is a no-op for the same still-current identity and creates a
    // fresh generation after logout or an account switch.
    _sessions.activate(account!.username!);
    final StudentServiceOverview? overview = await _cache.readOverview();
    final DateTime? lastSuccess = await _cache.readLastSuccessfulSync();
    return StudentServiceViewState(
      overview: overview,
      lastSuccessfulSync: lastSuccess,
    );
  }

  /// Whether the account can use this feature at all right now: grades
  /// signed in AND on the HISinOne portal — the legacy HIS-QIS portal has
  /// none of these pages.
  static bool _isUsable(GradeAccountState? account) =>
      account != null &&
      account.isSignedIn &&
      account.activePortal == GradePortal.hisInOne;

  Future<void> maybeAutoSync() async {
    if (_inFlight != null) return;
    final GradeAccountState? account = ref
        .read(gradeAccountControllerProvider)
        .value;
    if (!_isUsable(account)) return;

    final DateTime? lastAttempt = await _cache.readLastAttemptedSync();
    final DateTime now = ref.read(studentServiceClockProvider).now();
    if (lastAttempt != null &&
        now.difference(lastAttempt) < kStudentServiceAutoSyncInterval) {
      return;
    }
    await _sync();
  }

  Future<void> refresh() => _sync();

  Future<void> _sync() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;
    final GradeAccountState? account = ref
        .read(gradeAccountControllerProvider)
        .value;
    if (!_isUsable(account)) return Future<void>.value();
    final SessionLease<String>? lease = _sessions.capture(account!.username!);
    if (lease == null) return Future<void>.value();

    final Future<void> run = _sessions.track<void>(lease, () => _doSync(lease));
    _inFlight = run;
    return run.whenComplete(() => _inFlight = null);
  }

  /// Whether [lease] is still current — checked two ways, not one:
  ///
  ///  - [SessionGuard.isCurrent] catches a second local sync superseding this
  ///    one (two `refresh()` calls, a portal switch while this feature's own
  ///    `build()` already re-ran).
  ///  - A direct [ref.read] of grades' CURRENT account state catches the
  ///    disconnect-race this feature actually has no sign-in of its own to
  ///    guard: `build()`'s reaction to that disconnect (and the
  ///    `invalidateAndWait()` inside it) runs on Riverpod's own schedule,
  ///    which is not guaranteed to have already happened by the time a
  ///    pending network call resolves. Reading grades' state directly has no
  ///    such delay — it is never stale, because it is not a copy.
  ///
  /// Either signal being false is enough to stop; neither is trusted alone.
  bool _isCurrent(SessionLease<String> lease) {
    if (!_sessions.isCurrent(lease)) return false;
    final GradeAccountState? account = ref
        .read(gradeAccountControllerProvider)
        .value;
    return _isUsable(account) && account!.username == lease.identity;
  }

  Future<void> _doSync(SessionLease<String> lease) async {
    if (!_isCurrent(lease)) return;
    final StudentServiceViewState current =
        state.value ?? const StudentServiceViewState();
    state = AsyncData(current.copyWith(isSyncing: true, clearError: true));

    try {
      final DateTime now = ref.read(studentServiceClockProvider).now();
      await _cache.writeLastAttemptedSync(now);
      if (!_isCurrent(lease)) return;

      final credentials = await ref
          .read(gradeAccountControllerProvider.notifier)
          .requireCredentials();
      if (!_isCurrent(lease)) return;

      final StudentServiceOverview overview = await ref
          .read(studentServiceGatewayProvider)
          .fetchOverview(credentials);
      if (!_isCurrent(lease)) return;

      await _cache.writeOverview(overview);
      if (!_isCurrent(lease)) return;
      await _cache.writeLastSuccessfulSync(now);
      if (!_isCurrent(lease)) return;

      state = AsyncData(
        StudentServiceViewState(
          overview: overview,
          lastSuccessfulSync: now,
          isSyncing: false,
        ),
      );
    } catch (error) {
      final StudentServiceFailure failure = error is StudentServiceFailure
          ? error
          : const StudentServiceFailure(StudentServiceFailureKind.unknown);
      if (!_isCurrent(lease)) return;
      state = AsyncData(
        (state.value ?? current).copyWith(isSyncing: false, error: failure),
      );
    }
  }

  /// Generates and fetches one certificate. Not cached and not retried
  /// automatically — a one-shot action the reader explicitly triggered.
  Future<CertificateDownloadResult> downloadCertificate(
    CertificateOffer offer,
  ) async {
    final GradeAccountState? account = ref
        .read(gradeAccountControllerProvider)
        .value;
    if (!_isUsable(account)) {
      throw const StudentServiceFailure(StudentServiceFailureKind.notConnected);
    }
    final SessionLease<String>? lease = _sessions.capture(account!.username!);
    if (lease == null) {
      throw const StudentServiceFailure(StudentServiceFailureKind.notConnected);
    }
    return _sessions.track<CertificateDownloadResult>(lease, () async {
      final credentials = await ref
          .read(gradeAccountControllerProvider.notifier)
          .requireCredentials();
      if (!_isCurrent(lease)) {
        throw const StudentServiceFailure(
          StudentServiceFailureKind.notConnected,
        );
      }
      final CertificateDownloadResult result = await ref
          .read(studentServiceGatewayProvider)
          .downloadCertificate(credentials, offer);
      if (!_isCurrent(lease)) {
        throw const StudentServiceFailure(
          StudentServiceFailureKind.notConnected,
        );
      }
      return result;
    });
  }
}

final AsyncNotifierProvider<StudentServiceController, StudentServiceViewState>
studentServiceControllerProvider =
    AsyncNotifierProvider<StudentServiceController, StudentServiceViewState>(
      StudentServiceController.new,
      retry: (_, _) => null,
    );
