// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/case_status.dart';
import '../domain/status_gateway.dart';
import '../domain/submitted_case.dart';
import 'requests_providers.dart';
import 'submissions_controller.dart';

/// What the app currently knows about one case's state.
///
/// Deliberately **in memory only**. The status endpoint answers
/// `Cache-Control: no-store`, and persisting a response would let the app show
/// yesterday's decision as today's — offline it says it has nothing current
/// rather than presenting a stale answer as fresh.
class CaseStatusState {
  const CaseStatusState({
    this.status,
    this.isLoading = false,
    this.error,
    this.blockedUntil,
  });

  final CaseStatus? status;
  final bool isLoading;

  /// The last failure, kept so the screen can offer a retry.
  final StatusResult? error;

  /// Set by a 429: no request goes out before this moment.
  final DateTime? blockedUntil;

  bool get hasStatus => status != null;

  bool isBlockedAt(DateTime now) =>
      blockedUntil != null && now.isBefore(blockedUntil!);

  CaseStatusState copyWith({
    CaseStatus? status,
    bool? isLoading,
    StatusResult? error,
    bool clearError = false,
    DateTime? blockedUntil,
    bool clearBlock = false,
  }) => CaseStatusState(
    status: status ?? this.status,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    blockedUntil: clearBlock ? null : (blockedUntil ?? this.blockedUntil),
  );
}

/// Fetches and refreshes the state of the cases this device knows about.
///
/// Three things this class exists to get right:
///
/// * **Single flight.** Two screens asking for the same case at the same
///   moment produce one request, not two — the list refresh and a detail view
///   opening at once is the ordinary case, not an edge one.
/// * **A ceiling on concurrency.** Refreshing the list fires at most three
///   requests at a time. A student with twenty cases should not open twenty
///   sockets, and the endpoint's rate limit is shared with everyone else on
///   the same network.
/// * **Respecting 429.** `Retry-After` is an instruction, not a hint. Nothing
///   goes out for that case until it has passed.
class CaseStatusController extends Notifier<Map<String, CaseStatusState>> {
  final Map<String, Future<StatusResult>> _inFlight =
      <String, Future<StatusResult>>{};

  /// Set by any 429: the limit is this client's, not one case's, so no case
  /// is asked about before it has passed (E-09).
  DateTime? _blockedUntil;

  /// Bumped on every (re)build. A fetch that started before a local wipe
  /// belongs to an older generation, and its answer — links, documents,
  /// personal data — is dropped instead of being written back (E-10).
  int _generation = 0;

  static const int maxConcurrentRefreshes = 3;

  @override
  Map<String, CaseStatusState> build() {
    _generation++;
    _inFlight.clear();
    _blockedUntil = null;
    return const <String, CaseStatusState>{};
  }

  CaseStatusState stateFor(String id) => state[id] ?? const CaseStatusState();

  bool _isBlockedAt(DateTime now) =>
      _blockedUntil != null && now.isBefore(_blockedUntil!);

  /// Fetches one case, joining an in-flight request for the same one.
  Future<StatusResult> refresh(
    SubmittedCase submitted, {
    required DateTime now,
    bool force = false,
  }) {
    final CaseStatusState current = stateFor(submitted.id);
    if (!force && _isBlockedAt(now)) {
      return Future<StatusResult>.value(
        StatusRateLimited(retryAfter: _blockedUntil!.difference(now)),
      );
    }
    if (!force && current.isBlockedAt(now)) {
      return Future<StatusResult>.value(
        StatusRateLimited(retryAfter: current.blockedUntil!.difference(now)),
      );
    }

    final Future<StatusResult>? running = _inFlight[submitted.id];
    if (running != null) return running;

    final Future<StatusResult> request = _fetch(submitted, now);
    _inFlight[submitted.id] = request;
    return request.whenComplete(() {
      if (identical(_inFlight[submitted.id], request)) {
        _inFlight.remove(submitted.id);
      }
    });
  }

  Future<StatusResult> _fetch(SubmittedCase submitted, DateTime now) async {
    final int generation = _generation;
    _set(submitted.id, stateFor(submitted.id).copyWith(isLoading: true));

    final StatusResult result = await ref
        .read(statusGatewayProvider)
        .fetch(submitted.statusUrl);

    // Wiped (or rebuilt) meanwhile: the answer is about data that is gone.
    if (!ref.mounted || generation != _generation) return result;

    switch (result) {
      case StatusLoaded(:final CaseStatus status):
        _set(submitted.id, CaseStatusState(status: status, isLoading: false));
        // Number and title are not secret and make the list readable offline.
        // The status itself is never written down.
        await ref
            .read(submissionsProvider.notifier)
            .noteServerFacts(
              submitted.id,
              number: status.number,
              title: switch (status) {
                ApplicationCaseStatus(:final String title) => title,
                FeedbackCaseStatus(:final String text) => text,
              },
            );
      case StatusRateLimited(:final Duration? retryAfter):
        final DateTime until = now.add(
          retryAfter ?? const Duration(minutes: 1),
        );
        if (_blockedUntil == null || until.isAfter(_blockedUntil!)) {
          _blockedUntil = until;
        }
        _set(
          submitted.id,
          stateFor(
            submitted.id,
          ).copyWith(isLoading: false, error: result, blockedUntil: until),
        );
      case StatusNotConnected():
      case StatusLinkInvalid():
      case StatusNotFound():
      case StatusUnavailable():
        // The previously loaded status, if any, is deliberately kept: a failed
        // refresh should not blank a screen the user is reading. It is never
        // written to disk, so it cannot outlive the session either way.
        _set(
          submitted.id,
          stateFor(submitted.id).copyWith(isLoading: false, error: result),
        );
    }

    return result;
  }

  /// Refreshes several cases, at most [maxConcurrentRefreshes] at a time.
  Future<void> refreshAll(
    List<SubmittedCase> cases, {
    required DateTime now,
  }) async {
    final List<SubmittedCase> queue = cases.toList();
    final List<Future<void>> workers = <Future<void>>[
      for (int i = 0; i < maxConcurrentRefreshes; i++)
        Future<void>(() async {
          // Stops at the first 429: the remaining cases would only be
          // refused locally anyway, and none of them may go out.
          while (queue.isNotEmpty && !_isBlockedAt(now)) {
            final SubmittedCase next = queue.removeAt(0);
            await refresh(next, now: now);
          }
        }),
    ];
    await Future.wait(workers);
  }

  void _set(String id, CaseStatusState value) {
    if (!ref.mounted) return;
    state = <String, CaseStatusState>{...state, id: value};
  }

  /// Drops what is known about one case — used when it is deleted locally.
  void forget(String id) {
    final Map<String, CaseStatusState> next = Map<String, CaseStatusState>.of(
      state,
    )..remove(id);
    state = next;
  }
}

final NotifierProvider<CaseStatusController, Map<String, CaseStatusState>>
caseStatusProvider =
    NotifierProvider<CaseStatusController, Map<String, CaseStatusState>>(
      CaseStatusController.new,
    );
