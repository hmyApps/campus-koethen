// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

/// Owns the foreground-only refresh and rate-limit timers of a submission.
class SubmissionPollingController {
  SubmissionPollingController({required this.interval, required this.onPoll});

  final Duration interval;
  final Future<void> Function() onPoll;

  Timer? _periodic;
  Timer? _resume;
  bool _disposed = false;

  bool get isRunning => _periodic?.isActive ?? false;

  void start() {
    if (_disposed) return;
    _periodic?.cancel();
    _resume?.cancel();
    _resume = null;
    _periodic = Timer.periodic(interval, (_) => unawaited(onPoll()));
  }

  void stop() {
    _periodic?.cancel();
    _periodic = null;
    _resume?.cancel();
    _resume = null;
  }

  void pauseFor(Duration duration) {
    if (_disposed) return;
    stop();
    _resume = Timer(duration, start);
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
