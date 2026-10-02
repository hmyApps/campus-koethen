// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/moodle/presentation/moodle_course_refresh_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces concurrent refreshes and exposes completion', () async {
    final MoodleCourseRefreshController controller =
        MoodleCourseRefreshController();
    addTearDown(controller.dispose);
    final Completer<void> pending = Completer<void>();
    int calls = 0;

    final Future<void> first = controller.run(() {
      calls++;
      return pending.future;
    });
    await controller.run(() async => calls++);

    expect(controller.refreshing, isTrue);
    expect(calls, 1);
    pending.complete();
    await first;
    expect(controller.refreshing, isFalse);
    expect(controller.error, isNull);
  });

  test('retains a refresh failure for the warning banner', () async {
    final MoodleCourseRefreshController controller =
        MoodleCourseRefreshController();
    addTearDown(controller.dispose);
    final StateError failure = StateError('offline');

    await controller.run(() async => throw failure);

    expect(controller.refreshing, isFalse);
    expect(controller.error, same(failure));
  });

  test('a refresh may finish after its screen was disposed', () async {
    final MoodleCourseRefreshController controller =
        MoodleCourseRefreshController();
    final Completer<void> pending = Completer<void>();
    final Future<void> refresh = controller.run(() => pending.future);

    controller.dispose();
    pending.complete();

    await expectLater(refresh, completes);
  });
}
