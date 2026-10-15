// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/core/background/background_sync_runner.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs every step once, in order', () async {
    final List<String> ran = <String>[];
    final BackgroundSyncRunner runner = BackgroundSyncRunner(
      steps: <BackgroundSyncStep>[
        BackgroundSyncStep('mail', () async => ran.add('mail')),
        BackgroundSyncStep('moodle', () async => ran.add('moodle')),
        BackgroundSyncStep('events', () async => ran.add('events')),
      ],
    );

    final BackgroundSyncResult result = await runner.run();

    expect(ran, <String>['mail', 'moodle', 'events']);
    expect(result.completed, <String>['mail', 'moodle', 'events']);
    expect(result.failed, isEmpty);
    expect(result.timedOut, isFalse);
  });

  test('a failing step does not stop the others and is named, not '
      'explained', () async {
    final List<String> ran = <String>[];
    final BackgroundSyncRunner runner = BackgroundSyncRunner(
      steps: <BackgroundSyncStep>[
        BackgroundSyncStep('mail', () async {
          throw StateError('secret subject line');
        }),
        BackgroundSyncStep('events', () async => ran.add('events')),
      ],
    );

    final BackgroundSyncResult result = await runner.run();

    expect(ran, <String>['events']);
    expect(result.failed, <String>['mail']);
    expect(result.completed, <String>['events']);
    expect(result.toString(), isNot(contains('secret')));
  });

  test('stops at the deadline and leaves the remaining steps unstarted', () {
    fakeAsync((FakeAsync async) {
      final List<String> started = <String>[];
      final BackgroundSyncRunner runner = BackgroundSyncRunner(
        deadline: const Duration(minutes: 5),
        steps: <BackgroundSyncStep>[
          BackgroundSyncStep('mail', () async {
            started.add('mail');
            await Completer<void>().future; // never finishes
          }),
          BackgroundSyncStep('events', () async => started.add('events')),
        ],
      );
      BackgroundSyncResult? result;
      unawaited(runner.run().then((BackgroundSyncResult r) => result = r));

      async.elapse(const Duration(minutes: 6));

      expect(result?.timedOut, isTrue);
      expect(started, <String>['mail']);
      expect(result?.completed, isEmpty);
      expect(result?.notStarted, <String>['events']);
    });
  });

  test('an empty step list is a completed run', () async {
    final BackgroundSyncResult result = await BackgroundSyncRunner(
      steps: const <BackgroundSyncStep>[],
    ).run();

    expect(result.timedOut, isFalse);
    expect(result.completed, isEmpty);
  });
}
