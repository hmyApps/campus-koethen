// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/notifications/application/event_reminder_candidates.dart';
import 'package:campus_koethen/features/notifications/application/notification_planner.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/domain/notification_plan.dart';
import 'package:campus_koethen/features/notifications/domain/notification_preferences.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:campus_koethen/features/notifications/domain/planned_notification.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// N1 · `event.reminder` — the rule of ADR-0001 § 7.3, checked as a pure
/// function.
///
/// The candidate builder and the planner are tested *together* here wherever
/// the answer depends on both. That is deliberate: the builder decides which
/// events exist and what a reminder says, the planner decides when it is
/// delivered, and every acceptance criterion of LEVIORA-166 is a statement
/// about the pair. Testing only one of them would leave exactly the seam
/// where a wrong reminder can appear.

late tz.Location berlin;
late tz.Location sydney;

/// Names the two parts of the text that must vary with the delivery day, so a
/// test can assert "morgen" versus "heute" without any localisation loaded.
class _TestCopy implements EventReminderCopy {
  const _TestCopy();

  @override
  String title(CalendarEntry entry, {required bool onEventDay}) =>
      '${onEventDay ? 'today' : 'tomorrow'}: ${entry.title}';

  @override
  String body(CalendarEntry entry, {required bool onEventDay}) {
    final String when = entry.allDay
        ? '${onEventDay ? 'today' : 'tomorrow'}, all day'
        : '${onEventDay ? 'today' : 'tomorrow'} at ${entry.start.toLocal()}';
    final String? place = entry.location;
    return place == null ? '$when.' : '$when, $place.';
  }
}

CalendarEntry publicEvent({
  String id = 'publicCalendar:hsa:4711',
  String title = 'Campus Sommerfest 2026',
  required DateTime start,
  DateTime? end,
  bool allDay = false,
  bool isCancelled = false,
  String? location,
}) => CalendarEntry(
  id: id,
  source: CalendarSource.publicCalendar,
  title: title,
  start: start,
  end: end,
  allDay: allDay,
  isCancelled: isCancelled,
  location: location,
  calendarSlug: 'hsa',
);

CalendarEntry savedEvent({
  String id = 'savedEvent:calendar:4711',
  String title = 'Campus Sommerfest 2026',
  required DateTime start,
}) => CalendarEntry(
  id: id,
  source: CalendarSource.savedEvents,
  title: title,
  start: start,
);

/// `2026-07-22 09:00` in [location], as an absolute instant.
tz.TZDateTime at(
  tz.Location location,
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
]) => tz.TZDateTime(location, year, month, day, hour, minute);

List<NotificationRequest> requestsIn(
  tz.Location location,
  tz.TZDateTime now,
  List<CalendarEntry> entries,
) => eventReminderRequests(entries: entries, now: now, copy: const _TestCopy());

/// The builder and the planner as one answer: what the operating system would
/// actually be asked to deliver.
List<PlannedNotification> planned(
  tz.Location location,
  tz.TZDateTime now,
  List<CalendarEntry> entries, {
  NotificationPreferences preferences = const NotificationPreferences(
    optedIn: true,
  ),
  NotificationPermissionStatus permission =
      NotificationPermissionStatus.granted,
}) {
  final NotificationPlan plan = planNotifications(
    candidates: requestsIn(location, now, entries),
    preferences: preferences,
    permission: permission,
    now: now,
  );
  return plan.notifications;
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    berlin = tz.getLocation('Europe/Berlin');
    sydney = tz.getLocation('Australia/Sydney');
  });

  group('exactly 24 hours before (P3)', () {
    test('an event inside the window is reminded about 24 hours earlier', () {
      final tz.TZDateTime start = at(berlin, 2026, 7, 22, 16);

      final List<PlannedNotification> out = planned(
        berlin,
        at(berlin, 2026, 7, 1, 12),
        <CalendarEntry>[publicEvent(start: start)],
      );

      expect(out, hasLength(1));
      expect(out.single.scheduledAt, at(berlin, 2026, 7, 21, 16));
      expect(out.single.category, NotificationCategory.eventReminder);
    });

    test('the lead is an absolute duration, not the same time yesterday', () {
      // The night the clocks go forward in Berlin: 02:00 becomes 03:00, so
      // 24 hours before 12:00 on the 29th is 11:00 on the 28th, not 12:00.
      final tz.TZDateTime start = at(berlin, 2026, 3, 29, 12);

      final List<PlannedNotification> out = planned(
        berlin,
        at(berlin, 2026, 3, 1, 12),
        <CalendarEntry>[publicEvent(start: start)],
      );

      expect(out.single.scheduledAt, at(berlin, 2026, 3, 28, 11));
      expect(
        start.difference(out.single.scheduledAt),
        const Duration(hours: 24),
      );
    });

    test('the 24-hour mark is the same instant in every zone', () {
      // The lead is absolute, so the *desired* moment does not depend on where
      // the phone is. What follows it does: the 07:00–20:00 window is local
      // time, so the same event can be delivered at a different instant in
      // Sydney than in Berlin — that is the window working, not the lead
      // drifting. Both halves are asserted here so neither can be changed
      // silently.
      final DateTime start = DateTime.utc(2026, 7, 22, 14);
      final DateTime expectedDesired = DateTime.utc(2026, 7, 21, 14);

      for (final tz.Location zone in <tz.Location>[berlin, sydney]) {
        final NotificationRequest request = requestsIn(
          zone,
          at(zone, 2026, 7, 1, 12),
          <CalendarEntry>[publicEvent(start: start)],
        ).single;
        expect(
          (request.trigger as AbsoluteTrigger).instant.toUtc(),
          expectedDesired,
          reason: '$zone',
        );
      }

      // 14:00 UTC is 16:00 in Berlin — inside the window, so nothing moves.
      expect(
        planned(berlin, at(berlin, 2026, 7, 1, 12), <CalendarEntry>[
          publicEvent(start: start),
        ]).single.scheduledAt.toUtc(),
        expectedDesired,
      );
      // In Sydney the same mark falls at 00:00 local, and is moved to 07:00.
      final PlannedNotification inSydney = planned(
        sydney,
        at(sydney, 2026, 7, 1, 12),
        <CalendarEntry>[publicEvent(start: start)],
      ).single;
      expect(inSydney.scheduledAt.hour, 7);
      expect(
        inSydney.scheduledAt.isBefore(tz.TZDateTime.from(start, sydney)),
        isTrue,
      );
    });
  });

  group('the delivery window, 07:00–20:00 (P7, ADR-0001 § 7.4)', () {
    test('before 07:00 moves to 07:00 of the same day, and says tomorrow', () {
      // Event at 06:00 → desired 06:00 the day before → 07:00 that same day,
      // which is still the day BEFORE the event.
      final List<PlannedNotification> out = planned(
        berlin,
        at(berlin, 2026, 7, 1, 12),
        <CalendarEntry>[publicEvent(start: at(berlin, 2026, 7, 22, 6))],
      );

      expect(out.single.scheduledAt, at(berlin, 2026, 7, 21, 7));
      expect(out.single.title, startsWith('tomorrow'));
    });

    test('after 20:00 moves to 07:00 of the next day, and says today', () {
      // Event at 22:00 → desired 22:00 the day before → 07:00 the next day,
      // which is the day OF the event. This is the UX spec's
      // `fallback_window` case.
      final List<PlannedNotification> out = planned(
        berlin,
        at(berlin, 2026, 7, 1, 12),
        <CalendarEntry>[publicEvent(start: at(berlin, 2026, 7, 22, 22))],
      );

      expect(out.single.scheduledAt, at(berlin, 2026, 7, 22, 7));
      expect(out.single.title, startsWith('today'));
      expect(
        out.single.scheduledAt.isBefore(at(berlin, 2026, 7, 22, 22)),
        isTrue,
        reason: 'a shifted reminder must never land after its own event',
      );
    });

    test('both bounds are inclusive and are not shifted', () {
      for (final int hour in <int>[7, 20]) {
        final List<PlannedNotification> out = planned(
          berlin,
          at(berlin, 2026, 7, 1, 12),
          <CalendarEntry>[publicEvent(start: at(berlin, 2026, 7, 22, hour))],
        );
        expect(
          out.single.scheduledAt,
          at(berlin, 2026, 7, 21, hour),
          reason: '$hour:00 is inside the window',
        );
      }
    });

    test('one second past 20:00 is outside and moves to the next 07:00', () {
      final tz.TZDateTime start = tz.TZDateTime(berlin, 2026, 7, 22, 20, 0, 1);

      final List<PlannedNotification> out = planned(
        berlin,
        at(berlin, 2026, 7, 1, 12),
        <CalendarEntry>[publicEvent(start: start)],
      );

      expect(out.single.scheduledAt, at(berlin, 2026, 7, 22, 7));
    });

    test('a shift across a daylight-saving change lands on 07:00 the dial', () {
      // Event at 22:00 on 2026-03-29, the day the clocks went forward that
      // morning. The shift must produce 07:00 local, not 06:00 or 08:00.
      final List<PlannedNotification> out = planned(
        berlin,
        at(berlin, 2026, 3, 1, 12),
        <CalendarEntry>[publicEvent(start: at(berlin, 2026, 3, 29, 22))],
      );

      expect(out.single.scheduledAt.hour, 7);
      expect(out.single.scheduledAt.day, 29);
    });
  });

  group('what never becomes a reminder', () {
    tz.TZDateTime future() => at(berlin, 2026, 7, 22, 16);

    test('a cancelled event', () {
      expect(
        requestsIn(berlin, at(berlin, 2026, 7, 1), <CalendarEntry>[
          publicEvent(start: future(), isCancelled: true),
        ]),
        isEmpty,
      );
    });

    test('lectures and Moodle deadlines never use the event category', () {
      final List<CalendarEntry> notEvents = <CalendarEntry>[
        CalendarEntry(
          id: 'timetable:99',
          source: CalendarSource.timetable,
          title: 'Analysis II',
          start: future(),
        ),
        CalendarEntry(
          id: 'moodle:1234',
          source: CalendarSource.moodle,
          title: 'Übungsblatt 4',
          start: future(),
        ),
      ];

      expect(
        requestsIn(berlin, at(berlin, 2026, 7, 1), notEvents),
        isEmpty,
        reason:
            'Moodle uses its dedicated neutral deadline category; '
            'lectures remain part of the daily overview only',
      );
    });

    test('no payload of this category can ever carry a Moodle identifier', () {
      // The structural half of the same rule: even if a Moodle entry were
      // somehow handed in, nothing about it reaches the operating system.
      final List<NotificationRequest> out =
          requestsIn(berlin, at(berlin, 2026, 7, 1), <CalendarEntry>[
            CalendarEntry(
              id: 'moodle:1234',
              source: CalendarSource.moodle,
              title: 'Übungsblatt 4',
              start: future(),
            ),
          ]);
      expect(out, isEmpty);
    });

    test('an event that has already started', () {
      expect(
        requestsIn(berlin, at(berlin, 2026, 7, 22, 17), <CalendarEntry>[
          publicEvent(start: at(berlin, 2026, 7, 22, 16)),
        ]),
        isEmpty,
      );
    });

    test('an event whose reminder moment has already passed', () {
      // Tomorrow at 16:00, asked today at 17:00: the 24-hour mark was an hour
      // ago. A missed reminder is never caught up (ADR-0001 § 9.4).
      expect(
        requestsIn(berlin, at(berlin, 2026, 7, 21, 17), <CalendarEntry>[
          publicEvent(start: at(berlin, 2026, 7, 22, 16)),
        ]),
        isEmpty,
      );
    });

    test('the switch for this category being off', () {
      final List<PlannedNotification> out = planned(
        berlin,
        at(berlin, 2026, 7, 1),
        <CalendarEntry>[publicEvent(start: future())],
        preferences: const NotificationPreferences(
          optedIn: true,
          disabledCategories: <NotificationCategory>{
            NotificationCategory.eventReminder,
          },
        ),
      );
      expect(out, isEmpty);
    });

    test('no opt-in, and a withdrawn operating-system permission', () {
      expect(
        planned(berlin, at(berlin, 2026, 7, 1), <CalendarEntry>[
          publicEvent(start: future()),
        ], preferences: const NotificationPreferences()),
        isEmpty,
      );
      expect(
        planned(berlin, at(berlin, 2026, 7, 1), <CalendarEntry>[
          publicEvent(start: future()),
        ], permission: NotificationPermissionStatus.denied),
        isEmpty,
      );
    });
  });

  group('all-day events (ADR-0001 § 7.3)', () {
    test('are reminded about, on the 24-hour rule unchanged', () {
      // The worker encodes an all-day date as UTC midnight so no device zone
      // can shift it; 24 hours before that is the previous UTC midnight,
      // which the window then moves to 07:00 local.
      final List<PlannedNotification> out = planned(
        berlin,
        at(berlin, 2026, 7, 1),
        <CalendarEntry>[
          publicEvent(start: DateTime.utc(2026, 7, 22), allDay: true),
        ],
      );

      expect(out, hasLength(1));
      expect(out.single.scheduledAt.hour, 7);
      expect(out.single.body, contains('all day'));
      expect(
        out.single.scheduledAt.isBefore(
          tz.TZDateTime.from(DateTime.utc(2026, 7, 22), berlin),
        ),
        isTrue,
      );
    });
  });

  group('identity, replacing and cancelling (P12, ADR-0001 § 7.6)', () {
    test('the key is n1: plus the CalendarEntry.id, taken over as it is', () {
      final List<NotificationRequest> out = requestsIn(
        berlin,
        at(berlin, 2026, 7, 1),
        <CalendarEntry>[savedEvent(start: at(berlin, 2026, 7, 22, 16))],
      );

      expect(out.single.key, 'n1:savedEvent:calendar:4711');
      expect(
        out.single.payload.toStorage(),
        'v1|event.reminder|savedEvent:calendar:4711',
      );
    });

    test('a moved event keeps its key and only changes its moment', () {
      final CalendarEntry before = publicEvent(
        start: at(berlin, 2026, 7, 22, 16),
      );
      final CalendarEntry after = publicEvent(
        start: at(berlin, 2026, 7, 23, 16),
      );

      final PlannedNotification first = planned(
        berlin,
        at(berlin, 2026, 7, 1),
        <CalendarEntry>[before],
      ).single;
      final PlannedNotification second = planned(
        berlin,
        at(berlin, 2026, 7, 1),
        <CalendarEntry>[after],
      ).single;

      expect(second.key, first.key);
      expect(second.systemId, first.systemId);
      expect(second.scheduledAt, isNot(first.scheduledAt));
    });

    test('a removed or cancelled event simply produces nothing', () {
      // Replacing and cancelling need no mechanism of their own: the whole
      // plan is rebuilt, so an entry that stops being produced stops being
      // registered.
      expect(
        planned(berlin, at(berlin, 2026, 7, 1), const <CalendarEntry>[]),
        isEmpty,
      );
    });

    test('two entries carrying the same id yield exactly one reminder', () {
      final List<PlannedNotification> out =
          planned(berlin, at(berlin, 2026, 7, 1), <CalendarEntry>[
            publicEvent(start: at(berlin, 2026, 7, 22, 16)),
            publicEvent(start: at(berlin, 2026, 7, 22, 16)),
          ]);

      expect(out, hasLength(1));
    });

    test('two different events at the same moment stay two reminders', () {
      // P8: simultaneous hints are never merged into one message.
      final List<PlannedNotification> out =
          planned(berlin, at(berlin, 2026, 7, 1), <CalendarEntry>[
            publicEvent(
              id: 'publicCalendar:hsa:1',
              start: at(berlin, 2026, 7, 22, 16),
            ),
            publicEvent(
              id: 'publicCalendar:hsa:2',
              start: at(berlin, 2026, 7, 22, 16),
            ),
          ]);

      expect(out, hasLength(2));
      expect(out.first.scheduledAt, out.last.scheduledAt);
    });
  });

  group('the text (UX spec § 5.2)', () {
    test('the short title is equivalent in German and English', () {
      final CalendarEntry entry = publicEvent(
        start: at(berlin, 2026, 7, 22, 16),
      );
      final LocalisedEventReminderCopy german = LocalisedEventReminderCopy(
        l10n: lookupAppLocalizations(const Locale('de')),
        localeCode: 'de',
      );
      final LocalisedEventReminderCopy english = LocalisedEventReminderCopy(
        l10n: lookupAppLocalizations(const Locale('en')),
        localeCode: 'en',
      );

      expect(
        german.title(entry, onEventDay: false),
        'Morgen: Campus Sommerfest 2026',
      );
      expect(
        german.title(entry, onEventDay: true),
        'Heute: Campus Sommerfest 2026',
      );
      expect(
        english.title(entry, onEventDay: false),
        'Tomorrow: Campus Sommerfest 2026',
      );
      expect(
        english.title(entry, onEventDay: true),
        'Today: Campus Sommerfest 2026',
      );
    });

    test('names the event and its place, and says which day it is on', () {
      final List<NotificationRequest> out = requestsIn(
        berlin,
        at(berlin, 2026, 7, 1),
        <CalendarEntry>[
          publicEvent(
            start: at(berlin, 2026, 7, 22, 16),
            location: 'Campuswiese',
          ),
        ],
      );

      expect(out.single.title, contains('Campus Sommerfest 2026'));
      expect(out.single.body, contains('Campuswiese'));
      expect(out.single.title, startsWith('tomorrow'));
    });

    test('an event without a place still reads as a sentence', () {
      final List<NotificationRequest> out = requestsIn(
        berlin,
        at(berlin, 2026, 7, 1),
        <CalendarEntry>[publicEvent(start: at(berlin, 2026, 7, 22, 16))],
      );

      expect(out.single.body, endsWith('.'));
      expect(out.single.body, isNot(contains(', .')));
    });

    test('public event details may show on the lock screen (P9)', () {
      final List<NotificationRequest> out = requestsIn(
        berlin,
        at(berlin, 2026, 7, 1),
        <CalendarEntry>[publicEvent(start: at(berlin, 2026, 7, 22, 16))],
      );

      expect(out.single.visibility, NotificationVisibility.publicContent);
    });
  });
}
