// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/notifications/application/notification_scheduler.dart';
import 'package:campus_koethen/features/notifications/domain/immediate_notification.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_payload.dart';
import 'package:campus_koethen/features/notifications/domain/notification_plan.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:campus_koethen/features/notifications/domain/planned_notification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../support/fake_notification_gateway.dart';

late tz.Location berlin;

PlannedNotification entry(String target, {int hour = 9}) => PlannedNotification(
  key: 'n1:$target',
  category: NotificationCategory.eventReminder,
  scheduledAt: tz.TZDateTime(berlin, 2026, 9, 3, hour),
  title: 'Campus Sommerfest',
  body: 'Tomorrow at 4 PM',
  payload: NotificationPayload(
    category: NotificationCategory.eventReminder,
    target: target,
  ),
  visibility: NotificationVisibility.publicContent,
);

NotificationPlan planOf(List<PlannedNotification> entries) => NotificationPlan(
  notifications: entries,
  diagnostics: NotificationPlanDiagnostics(
    candidateCount: entries.length,
    scheduledCount: entries.length,
    scheduledByCategory: const <NotificationCategory, int>{},
    dropped: const <NotificationDropReason, int>{},
    budget: kMaxScheduledNotifications,
  ),
);

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    berlin = tz.getLocation('Europe/Berlin');
  });

  test('a run clears everything before it registers anything', () async {
    final FakeNotificationGateway gateway = FakeNotificationGateway();
    final NotificationScheduler scheduler = NotificationScheduler(gateway);

    await scheduler.apply(
      planOf(<PlannedNotification>[entry('a'), entry('b')]),
    );

    expect(gateway.calls, <String>[
      'cancelAllPending',
      'schedule:n1:a',
      'schedule:n1:b',
    ]);
  });

  test('delivered notifications stay in the shade across re-plans and an '
      'empty plan (F-01)', () async {
    final FakeNotificationGateway gateway = FakeNotificationGateway();
    final NotificationScheduler scheduler = NotificationScheduler(gateway);

    await scheduler.apply(planOf(<PlannedNotification>[entry('a')]));
    // The reminder fires; then an immediate mail hint arrives.
    gateway.deliverPending('n1:a');
    await gateway.showNow(
      const ImmediateNotification(
        key: 'n6:4711',
        category: NotificationCategory.newMail,
        title: 'Neue E-Mail',
        body: 'Eine neue Nachricht ist eingegangen.',
        payload: NotificationPayload(
          category: NotificationCategory.newMail,
          target: '4711',
        ),
        visibility: NotificationVisibility.neutral,
      ),
    );

    // The reader opens the app: a resume re-plans, then notifications are
    // switched off and the plan becomes empty.
    await scheduler.apply(planOf(<PlannedNotification>[entry('b')]));
    await scheduler.apply(const NotificationPlan.empty());
    expect(await scheduler.cancelAllPending(), isTrue);

    expect(gateway.pending, isEmpty);
    expect(gateway.delivered, <String>['n1:a', 'n6:4711']);
  });

  test('planning the same state twice leaves no duplicates', () async {
    final FakeNotificationGateway gateway = FakeNotificationGateway();
    final NotificationScheduler scheduler = NotificationScheduler(gateway);
    final NotificationPlan plan = planOf(<PlannedNotification>[
      entry('a'),
      entry('b'),
    ]);

    await scheduler.apply(plan);
    await scheduler.apply(plan);

    expect(gateway.pending.map((PlannedNotification n) => n.key), <String>[
      'n1:a',
      'n1:b',
    ]);
  });

  test(
    'two runs started at once end in exactly one state, never interleaved',
    () async {
      final FakeNotificationGateway gateway = FakeNotificationGateway(
        // Slow enough that an unserialised second run would land in the middle
        // of the first one's scheduling.
        scheduleDelay: const Duration(milliseconds: 5),
      );
      final NotificationScheduler scheduler = NotificationScheduler(gateway);

      final Future<NotificationSyncResult> first = scheduler.apply(
        planOf(<PlannedNotification>[entry('a'), entry('b'), entry('c')]),
      );
      final Future<NotificationSyncResult> second = scheduler.apply(
        planOf(<PlannedNotification>[entry('x'), entry('y')]),
      );
      await Future.wait(<Future<NotificationSyncResult>>[first, second]);

      expect(gateway.pending.map((PlannedNotification n) => n.key), <String>[
        'n1:x',
        'n1:y',
      ]);
      // The second cancelAllPending comes after the first run finished scheduling —
      // that is what "serialised" means, and it is invisible in the end state.
      expect(gateway.calls, <String>[
        'cancelAllPending',
        'schedule:n1:a',
        'schedule:n1:b',
        'schedule:n1:c',
        'cancelAllPending',
        'schedule:n1:x',
        'schedule:n1:y',
      ]);
    },
  );

  test(
    'an empty plan clears the pending entries and schedules nothing',
    () async {
      final FakeNotificationGateway gateway = FakeNotificationGateway();
      final NotificationScheduler scheduler = NotificationScheduler(gateway);

      await scheduler.apply(planOf(<PlannedNotification>[entry('a')]));
      final NotificationSyncResult result = await scheduler.apply(
        const NotificationPlan.empty(),
      );

      expect(gateway.pending, isEmpty);
      expect(result.cancelledOnly, isTrue);
      expect(
        gateway.calls.where((String c) => c == 'cancelAllPending'),
        hasLength(2),
      );
    },
  );

  test('one entry the platform refuses does not cost the rest', () async {
    final FakeNotificationGateway gateway = FakeNotificationGateway(
      failScheduleForKeys: <String>{'n1:b'},
    );
    final NotificationScheduler scheduler = NotificationScheduler(gateway);

    final NotificationSyncResult result = await scheduler.apply(
      planOf(<PlannedNotification>[entry('a'), entry('b'), entry('c')]),
    );

    expect(result.scheduled, 2);
    expect(result.failed, 1);
    expect(gateway.pending.map((PlannedNotification n) => n.key), <String>[
      'n1:a',
      'n1:c',
    ]);
  });

  test(
    'a failed cancellation keeps the old state and skips the replacement',
    () async {
      final FakeNotificationGateway gateway = FakeNotificationGateway();
      final NotificationScheduler scheduler = NotificationScheduler(gateway);
      await scheduler.apply(planOf(<PlannedNotification>[entry('old')]));

      gateway.failCancellation = true;
      final NotificationSyncResult failed = await scheduler.apply(
        planOf(<PlannedNotification>[entry('new')]),
      );

      expect(failed.cancellationFailed, isTrue);
      expect(failed.scheduled, 0);
      expect(gateway.pending.map((PlannedNotification n) => n.key), <String>[
        'n1:old',
      ]);
      expect(gateway.calls, <String>[
        'cancelAllPending',
        'schedule:n1:old',
        'cancelAllPending',
      ]);

      gateway.failCancellation = false;
      final NotificationSyncResult recovered = await scheduler.apply(
        planOf(<PlannedNotification>[entry('new')]),
      );
      expect(recovered.scheduled, 1);
      expect(gateway.pending.single.key, 'n1:new');
    },
  );

  test('a failed run does not stop the queue', () async {
    final FakeNotificationGateway gateway = FakeNotificationGateway();
    final NotificationScheduler scheduler = NotificationScheduler(gateway);

    // cancelAllPending on the fake never throws, so the failure is provoked through a
    // schedule call — and the run after it must still complete.
    gateway.failScheduleForKeys = <String>{'n1:a'};
    await scheduler.apply(planOf(<PlannedNotification>[entry('a')]));
    gateway.failScheduleForKeys = <String>{};
    final NotificationSyncResult after = await scheduler.apply(
      planOf(<PlannedNotification>[entry('z')]),
    );

    expect(after.scheduled, 1);
    expect(gateway.pending.single.key, 'n1:z');
  });

  test('the log line carries counts, never a title or a key', () async {
    final FakeNotificationGateway gateway = FakeNotificationGateway();
    final NotificationScheduler scheduler = NotificationScheduler(gateway);

    final NotificationSyncResult result = await scheduler.apply(
      planOf(<PlannedNotification>[entry('savedEvent:calendar:4711')]),
    );

    expect(result.toLogLine(), isNot(contains('Sommerfest')));
    expect(result.toLogLine(), isNot(contains('4711')));
    expect(result.toLogLine(), contains('1/1'));
  });
}
