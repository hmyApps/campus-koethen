// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/requests/presentation/submission_polling_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('polls on its interval and stops with the screen', () {
    fakeAsync((FakeAsync time) {
      int polls = 0;
      final SubmissionPollingController controller =
          SubmissionPollingController(
            interval: const Duration(minutes: 1),
            onPoll: () async => polls++,
          );

      controller.start();
      time.elapse(const Duration(minutes: 2));
      expect(polls, 2);
      controller.dispose();
      time.elapse(const Duration(minutes: 2));
      expect(polls, 2);
    });
  });

  test('rate-limit pause resumes only after the requested duration', () {
    fakeAsync((FakeAsync time) {
      int polls = 0;
      final SubmissionPollingController controller =
          SubmissionPollingController(
            interval: const Duration(minutes: 1),
            onPoll: () async => polls++,
          );
      addTearDown(controller.dispose);

      controller.start();
      controller.pauseFor(const Duration(minutes: 3));
      time.elapse(const Duration(minutes: 3, seconds: 59));
      expect(polls, 0);
      time.elapse(const Duration(seconds: 1));
      expect(polls, 1);
    });
  });
}
