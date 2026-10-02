// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/moodle_account.dart';
import '../domain/moodle_course.dart';
import '../domain/moodle_deadline.dart';
import '../domain/moodle_failure.dart';
import '../domain/moodle_repository.dart';
import 'moodle_account_controller.dart';
import 'moodle_providers.dart';

/// How long an automatic sync stays suppressed after the last attempt.
const Duration kMoodleAutoSyncInterval = Duration(hours: 1);

/// Everything the Moodle overview shows at once.
class MoodleOverviewState {
  const MoodleOverviewState({
    this.courses = const <MoodleCourse>[],
    this.deadlines = const <MoodleDeadline>[],
    this.lastSuccessfulSync,
    this.isSyncing = false,
    this.error,
  });

  final List<MoodleCourse> courses;
  final List<MoodleDeadline> deadlines;
  final DateTime? lastSuccessfulSync;
  final bool isSyncing;
  final MoodleFailure? error;

  bool get hasCache => lastSuccessfulSync != null || courses.isNotEmpty;

  MoodleOverviewState copyWith({
    List<MoodleCourse>? courses,
    List<MoodleDeadline>? deadlines,
    DateTime? lastSuccessfulSync,
    bool? isSyncing,
    MoodleFailure? error,
    bool clearError = false,
  }) => MoodleOverviewState(
    courses: courses ?? this.courses,
    deadlines: deadlines ?? this.deadlines,
    lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
    isSyncing: isSyncing ?? this.isSyncing,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Serves the cached Moodle overview and enforces the sync policy.
///
/// Automatic sync is rolling: at most one attempt per hour, gated
/// by the stored `lastAttempt`. A failed attempt still advances that timestamp
/// (recorded up front), so it is NOT retried on every rebuild. Only a validated
/// success replaces the cache and moves `lastSuccessfulSync`. Manual [refresh]
/// bypasses the one-hour gate. Concurrent syncs merge into one network call.
/// The app-level foreground scheduler calls [maybeAutoSync] on boot and hourly;
/// screens may call it too without creating duplicate requests.
class MoodleController extends AsyncNotifier<MoodleOverviewState> {
  Future<void>? _inFlight;

  MoodleRepository get _repo => ref.read(moodleRepositoryProvider);

  @override
  Future<MoodleOverviewState> build() async {
    final int generation = ref.watch(moodleSessionGenerationProvider);
    final MoodleAccount? account = ref
        .watch(moodleAccountControllerProvider)
        .value;
    if (account == null) return const MoodleOverviewState();
    final _MoodleSessionSnapshot session = (
      generation: generation,
      userId: account.userId,
    );

    final List<MoodleCourse> courses =
        await _repo.cachedCourses() ?? const <MoodleCourse>[];
    if (!_isCurrent(session)) return const MoodleOverviewState();
    final List<MoodleDeadline> deadlines =
        await _repo.cachedDeadlines() ?? const <MoodleDeadline>[];
    if (!_isCurrent(session)) return const MoodleOverviewState();
    final marks = await _repo.syncMarks();
    if (!_isCurrent(session)) return const MoodleOverviewState();
    return MoodleOverviewState(
      courses: courses,
      deadlines: deadlines,
      lastSuccessfulSync: marks.lastSuccess,
    );
  }

  /// Lazy automatic sync — call when the screen opens. No-op if a sync runs, if
  /// disconnected, or if the last attempt is younger than the interval.
  Future<void> maybeAutoSync() async {
    if (_inFlight != null) return;
    if (ref.read(moodleAccountControllerProvider).value == null) return;

    final marks = await _repo.syncMarks();
    final DateTime now = ref.read(moodleClockProvider).now();
    final DateTime? lastAttempt = marks.lastAttempt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < kMoodleAutoSyncInterval) {
      return; // too soon for another automatic call
    }
    await _sync();
  }

  /// Manual sync (button / pull-to-refresh). Bypasses the one-hour gate but
  /// still joins an in-flight sync instead of starting a second one.
  Future<void> refresh() => _sync();

  Future<void> _sync() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;
    final MoodleAccount? account = ref
        .read(moodleAccountControllerProvider)
        .value;
    if (account == null) return Future<void>.value();
    final _MoodleSessionSnapshot session = (
      generation: ref.read(moodleSessionGenerationProvider),
      userId: account.userId,
    );
    final Future<void> run = _doSync(session);
    _inFlight = run;
    return run.whenComplete(() => _inFlight = null);
  }

  Future<void> _doSync(_MoodleSessionSnapshot session) async {
    if (!_isCurrent(session)) return;
    final MoodleOverviewState current =
        state.value ?? const MoodleOverviewState();
    state = AsyncData(current.copyWith(isSyncing: true, clearError: true));

    try {
      // Record the attempt up front so a failed automatic sync is not retried
      // on every rebuild within the one-hour window.
      final DateTime now = ref.read(moodleClockProvider).now();
      await _repo.recordAttempt(now);
      if (!_isCurrent(session)) return;
      final MoodleOverview overview = await _repo.refreshOverview();
      if (!_isCurrent(session)) return;
      state = AsyncData(
        MoodleOverviewState(
          courses: overview.courses,
          deadlines: overview.deadlines,
          lastSuccessfulSync: now,
          isSyncing: false,
        ),
      );
    } catch (error) {
      final MoodleFailure failure = error is MoodleFailure
          ? error
          : const MoodleFailure(MoodleFailureKind.unknown);
      if (!_isCurrent(session)) return;
      // Keep the last good cache; just surface the error alongside it.
      state = AsyncData(
        (state.value ?? current).copyWith(isSyncing: false, error: failure),
      );
    }
  }

  bool _isCurrent(_MoodleSessionSnapshot session) {
    final MoodleAccount? account = ref
        .read(moodleAccountControllerProvider)
        .value;
    return ref.read(moodleSessionGenerationProvider) == session.generation &&
        account?.userId == session.userId;
  }
}

typedef _MoodleSessionSnapshot = ({int generation, int userId});

final AsyncNotifierProvider<MoodleController, MoodleOverviewState>
moodleControllerProvider =
    AsyncNotifierProvider<MoodleController, MoodleOverviewState>(
      MoodleController.new,
      retry: (_, _) => null,
    );
