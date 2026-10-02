// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/session_guard.dart';
import '../domain/grade.dart';
import '../domain/grade_cache_store.dart';
import '../domain/grade_failure.dart';
import '../domain/grade_portal.dart';
import 'grade_account_controller.dart';
import 'grades_providers.dart';

/// How long an automatic sync stays suppressed after the last attempt.
const Duration kGradeAutoSyncInterval = Duration(hours: 24);

/// Everything the grades screen shows at once.
class GradesViewState {
  const GradesViewState({
    this.report,
    this.lastSuccessfulSync,
    this.isSyncing = false,
    this.error,
  });

  /// The cached report (last successful). Null when nothing has been cached.
  final GradeReport? report;

  /// When the report was last fetched successfully ("last updated").
  final DateTime? lastSuccessfulSync;

  /// A sync is in progress.
  final bool isSyncing;

  /// The most recent sync error, if any (the cache stays visible alongside it).
  final GradeFailure? error;

  bool get hasCache => report != null;

  GradesViewState copyWith({
    GradeReport? report,
    DateTime? lastSuccessfulSync,
    bool? isSyncing,
    GradeFailure? error,
    bool clearError = false,
  }) => GradesViewState(
    report: report ?? this.report,
    lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
    isSyncing: isSyncing ?? this.isSyncing,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Serves the cached grades and enforces the sync policy.
///
/// Automatic sync is lazy and rolling: at most one attempt per 24 hours, gated
/// by [GradeCacheStore.readLastAttemptedSync]. A failed attempt still updates
/// that timestamp, so it is NOT retried on every rebuild. Only a successful sync
/// replaces the cache and moves `lastSuccessfulSync`. Manual [refresh] bypasses
/// the 24-hour gate. Concurrent syncs are merged into one portal call.
class GradesController extends AsyncNotifier<GradesViewState> {
  Future<void>? _inFlight;

  GradeCacheStore get _cache => ref.read(gradeCacheStoreProvider);
  SessionGuard<({String username, GradePortal portal})> get _sessions =>
      ref.read(gradeSessionGuardProvider);

  @override
  Future<GradesViewState> build() async {
    final GradeAccountState? account = ref
        .watch(gradeAccountControllerProvider)
        .value;
    if (account == null || !account.isSignedIn) {
      return const GradesViewState();
    }
    // Offline-first: show whatever is cached immediately.
    final GradeReport? report = await _cache.readReport();
    final DateTime? lastSuccess = await _cache.readLastSuccessfulSync();
    return GradesViewState(report: report, lastSuccessfulSync: lastSuccess);
  }

  /// The lazy automatic sync — call this when the screen opens. Does nothing if
  /// a sync is already running, if signed out, or if the last attempt is younger
  /// than [kGradeAutoSyncInterval].
  Future<void> maybeAutoSync() async {
    if (_inFlight != null) return;
    final GradeAccountState? account = ref
        .read(gradeAccountControllerProvider)
        .value;
    if (account == null || !account.isSignedIn) return;

    final DateTime? lastAttempt = await _cache.readLastAttemptedSync();
    final DateTime now = ref.read(gradeClockProvider).now();
    if (lastAttempt != null &&
        now.difference(lastAttempt) < kGradeAutoSyncInterval) {
      return; // too soon for another automatic call
    }
    await _sync();
  }

  /// A manual sync (button / pull-to-refresh). Bypasses the 24-hour gate but
  /// still joins an in-flight sync instead of starting a second one.
  Future<void> refresh() => _sync();

  Future<void> _sync() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;
    final GradeAccountState? account = ref
        .read(gradeAccountControllerProvider)
        .value;
    final String? username = account?.username;
    final GradePortal? portal = account?.activePortal;
    if (username == null || portal == null) return Future<void>.value();
    final SessionLease<({String username, GradePortal portal})>? lease =
        _sessions.capture((username: username, portal: portal));
    if (lease == null) return Future<void>.value();

    final Future<void> run = _sessions.track<void>(lease, () => _doSync(lease));
    _inFlight = run;
    return run.whenComplete(() => _inFlight = null);
  }

  Future<void> _doSync(
    SessionLease<({String username, GradePortal portal})> lease,
  ) async {
    if (!_sessions.isCurrent(lease)) return;
    final GradesViewState current = state.value ?? const GradesViewState();
    state = AsyncData(current.copyWith(isSyncing: true, clearError: true));

    try {
      final DateTime now = ref.read(gradeClockProvider).now();
      // Record the attempt up front, so a failed automatic sync is not retried
      // on every rebuild within the 24-hour window.
      if (!_sessions.isCurrent(lease)) return;
      await _cache.writeLastAttemptedSync(now);
      if (!_sessions.isCurrent(lease)) return;

      final credentials = await ref
          .read(gradeAccountControllerProvider.notifier)
          .requireCredentials();
      if (!_sessions.isCurrent(lease)) return;
      final GradeReport report = await ref
          .read(gradesGatewayProvider)
          .fetchGrades(credentials);
      if (!_sessions.isCurrent(lease)) return;
      // An empty answer NEVER replaces grades we already have. The portal
      // returning nothing where it returned 75 entries yesterday means the
      // account moved, the session was silently dropped or the page changed —
      // never that the results are gone. Keep the cache and surface it.
      final GradeReport? cached = current.report;
      if (report.isEmpty && cached != null && !cached.isEmpty) {
        if (!_sessions.isCurrent(lease)) return;
        state = AsyncData(
          current.copyWith(
            isSyncing: false,
            error: const GradeFailure(GradeFailureKind.portalStructureChanged),
          ),
        );
        return;
      }
      // Only a success replaces the cache and moves lastSuccessfulSync.
      if (!_sessions.isCurrent(lease)) return;
      await _cache.writeReport(report);
      if (!_sessions.isCurrent(lease)) return;
      await _cache.writeLastSuccessfulSync(now);
      if (!_sessions.isCurrent(lease)) return;
      state = AsyncData(
        GradesViewState(
          report: report,
          lastSuccessfulSync: now,
          isSyncing: false,
        ),
      );
    } catch (error) {
      final GradeFailure failure = error is GradeFailure
          ? error
          : const GradeFailure(GradeFailureKind.unknown);
      if (!_sessions.isCurrent(lease)) return;
      // Keep the last good cache and lastSuccessfulSync; just surface the error.
      state = AsyncData(
        (state.value ?? current).copyWith(isSyncing: false, error: failure),
      );
    }
  }
}

final AsyncNotifierProvider<GradesController, GradesViewState>
gradesControllerProvider =
    AsyncNotifierProvider<GradesController, GradesViewState>(
      GradesController.new,
      // No Riverpod auto-retry: sync errors are handled explicitly and surfaced.
      retry: (_, _) => null,
    );
