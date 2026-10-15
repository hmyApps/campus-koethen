// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:meta/meta.dart';

/// One independent part of a background run.
@immutable
class BackgroundSyncStep {
  const BackgroundSyncStep(this.name, this.run);

  /// A fixed technical name (`mail`, `moodle`, …). It is the only thing that
  /// ever reaches a log: never an error text, which could quote content.
  final String name;
  final Future<void> Function() run;
}

/// What one background run did. Names and flags only.
@immutable
class BackgroundSyncResult {
  const BackgroundSyncResult({
    this.completed = const <String>[],
    this.failed = const <String>[],
    this.notStarted = const <String>[],
    this.timedOut = false,
  });

  final List<String> completed;
  final List<String> failed;

  /// Steps that were never begun because the deadline was reached first.
  final List<String> notStarted;
  final bool timedOut;

  @override
  String toString() =>
      'background sync: completed=$completed failed=$failed '
      'notStarted=$notStarted timedOut=$timedOut';
}

/// Runs the steps of one background execution, one after another.
///
/// The operating system gives a background run only a few minutes and may kill
/// it afterwards, so two properties matter: a step that fails or hangs never
/// costs the steps behind it more than the [deadline], and nothing that went
/// wrong is turned into text.
class BackgroundSyncRunner {
  BackgroundSyncRunner({
    required this.steps,
    this.deadline = const Duration(minutes: 8),
  });

  final List<BackgroundSyncStep> steps;

  /// Android allows about ten minutes; stay clearly inside it.
  final Duration deadline;

  Future<BackgroundSyncResult> run() async {
    final List<String> completed = <String>[];
    final List<String> failed = <String>[];
    final Completer<void> deadlineReached = Completer<void>();
    final Timer timer = Timer(deadline, deadlineReached.complete);
    try {
      for (int i = 0; i < steps.length; i++) {
        final BackgroundSyncStep step = steps[i];
        if (deadlineReached.isCompleted) {
          return BackgroundSyncResult(
            completed: completed,
            failed: failed,
            notStarted: <String>[
              for (final BackgroundSyncStep s in steps.skip(i)) s.name,
            ],
            timedOut: true,
          );
        }
        final Future<bool> attempt = () async {
          try {
            await step.run();
            return true;
          } catch (_) {
            return false;
          }
        }();
        final Object outcome = await Future.any<Object>(<Future<Object>>[
          attempt,
          deadlineReached.future.then((_) => #deadline),
        ]);
        if (outcome == #deadline) {
          return BackgroundSyncResult(
            completed: completed,
            failed: failed,
            notStarted: <String>[
              for (final BackgroundSyncStep s in steps.skip(i + 1)) s.name,
            ],
            timedOut: true,
          );
        }
        (outcome == true ? completed : failed).add(step.name);
      }
      return BackgroundSyncResult(completed: completed, failed: failed);
    } finally {
      timer.cancel();
    }
  }
}
