// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:campus_koethen/features/notifications/application/moodle_deadline_candidates.dart';
import 'package:campus_koethen/features/notifications/application/notification_planner.dart';
import 'package:campus_koethen/features/notifications/domain/delivery_window.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/domain/notification_plan.dart';
import 'package:campus_koethen/features/notifications/domain/notification_preferences.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:campus_koethen/features/notifications/domain/planned_notification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The planner is a pure function, so every rule of ADR-0001 § 7.3–7.5 is
/// checkable here — including the two that are impossible to reproduce on a
/// device on demand: a time zone change and a daylight-saving change.

late tz.Location berlin;
late tz.Location sydney;

NotificationPreferences get allOn =>
    const NotificationPreferences(optedIn: true);

NotificationRequest event({
  required String target,
  required DateTime startsAt,
  String title = 'Campus event',
}) => NotificationRequest(
  category: NotificationCategory.eventReminder,
  target: target,
  // The 24-hour lead of P3 is an absolute duration and is applied by the
  // contributor; the planner receives the resulting instant.
  trigger: AbsoluteTrigger(startsAt.subtract(const Duration(hours: 24))),
  title: title,
  body: 'Tomorrow',
);

NotificationRequest summary(DateTime day) => NotificationRequest(
  category: NotificationCategory.dailySummary,
  target:
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}',
  trigger: LocalTimeTrigger(day: day, hour: 8),
  title: 'Good morning',
  body: '3 lectures today',
  visibility: NotificationVisibility.neutral,
);

class _MoodleCopy implements MoodleDeadlineReminderCopy {
  const _MoodleCopy();

  @override
  String get title => 'Moodle deadline approaching';

  @override
  String get body => 'Open Moodle to view the deadline.';
}

NotificationPlan planIn(
  tz.Location location,
  tz.TZDateTime now,
  List<NotificationRequest> candidates, {
  NotificationPreferences? preferences,
  NotificationPermissionStatus permission =
      NotificationPermissionStatus.granted,
  int budget = kMaxScheduledNotifications,
}) => planNotifications(
  candidates: candidates,
  preferences: preferences ?? allOn,
  permission: permission,
  now: now,
  budget: budget,
);

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    berlin = tz.getLocation('Europe/Berlin');
    sydney = tz.getLocation('Australia/Sydney');
  });

  group('the delivery window (P7)', () {
    test('a desired moment inside the window is kept exactly', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1, 9);
      // Starts 2026-09-03 16:00 → reminder 2026-09-02 16:00, inside 07:00–20:00.
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(
          target: 'savedEvent:calendar:4711',
          startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16),
        ),
      ]);

      expect(plan.notifications, hasLength(1));
      expect(
        plan.notifications.single.scheduledAt,
        tz.TZDateTime(berlin, 2026, 9, 2, 16),
      );
    });

    test('a moment before 07:00 moves to 07:00 of the same day', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1, 9);
      // Starts 2026-09-03 05:30 → desired 2026-09-02 05:30, too early.
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(
          target: 'timetable:1',
          startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 5, 30),
        ),
      ]);

      expect(
        plan.notifications.single.scheduledAt,
        tz.TZDateTime(berlin, 2026, 9, 2, 7),
      );
    });

    test('a moment after 20:00 moves to 07:00 of the NEXT day', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1, 9);
      // Starts 2026-09-03 22:30 → desired 2026-09-02 22:30, too late.
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(
          target: 'publicCalendar:stura:9',
          startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 22, 30),
        ),
      ]);

      expect(
        plan.notifications.single.scheduledAt,
        tz.TZDateTime(berlin, 2026, 9, 3, 7),
      );
    });

    test('a shifted reminder still lands before the event it is about', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final tz.TZDateTime start = tz.TZDateTime(berlin, 2026, 9, 3, 23, 59);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(target: 'savedEvent:x', startsAt: start),
      ]);

      expect(plan.notifications.single.scheduledAt.isBefore(start), isTrue);
    });

    test('07:00:00 and 20:00:00 are inside the window', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(target: 'a', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 7)),
        event(target: 'b', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 20)),
      ]);

      expect(
        plan.notifications.map((PlannedNotification n) => n.scheduledAt),
        <tz.TZDateTime>[
          tz.TZDateTime(berlin, 2026, 9, 2, 7),
          tz.TZDateTime(berlin, 2026, 9, 2, 20),
        ],
      );
    });

    test('one second past 20:00 is already outside', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(
          target: 'a',
          startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 20, 0, 1),
        ),
      ]);

      expect(
        plan.notifications.single.scheduledAt,
        tz.TZDateTime(berlin, 2026, 9, 3, 7),
      );
    });

    test('the chosen overview time is allowed outside the delivery window', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        NotificationRequest(
          category: NotificationCategory.dailySummary,
          target: '2026-09-02',
          trigger: LocalTimeTrigger(day: DateTime(2026, 9, 2), hour: 4),
          title: 'Too early',
          body: 'Nobody asked for this',
        ),
      ]);

      expect(plan.notifications.single.scheduledAt.hour, 4);
      expect(
        plan.diagnostics.droppedFor(
          NotificationDropReason.outsideDeliveryWindow,
        ),
        0,
      );
    });
  });

  group('DeliveryWindow.shiftIntoWindowBefore', () {
    tz.TZDateTime b(int month, int day, int hour, [int minute = 0]) =>
        tz.TZDateTime(berlin, 2026, month, day, hour, minute);

    test('a moment inside the window and before the target is kept', () {
      expect(
        DeliveryWindow.shiftIntoWindowBefore(b(9, 2, 16), b(9, 3, 16)),
        b(9, 2, 16),
      );
    });

    test('the regular shift is kept while it still precedes the target', () {
      // 05:30 → 07:00, still before a 09:00 target.
      expect(
        DeliveryWindow.shiftIntoWindowBefore(b(9, 3, 5, 30), b(9, 3, 9)),
        b(9, 3, 7),
      );
      // 22:00 → 07:00 next day, still before a 12:00 target.
      expect(
        DeliveryWindow.shiftIntoWindowBefore(b(9, 2, 22), b(9, 3, 12)),
        b(9, 3, 7),
      );
    });

    test('a target after 20:00 falls back to 20:00 the same evening', () {
      expect(
        DeliveryWindow.shiftIntoWindowBefore(b(9, 3, 22, 59), b(9, 3, 23, 59)),
        b(9, 3, 20),
      );
    });

    test('a target at or before 20:00 falls back to the evening before', () {
      expect(
        DeliveryWindow.shiftIntoWindowBefore(b(9, 3, 6, 45), b(9, 3, 7)),
        b(9, 2, 20),
      );
      // Exactly 20:00 is not strictly before a 20:00 target.
      expect(
        DeliveryWindow.shiftIntoWindowBefore(b(9, 3, 20, 0), b(9, 3, 20)),
        b(9, 2, 20),
      );
    });

    test('the fallback is 20:00 on the dial on a daylight-saving day', () {
      // 2026-10-25: the clocks go back at 03:00. 2027-03-28: forward at 02:00.
      for (final (int year, int month, int day) in <(int, int, int)>[
        (2026, 10, 25),
        (2027, 3, 28),
      ]) {
        final tz.TZDateTime target = tz.TZDateTime(
          berlin,
          year,
          month,
          day,
          23,
          30,
        );
        final tz.TZDateTime out = DeliveryWindow.shiftIntoWindowBefore(
          target.subtract(const Duration(minutes: 30)),
          target,
        );
        expect(out, tz.TZDateTime(berlin, year, month, day, 20));
        expect(out.hour, 20);
      }
    });

    test(
      'a target given as a UTC instant is read in the zone of the moment',
      () {
        // 21:30 UTC is 23:30 in Berlin (CEST).
        final tz.TZDateTime out = DeliveryWindow.shiftIntoWindowBefore(
          b(9, 3, 22, 30),
          DateTime.utc(2026, 9, 3, 21, 30),
        );
        expect(out, b(9, 3, 20));
        expect(out.location, berlin);
      },
    );
  });

  group('a shifted reminder never lands on or after its target (F-02)', () {
    List<PlannedNotification> moodleIn(
      tz.Location location,
      tz.TZDateTime now,
      DateTime dueAt,
      Duration lead,
    ) => planIn(
      location,
      now,
      moodleDeadlineRequests(
        deadlines: <MoodleDeadline>[
          MoodleDeadline(id: 7, title: 'Demo-Abgabe', dueAt: dueAt),
        ],
        now: now,
        lead: lead,
        copy: const _MoodleCopy(),
      ),
    ).notifications;

    test('a deadline at 23:59 with a one-hour lead is reminded at 20:00 the '
        'same evening, not at 07:00 after it has passed', () {
      final tz.TZDateTime due = tz.TZDateTime(berlin, 2026, 9, 3, 23, 59);

      final List<PlannedNotification> out = moodleIn(
        berlin,
        tz.TZDateTime(berlin, 2026, 9, 1, 9),
        due,
        const Duration(hours: 1),
      );

      expect(out.single.category, NotificationCategory.moodleDeadline);
      expect(out.single.scheduledAt, tz.TZDateTime(berlin, 2026, 9, 3, 20));
      expect(out.single.scheduledAt.isBefore(due), isTrue);
    });

    test('a deadline before 07:00 is reminded the evening before', () {
      final tz.TZDateTime due = tz.TZDateTime(berlin, 2026, 9, 3, 6, 30);

      final List<PlannedNotification> out = moodleIn(
        berlin,
        tz.TZDateTime(berlin, 2026, 9, 1, 9),
        due,
        const Duration(minutes: 15),
      );

      expect(out.single.scheduledAt, tz.TZDateTime(berlin, 2026, 9, 2, 20));
    });

    test('every quarter hour of a day, every lead, both daylight-saving '
        'changes: inside the window and strictly before the deadline', () {
      const List<Duration> leads = <Duration>[
        Duration(minutes: 15),
        Duration(hours: 1),
        Duration(hours: 6),
        Duration(days: 1),
        Duration(days: 2),
        Duration(days: 7),
      ];
      for (final DateTime day in <DateTime>[
        DateTime(2026, 9, 15),
        DateTime(2026, 10, 25),
        DateTime(2027, 3, 28),
      ]) {
        final tz.TZDateTime now = tz.TZDateTime(
          berlin,
          day.year,
          day.month,
          day.day - 10,
        );
        for (int minute = 0; minute < 24 * 60; minute += 15) {
          final tz.TZDateTime due = tz.TZDateTime(
            berlin,
            day.year,
            day.month,
            day.day,
            0,
            minute,
          );
          for (final Duration lead in leads) {
            for (final PlannedNotification n in moodleIn(
              berlin,
              now,
              due,
              lead,
            )) {
              expect(
                n.scheduledAt.isBefore(due),
                isTrue,
                reason: 'due $due, lead $lead → ${n.scheduledAt}',
              );
              expect(
                DeliveryWindow.allows(n.scheduledAt),
                isTrue,
                reason: 'due $due, lead $lead → ${n.scheduledAt}',
              );
            }
          }
        }
      }
    });
  });

  group('time zones and daylight saving', () {
    test('a wall-clock time stays on the dial across the DST change', () {
      // Germany moves the clocks on 2026-10-25 at 03:00 back to 02:00.
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 10, 20);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        summary(DateTime(2026, 10, 24)),
        summary(DateTime(2026, 10, 25)),
        summary(DateTime(2026, 10, 26)),
      ]);

      expect(
        plan.notifications.map((PlannedNotification n) => n.scheduledAt.hour),
        <int>[8, 8, 8],
        reason: 'the daily overview is 08:00 on the dial, every day',
      );
      // And the two consecutive mornings really are 25 hours apart, which is
      // what "the same wall-clock time" means on that particular night.
      final Duration across = plan.notifications[2].scheduledAt.difference(
        plan.notifications[1].scheduledAt,
      );
      expect(across, const Duration(hours: 24));
      final Duration overNight = plan.notifications[1].scheduledAt.difference(
        plan.notifications[0].scheduledAt,
      );
      expect(overNight, const Duration(hours: 25));
    });

    test('the 24-hour lead is an absolute duration and may move the dial by an '
        'hour on the changeover day', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 10, 20);
      // The event starts 2026-10-25 12:00, after the clocks went back that
      // night. Exactly 24 hours earlier is 13:00 on the 24th, not 12:00:
      // the night in between has 25 hours, and P3 says "exactly 24 hours",
      // not "the same time the day before".
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(
          target: 'savedEvent:dst',
          startsAt: tz.TZDateTime(berlin, 2026, 10, 25, 12),
        ),
      ]);

      expect(
        plan.notifications.single.scheduledAt,
        tz.TZDateTime(berlin, 2026, 10, 24, 13),
      );
    });

    test('the same absolute event is planned in the device zone', () {
      final DateTime start = DateTime.utc(2026, 9, 3, 12);
      final NotificationPlan inBerlin = planIn(
        berlin,
        tz.TZDateTime(berlin, 2026, 9, 1),
        <NotificationRequest>[event(target: 'a', startsAt: start)],
      );
      final NotificationPlan inSydney = planIn(
        sydney,
        tz.TZDateTime(sydney, 2026, 9, 1),
        <NotificationRequest>[event(target: 'a', startsAt: start)],
      );

      // Same instant, different dial — and Sydney's 20:00 UTC+10 falls outside
      // the window, so it is moved to the next 07:00.
      expect(
        inBerlin.notifications.single.scheduledAt.hour,
        14,
        reason: '2026-09-02 12:00 UTC is 14:00 in Berlin (CEST)',
      );
      expect(inSydney.notifications.single.scheduledAt.hour, 7);
    });

    test('a wall-clock time is planned in the device zone, not in UTC', () {
      final NotificationPlan plan = planIn(
        sydney,
        tz.TZDateTime(sydney, 2026, 9, 1),
        <NotificationRequest>[summary(DateTime(2026, 9, 2))],
      );

      expect(plan.notifications.single.scheduledAt.location, sydney);
      expect(plan.notifications.single.scheduledAt.hour, 8);
    });
  });

  group('what never reaches the operating system', () {
    test('nothing at all without the opt-in', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(target: 'a', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16)),
      ], preferences: const NotificationPreferences());

      expect(plan.notifications, isEmpty);
      expect(
        plan.diagnostics.droppedFor(NotificationDropReason.notPermitted),
        1,
      );
    });

    test('nothing at all once the permission is gone', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(target: 'a', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16)),
      ], permission: NotificationPermissionStatus.denied);

      expect(plan.notifications, isEmpty);
    });

    test('a switched-off category, while the others carry on', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final NotificationPlan plan = planIn(
        berlin,
        now,
        <NotificationRequest>[
          event(target: 'a', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16)),
          summary(DateTime(2026, 9, 2)),
        ],
        preferences: const NotificationPreferences(
          optedIn: true,
          disabledCategories: <NotificationCategory>{
            NotificationCategory.eventReminder,
          },
        ),
      );

      expect(
        plan.notifications.map((PlannedNotification n) => n.category),
        <NotificationCategory>[NotificationCategory.dailySummary],
      );
      expect(
        plan.diagnostics.droppedFor(NotificationDropReason.categoryDisabled),
        1,
      );
    });

    test('a moment already past — missed reminders are never caught up', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 2, 18);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        // Reminder would have been 2026-09-02 16:00, two hours ago.
        event(target: 'a', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16)),
        event(target: 'b', startsAt: tz.TZDateTime(berlin, 2026, 9, 4, 16)),
      ]);

      expect(plan.notifications.map((PlannedNotification n) => n.key), <String>[
        'n1:b',
      ]);
      expect(plan.diagnostics.droppedFor(NotificationDropReason.inThePast), 1);
    });

    test('exactly "now" is already past', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 2, 16);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(target: 'a', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16)),
      ]);

      expect(plan.notifications, isEmpty);
    });

    test('a second candidate with the same key — one hint per subject', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        event(
          target: 'savedEvent:calendar:1',
          startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16),
          title: 'First',
        ),
        event(
          target: 'savedEvent:calendar:1',
          startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 18),
          title: 'Second',
        ),
      ]);

      expect(plan.notifications, hasLength(1));
      expect(plan.notifications.single.title, 'First');
      expect(
        plan.diagnostics.droppedFor(NotificationDropReason.duplicateKey),
        1,
      );
    });
  });

  group('budget and ordering (§ 7.5)', () {
    test('the earliest entries survive a full budget', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final List<NotificationRequest> many = <NotificationRequest>[
        for (int day = 20; day >= 3; day--)
          event(
            target: 'e$day',
            startsAt: tz.TZDateTime(berlin, 2026, 9, day, 16),
          ),
      ];

      final NotificationPlan plan = planIn(berlin, now, many, budget: 3);

      expect(plan.notifications.map((PlannedNotification n) => n.key), <String>[
        'n1:e3',
        'n1:e4',
        'n1:e5',
      ]);
      expect(plan.diagnostics.budgetExhausted, isTrue);
      expect(
        plan.diagnostics.droppedFor(NotificationDropReason.budgetExhausted),
        15,
      );
    });

    test('an exhausted budget is a counter, never a silent truncation', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        for (int day = 3; day < 8; day++)
          event(
            target: 'e$day',
            startsAt: tz.TZDateTime(berlin, 2026, 9, day, 16),
          ),
      ], budget: 2);

      expect(plan.diagnostics.toLogLine(), contains('budgetExhausted=3'));
      expect(plan.diagnostics.scheduledCount, 2);
      expect(plan.diagnostics.candidateCount, 5);
    });

    test(
      'entries due at the same instant are ordered by category, then by key',
      () {
        final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
        final DateTime day = DateTime(2026, 9, 2);
        final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
          NotificationRequest(
            category: NotificationCategory.canteenFavourite,
            target: 'mensa:2026-09-02',
            trigger: LocalTimeTrigger(day: day, hour: 8),
            title: 'Canteen',
            body: 'Spaetzle',
          ),
          summary(day),
          event(target: 'zzz', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 8)),
          event(target: 'aaa', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 8)),
        ]);

        expect(
          plan.notifications.map((PlannedNotification n) => n.key),
          <String>['n1:aaa', 'n1:zzz', 'n2:2026-09-02', 'n3:mensa:2026-09-02'],
        );
      },
    );

    test('the same input always produces the same plan', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 1);
      List<NotificationRequest> candidates() => <NotificationRequest>[
        summary(DateTime(2026, 9, 2)),
        event(target: 'b', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16)),
        event(target: 'a', startsAt: tz.TZDateTime(berlin, 2026, 9, 3, 16)),
      ];

      expect(
        planIn(berlin, now, candidates()),
        planIn(berlin, now, candidates().reversed.toList()),
      );
    });

    test('past entries do not occupy a budget slot', () {
      final tz.TZDateTime now = tz.TZDateTime(berlin, 2026, 9, 10);
      final NotificationPlan plan = planIn(berlin, now, <NotificationRequest>[
        for (int day = 3; day < 9; day++)
          event(
            target: 'past$day',
            startsAt: tz.TZDateTime(berlin, 2026, 9, day, 16),
          ),
        event(
          target: 'future',
          startsAt: tz.TZDateTime(berlin, 2026, 9, 20, 16),
        ),
      ], budget: 1);

      expect(plan.notifications.single.key, 'n1:future');
      expect(plan.diagnostics.budgetExhausted, isFalse);
    });
  });

  group('identity (§ 7.6)', () {
    test('the key is the source identity, not a second scheme', () {
      final NotificationRequest request = event(
        target: 'savedEvent:calendar:4711',
        startsAt: DateTime(2026, 9, 3, 16),
      );
      expect(request.key, 'n1:savedEvent:calendar:4711');
      expect(request.payload.target, 'savedEvent:calendar:4711');
    });

    test('the system id is deterministic, positive and fits 31 bits', () {
      for (final String key in <String>[
        'n1:savedEvent:calendar:4711',
        'n2:2026-09-03',
        'n3:mensa-fasanerieallee:2026-09-03',
        '',
        'ä' * 500,
      ]) {
        final int id = notificationSystemId(key);
        expect(id, notificationSystemId(key));
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7fffffff));
      }
    });

    test('different keys get different ids for the three real shapes', () {
      final Set<int> ids = <String>{
        'n1:savedEvent:calendar:4711',
        'n2:2026-09-03',
        'n3:mensa-fasanerieallee:2026-09-03',
      }.map(notificationSystemId).toSet();
      expect(ids, hasLength(3));
    });
  });
}
