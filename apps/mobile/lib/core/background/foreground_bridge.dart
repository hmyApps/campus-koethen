// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

/// How a background run ended up when the running app was asked first.
enum DelegatedRun {
  /// No app isolate lives in this process: the caller has to run itself.
  noForeground,

  /// The running app did the work (or tried to).
  handled,

  /// The app was asked but did not answer in time.
  timedOut,
}

/// Lets a background run hand its work to the app that is already alive.
///
/// The encrypted caches (Hive) are not safe to open from two isolates of one
/// process: a run that opened them next to the app's own isolate could
/// corrupt them. So the app registers itself here, and a background run asks
/// first. Only a process without an app isolate — the system started it for
/// the background run alone — does the work itself.
abstract final class ForegroundBridge {
  static const String _portName =
      'dev.erikengler.campuskoethen/background-sync';
  static ReceivePort? _port;

  /// Makes this isolate the one that serves background runs. [run] performs
  /// one complete run; its errors never leave this isolate.
  static void register(Future<void> Function() run) {
    unregister();
    final ReceivePort port = ReceivePort();
    port.listen((Object? message) async {
      if (message is! SendPort) return;
      // First answer at once: a port left behind by an app isolate that has
      // died stays registered and never answers.
      message.send('accepted');
      try {
        await run();
      } catch (_) {
        // Reported as handled: a failing run is not retried by asking again.
      }
      message.send('done');
    });
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    _port = port;
  }

  /// Whether this isolate currently serves background runs.
  static bool get isRegistered => _port != null;

  static void unregister() {
    final ReceivePort? port = _port;
    if (port == null) return;
    IsolateNameServer.removePortNameMapping(_portName);
    port.close();
    _port = null;
  }

  /// Asks the running app, if there is one, to perform the run.
  ///
  /// [acknowledgement] bounds how long a silent port is believed in; [timeout]
  /// bounds the run itself.
  static Future<DelegatedRun> delegate({
    Duration timeout = const Duration(minutes: 8),
    Duration acknowledgement = const Duration(seconds: 5),
  }) async {
    final SendPort? app = IsolateNameServer.lookupPortByName(_portName);
    if (app == null) return DelegatedRun.noForeground;
    final ReceivePort reply = ReceivePort();
    final Completer<void> accepted = Completer<void>();
    final Completer<void> done = Completer<void>();
    reply.listen((Object? message) {
      if (message == 'accepted' && !accepted.isCompleted) accepted.complete();
      if (message == 'done' && !done.isCompleted) done.complete();
    });
    try {
      app.send(reply.sendPort);
      try {
        await accepted.future.timeout(acknowledgement);
      } on TimeoutException {
        // Dead port of an app that is gone: forget it and run alone.
        IsolateNameServer.removePortNameMapping(_portName);
        return DelegatedRun.noForeground;
      }
      await done.future.timeout(timeout);
      return DelegatedRun.handled;
    } on TimeoutException {
      return DelegatedRun.timedOut;
    } finally {
      reply.close();
    }
  }
}
