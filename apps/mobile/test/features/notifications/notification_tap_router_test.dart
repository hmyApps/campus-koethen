// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/app_routes.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/notifications/application/notification_tap_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where a tap lands, and — more importantly — where it does *not* land when
/// the payload is older than the app reading it.

void main() {
  const NotificationTapRouter router = NotificationTapRouter(
    preferredCanteenSlug: 'mensa-fasanerieallee',
  );

  group('the daily overview', () {
    test('opens the calendar on the day it was about', () {
      final NotificationTapTarget? target = router.resolve(
        'v1|daily.summary|2026-09-03',
      );

      expect(target?.location, AppRoutes.calendar);
      expect(target?.focusDay, DateTime(2026, 9, 3));
      expect(target?.resolved, isTrue);
    });

    test('a day that is not a day falls back and says so', () {
      for (final String broken in <String>[
        'v1|daily.summary|2026-9-3',
        'v1|daily.summary|2026-02-30',
        'v1|daily.summary|2026-13-01',
        'v1|daily.summary|tomorrow',
        'v1|daily.summary|2026-09-03T08:00:00Z',
      ]) {
        final NotificationTapTarget? target = router.resolve(broken);
        expect(target?.location, AppRoutes.calendar, reason: broken);
        expect(target?.resolved, isFalse, reason: broken);
      }
    });
  });

  group('the canteen favourite', () {
    test('opens the menu on the day it was about', () {
      final NotificationTapTarget? target = router.resolve(
        'v1|canteen.favourite|mensa-fasanerieallee:2026-09-03',
      );

      expect(target?.location, AppRoutes.canteen);
      expect(target?.focusDay, DateTime(2026, 9, 3));
      expect(target?.resolved, isTrue);
    });

    test('a hint for a canteen the reader has since left is not resolved', () {
      final NotificationTapTarget? target = router.resolve(
        'v1|canteen.favourite|mensa-somewhere-else:2026-09-03',
      );

      expect(target?.location, AppRoutes.canteen);
      expect(target?.resolved, isFalse);
    });

    test('a malformed target falls back to the menu', () {
      for (final String broken in <String>[
        'v1|canteen.favourite|noseparator',
        'v1|canteen.favourite|:2026-09-03',
        'v1|canteen.favourite|mensa-fasanerieallee:2026-9-3',
        'v1|canteen.favourite|mensa-fasanerieallee:2026-02-30',
        'v1|canteen.favourite|mensa-fasanerieallee:2026-09-03:',
      ]) {
        final NotificationTapTarget? target = router.resolve(broken);
        expect(target?.location, AppRoutes.canteen, reason: broken);
        expect(target?.resolved, isFalse, reason: broken);
      }
    });

    test('names the dish when the payload carries one', () {
      final NotificationTapTarget? target = router.resolve(
        'v1|canteen.favourite|mensa-fasanerieallee:2026-09-03:Käsespätzle',
      );

      expect(target?.focusDay, DateTime(2026, 9, 3));
      expect(target?.focusMealName, 'Käsespätzle');
      expect(target?.resolved, isTrue);
    });

    test('a dish name containing a colon survives intact', () {
      // Read from the left, not from the end: anchoring on the last colon
      // would cut this name in half and mark nothing.
      final NotificationTapTarget? target = router.resolve(
        'v1|canteen.favourite|mensa-fasanerieallee:2026-09-03:Menü 1: Spätzle',
      );

      expect(target?.focusMealName, 'Menü 1: Spätzle');
    });

    test('a payload from before the dish target still opens the day', () {
      final NotificationTapTarget? target = router.resolve(
        'v1|canteen.favourite|mensa-fasanerieallee:2026-09-03',
      );

      expect(target?.focusDay, DateTime(2026, 9, 3));
      expect(target?.focusMealName, isNull);
      expect(target?.resolved, isTrue);
    });
  });

  group('the event reminder', () {
    final CalendarEntry sommerfest = CalendarEntry(
      id: 'savedEvent:calendar:4711',
      source: CalendarSource.savedEvents,
      title: 'Campus Sommerfest 2026',
      start: DateTime(2026, 9, 3, 16),
    );
    final NotificationTapRouter resolving = NotificationTapRouter(
      findCalendarEntry: (String id) => id == sommerfest.id ? sommerfest : null,
    );

    test('opens the calendar on the event, with the entry to show', () {
      final NotificationTapTarget? target = resolving.resolve(
        'v1|event.reminder|savedEvent:calendar:4711',
      );

      expect(target?.location, AppRoutes.calendar);
      expect(target?.focusDay, DateTime(2026, 9, 3));
      expect(target?.calendarEntry, sommerfest);
      expect(target?.resolved, isTrue);
    });

    test('the day comes from the entry, not from the payload', () {
      // The payload carries an identifier and nothing else, so an event moved
      // to another day since the reminder was scheduled still opens on the day
      // it is actually on.
      final CalendarEntry moved = CalendarEntry(
        id: 'savedEvent:calendar:4711',
        source: CalendarSource.savedEvents,
        title: 'Campus Sommerfest 2026',
        start: DateTime(2026, 9, 10, 16),
      );
      final NotificationTapTarget? target = NotificationTapRouter(
        findCalendarEntry: (String _) => moved,
      ).resolve('v1|event.reminder|savedEvent:calendar:4711');

      expect(target?.focusDay, DateTime(2026, 9, 10));
    });

    test('an entry that is gone falls back to the calendar and says so', () {
      final NotificationTapTarget? target = resolving.resolve(
        'v1|event.reminder|publicCalendar:hsa:deleted',
      );

      expect(target?.location, AppRoutes.calendar);
      expect(target?.calendarEntry, isNull);
      expect(target?.resolved, isFalse);
    });

    test('without any way to resolve, it still lands on the calendar', () {
      // The router with no lookup at all — the shape a caller that has not
      // wired one takes. It must degrade to the fallback, never throw.
      final NotificationTapTarget? target = router.resolve(
        'v1|event.reminder|savedEvent:calendar:4711',
      );

      expect(target?.location, AppRoutes.calendar);
      expect(target?.resolved, isFalse);
    });

    test('a stale payload never reaches the lookup as something else', () {
      // Whatever an older app version wrote, the identifier is handed over
      // verbatim and the answer decides — no parsing, no guessing, no crash.
      final List<String> asked = <String>[];
      final NotificationTapRouter recording = NotificationTapRouter(
        findCalendarEntry: (String id) {
          asked.add(id);
          return null;
        },
      );

      recording.resolve('v1|event.reminder|timetable:99');
      recording.resolve('v1|event.reminder|../../etc/passwd');
      recording.resolve('v1|event.reminder|a b c');

      expect(asked, <String>['timetable:99', '../../etc/passwd', 'a b c']);
    });
  });

  group('new mail', () {
    test('opens the inbox for a validated IMAP UID', () {
      final NotificationTapTarget? target = router.resolve('v1|mail.new|4711');

      expect(target?.location, AppRoutes.mail);
      expect(target?.resolved, isTrue);
    });

    test('a malformed UID falls back to the inbox and says so', () {
      for (final String broken in <String>[
        'v1|mail.new|abc',
        'v1|mail.new|-1',
        'v1|mail.new|1@host',
        'v1|mail.new|123456789012345678901',
      ]) {
        final NotificationTapTarget? target = router.resolve(broken);
        expect(target?.location, AppRoutes.mail, reason: broken);
        expect(target?.resolved, isFalse, reason: broken);
      }
    });
  });

  test('a payload this version cannot read navigates nowhere at all', () {
    for (final String? raw in <String?>[
      null,
      '',
      'v2|daily.summary|2026-09-03',
      'v1|moodle.deadline|4711',
      '/more/moodle',
      'garbage',
    ]) {
      expect(router.resolve(raw), isNull, reason: 'must not navigate: $raw');
    }
  });

  test('every destination is an existing app route', () {
    const Set<String> known = <String>{
      AppRoutes.calendar,
      AppRoutes.canteen,
      AppRoutes.mail,
    };
    for (final String payload in <String>[
      'v1|event.reminder|savedEvent:1',
      'v1|daily.summary|2026-09-03',
      'v1|canteen.favourite|mensa-fasanerieallee:2026-09-03',
      'v1|canteen.favourite|broken',
      'v1|mail.new|4711',
    ]) {
      expect(known, contains(router.resolve(payload)!.location));
    }
  });

  test('a day key is written the way the router reads it', () {
    expect(notificationDayKey(DateTime(2026, 9, 3)), '2026-09-03');
    expect(
      router
          .resolve(
            'v1|daily.summary|${notificationDayKey(DateTime(2026, 1, 7))}',
          )
          ?.focusDay,
      DateTime(2026, 1, 7),
    );
  });
}
