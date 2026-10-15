// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:campus_koethen/core/background/foreground_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ForegroundBridge.unregister);

  test('without a running app nobody takes the run', () async {
    expect(await ForegroundBridge.delegate(), DelegatedRun.noForeground);
  });

  test('a running app takes the run and reports that it finished', () async {
    int runs = 0;
    ForegroundBridge.register(() async => runs++);

    expect(await ForegroundBridge.delegate(), DelegatedRun.handled);
    expect(runs, 1);
  });

  test('a run that throws is still reported as handled, never rerun', () async {
    ForegroundBridge.register(() async => throw StateError('boom'));

    expect(await ForegroundBridge.delegate(), DelegatedRun.handled);
  });

  test('an app that never answers ends in a timeout, not a hang', () async {
    ForegroundBridge.register(() => Completer<void>().future);

    expect(
      await ForegroundBridge.delegate(
        timeout: const Duration(milliseconds: 50),
      ),
      DelegatedRun.timedOut,
    );
  });

  test('a port nobody listens to any more is dropped, and the caller runs '
      'itself', () async {
    final ReceivePort dead = ReceivePort();
    IsolateNameServer.registerPortWithName(
      dead.sendPort,
      'dev.erikengler.campuskoethen/background-sync',
    );
    dead.close();

    expect(
      await ForegroundBridge.delegate(
        acknowledgement: const Duration(milliseconds: 50),
      ),
      DelegatedRun.noForeground,
    );
    expect(
      IsolateNameServer.lookupPortByName(
        'dev.erikengler.campuskoethen/background-sync',
      ),
      isNull,
    );
  });

  test('after unregistering the app is gone again', () async {
    ForegroundBridge.register(() async {});
    ForegroundBridge.unregister();

    expect(await ForegroundBridge.delegate(), DelegatedRun.noForeground);
  });
}
