// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/notification_gateway.dart';
import '../domain/notification_plan.dart';
import '../domain/planned_notification.dart';

/// What one apply-run actually achieved.
///
/// Counts, never content: how many entries the operating system was asked
/// for, how many it accepted, and how many it refused. A refusal is the early
/// indicator that a platform limit has been reached (ADR-0001 § 7.5).
@immutable
class NotificationSyncResult {
  const NotificationSyncResult({
    required this.requested,
    required this.scheduled,
    required this.failed,
    required this.cancelledOnly,
    this.cancellationFailed = false,
  });

  const NotificationSyncResult.cancelled()
    : requested = 0,
      scheduled = 0,
      failed = 0,
      cancelledOnly = true,
      cancellationFailed = false;

  const NotificationSyncResult.cancellationFailure({required this.requested})
    : scheduled = 0,
      failed = requested,
      cancelledOnly = false,
      cancellationFailed = true;

  final int requested;
  final int scheduled;
  final int failed;

  /// The run only cleared the pending entries — notifications are off, or the
  /// permission is gone.
  final bool cancelledOnly;

  /// The previous platform state could not be cleared, so no replacement was
  /// attempted. Existing entries may still be pending, but duplicates cannot
  /// have been introduced by this run.
  final bool cancellationFailed;

  String toLogLine() {
    if (cancellationFailed) {
      return 'notifications: cancellation failed; replacement skipped';
    }
    return cancelledOnly
        ? 'notifications: cleared all pending entries'
        : 'notifications: scheduled $scheduled/$requested'
              '${failed == 0 ? '' : ' failed=$failed'}';
  }
}

/// Registers a [NotificationPlan] with the operating system.
///
/// Two properties carry the whole design:
///
/// **Full replacement, never a delta.** Every run cancels everything still
/// pending and re-registers the plan. That is what makes "updated",
/// "replaced" and "cancelled" need no code of their own (ADR-0001 § 7.1): a
/// cancelled event simply is not in the next plan. Notifications already
/// delivered are not part of that state and are never touched (F-01).
///
/// **Strictly serialised.** `cancelAllPending()` and the re-scheduling that follows
/// it are not atomic, so two runs overlapping would interleave a cancel into
/// another run's scheduling and leave an arbitrary subset behind. Runs are
/// therefore chained; a second one waits.
///
/// The remaining, deliberately accepted risk is the window between the cancel
/// and the last schedule: a process killed exactly there leaves nothing
/// pending until the app is next opened. Acceptable because every app start
/// plans again — but real, and part of the manual device matrix.
class NotificationScheduler {
  NotificationScheduler(this._gateway);

  final NotificationGateway _gateway;

  Future<void> _tail = Future<void>.value();

  /// Whether a run is currently in flight or queued. Diagnostic only.
  bool get isBusy => _pending > 0;
  int _pending = 0;

  /// Replaces everything currently pending with [plan].
  ///
  /// The returned future completes when **this** run is done, not when the
  /// queue is empty, so a caller can await its own work.
  Future<NotificationSyncResult> apply(NotificationPlan plan) {
    return _enqueue(() async {
      final bool cancelled = await _gateway.cancelAllPending();
      if (!cancelled) {
        final NotificationSyncResult result =
            NotificationSyncResult.cancellationFailure(
              requested: plan.notifications.length,
            );
        _log(plan.diagnostics.toLogLine());
        _log(result.toLogLine());
        return result;
      }
      if (plan.isEmpty) {
        _log(const NotificationSyncResult.cancelled().toLogLine());
        _log(plan.diagnostics.toLogLine());
        return const NotificationSyncResult.cancelled();
      }
      int scheduled = 0;
      int failed = 0;
      for (final PlannedNotification notification in plan.notifications) {
        try {
          await _gateway.schedule(notification);
          scheduled++;
        } catch (error) {
          // One entry the platform refuses must not cost the rest of the
          // plan. The count is what surfaces; the entry itself is not logged.
          failed++;
          _log('notifications: schedule failed (${error.runtimeType})');
        }
      }
      final NotificationSyncResult result = NotificationSyncResult(
        requested: plan.notifications.length,
        scheduled: scheduled,
        failed: failed,
        cancelledOnly: false,
      );
      _log(plan.diagnostics.toLogLine());
      _log(result.toLogLine());
      return result;
    });
  }

  /// Clears every pending entry — switching notifications off, or a withdrawn
  /// permission. Goes through the same queue, so it can never race a run that
  /// is still scheduling. Delivered notifications stay.
  Future<bool> cancelAllPending() =>
      _enqueue(() => _gateway.cancelAllPending());

  Future<T> _enqueue<T>(Future<T> Function() run) {
    _pending++;
    final Completer<T> completer = Completer<T>();
    _tail = _tail
        .then((_) => run())
        .then(
          completer.complete,
          onError: (Object error, StackTrace stackTrace) {
            // The chain must survive: a failed run may not stop every later
            // one. The error is handed to this run's caller only.
            completer.completeError(error, stackTrace);
          },
        )
        .whenComplete(() => _pending--);
    return completer.future;
  }

  void _log(String line) {
    assert(() {
      debugPrint(line);
      return true;
    }());
  }
}
