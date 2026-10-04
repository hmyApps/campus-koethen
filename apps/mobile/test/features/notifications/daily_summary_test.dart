// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The aggregation behind the 08:00 overview (LEVIORA-164).
///
/// A pure function over calendar entries, so every case the product rules
/// name — an empty day, a crowded one, a cancelled lecture, a week that runs
/// across a daylight-saving change — is a value comparison here rather than a
/// device session.
library;

import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/notifications/application/daily_summary.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEntry lecture(
  DateTime start, {
  String id = 'l1',
  String title = 'Analysis I',
  bool cancelled = false,
}) => CalendarEntry(
  id: 'timetable:$id',
  source: CalendarSource.timetable,
  title: title,
  start: start,
  end: start.add(const Duration(minutes: 90)),
  isCancelled: cancelled,
);

CalendarEntry event(
  DateTime start, {
  String id = 'e1',
  String title = 'Campus Sommerfest',
  DateTime? end,
  bool allDay = false,
  CalendarSource source = CalendarSource.publicCalendar,
}) => CalendarEntry(
  id: id,
  source: source,
  title: title,
  start: start,
  end: end,
  allDay: allDay,
);

CalendarEntry deadline(DateTime dueAt, {String id = 'm1'}) => CalendarEntry(
  id: 'moodle:$id',
  source: CalendarSource.moodle,
  title: 'Übungsblatt 4',
  start: dueAt,
  subtitle: 'Datenbanken II',
);

DailySummaryDay dayOf(List<DailySummaryDay> days, DateTime day) =>
    days.firstWhere((DailySummaryDay d) => d.day == day);

void main() {
  final DateTime today = DateTime(2026, 8, 24);
  final DateTime tomorrow = DateTime(2026, 8, 25);

  group('what makes a day worth a notification', () {
    test('a day with nothing on it produces no overview', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: const <CalendarEntry>[],
      );

      expect(days, hasLength(kDailySummaryHorizonDays));
      expect(
        days.where((DailySummaryDay d) => d.hasRelevantEntry),
        isEmpty,
        reason: 'An empty day must not be announced (LEVIORA-159).',
      );
    });

    test('a normal day carries its lectures, events, deadlines and menu', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[
          lecture(DateTime(2026, 8, 24, 8, 30), id: 'a'),
          lecture(DateTime(2026, 8, 24, 11, 15), id: 'b'),
          lecture(DateTime(2026, 8, 24, 13, 0), id: 'c'),
          event(DateTime(2026, 8, 24, 16)),
          deadline(DateTime(2026, 8, 24, 23, 59)),
        ],
        canteenByDay: <DateTime, DailySummaryCanteen>{
          today: const DailySummaryCanteen(hasMenu: true),
        },
      );

      final DailySummaryDay day = dayOf(days, today);
      expect(day.hasRelevantEntry, isTrue);
      expect(day.lectureCount, 3);
      expect(day.firstLectureStart, DateTime(2026, 8, 24, 8, 30));
      expect(day.eventCount, 1);
      expect(day.singleEventTitle, 'Campus Sommerfest');
      expect(day.moodleDeadlineCount, 1);
      expect(day.hasCanteenMenu, isTrue);
      expect(day.favouriteMealName, isNull);
    });

    test('a crowded day keeps counts and stops naming individual events', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[
          for (int i = 0; i < 6; i++)
            lecture(DateTime(2026, 8, 24, 8 + i), id: 'l$i'),
          for (int i = 0; i < 5; i++)
            event(DateTime(2026, 8, 24, 12 + i), id: 'e$i', title: 'Event $i'),
          for (int i = 0; i < 4; i++)
            deadline(DateTime(2026, 8, 24, 20 + (i % 3)), id: 'd$i'),
        ],
      );

      final DailySummaryDay day = dayOf(days, today);
      expect(day.lectureCount, 6);
      expect(day.eventCount, 5);
      expect(day.moodleDeadlineCount, 4);
      expect(
        day.singleEventTitle,
        isNull,
        reason:
            'With more than one event the body names a count, so a crowded '
            'day still fits the two lines of UX spec § 5.1.3.',
      );
    });

    test('a cancelled lecture neither counts nor fills a day', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[
          lecture(DateTime(2026, 8, 24, 8, 30), id: 'a', cancelled: true),
          lecture(DateTime(2026, 8, 25, 8, 30), id: 'b'),
        ],
      );

      expect(dayOf(days, today).lectureCount, 0);
      expect(dayOf(days, today).hasRelevantEntry, isFalse);
      expect(dayOf(days, tomorrow).lectureCount, 1);
    });

    test('a menu alone and a favourite both fill their day', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: const <CalendarEntry>[],
        canteenByDay: <DateTime, DailySummaryCanteen>{
          today: const DailySummaryCanteen(hasMenu: true),
          tomorrow: const DailySummaryCanteen(
            hasMenu: true,
            favouriteMealName: 'Käsespätzle',
          ),
        },
      );

      expect(dayOf(days, today).hasRelevantEntry, isTrue);
      expect(dayOf(days, tomorrow).hasRelevantEntry, isTrue);
      expect(dayOf(days, tomorrow).favouriteMealName, 'Käsespätzle');
    });
  });

  group('locally known changes are reflected, not accumulated', () {
    test('a removed entry simply stops producing an overview', () {
      List<DailySummaryDay> plan(List<CalendarEntry> entries) =>
          buildDailySummaryDays(firstDay: today, entries: entries);

      final CalendarEntry only = lecture(DateTime(2026, 8, 24, 8, 30));
      expect(
        dayOf(plan(<CalendarEntry>[only]), today).hasRelevantEntry,
        isTrue,
      );
      expect(
        dayOf(plan(const <CalendarEntry>[]), today).hasRelevantEntry,
        isFalse,
      );
    });

    test('a moved lecture moves the day it is counted on', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[lecture(DateTime(2026, 8, 25, 10))],
      );

      expect(dayOf(days, today).lectureCount, 0);
      expect(dayOf(days, tomorrow).lectureCount, 1);
    });

    test('the same entry delivered twice is counted once', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[
          lecture(DateTime(2026, 8, 24, 8, 30), id: 'a'),
          lecture(DateTime(2026, 8, 24, 8, 30), id: 'a'),
        ],
      );

      expect(dayOf(days, today).lectureCount, 1);
    });
  });

  group('the horizon', () {
    test('covers exactly the days the shortest source knows about', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: const <CalendarEntry>[],
      );

      expect(days.first.day, today);
      expect(days.last.day, DateTime(2026, 9, 6));
      expect(kDailySummaryHorizonDays, 14);
    });

    test('an entry beyond the horizon is not planned', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[lecture(DateTime(2026, 9, 7, 10))],
      );

      expect(days.where((DailySummaryDay d) => d.hasRelevantEntry), isEmpty);
    });

    test('a day count is stable across a daylight-saving change', () {
      // Germany turns the clocks back on 25 October 2026. A horizon advanced
      // by `Duration(days: 1)` would land on the 25th twice and never reach
      // the last day at all.
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: DateTime(2026, 10, 20),
        entries: const <CalendarEntry>[],
      );

      expect(
        days.map((DailySummaryDay d) => d.day).toSet(),
        hasLength(kDailySummaryHorizonDays),
      );
      expect(days[5].day, DateTime(2026, 10, 25));
      expect(days.last.day, DateTime(2026, 11, 2));
    });
  });

  group('entries that span more than one day', () {
    test('an examination week is counted on every day it runs', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[
          event(
            DateTime.utc(2026, 8, 24),
            id: 'exam',
            title: 'Prüfungszeitraum',
            end: DateTime.utc(2026, 8, 27),
            allDay: true,
          ),
        ],
      );

      for (final DateTime day in <DateTime>[
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 25),
        DateTime(2026, 8, 26),
      ]) {
        expect(dayOf(days, day).eventCount, 1, reason: '$day');
      }
      // `DTEND` is exclusive: the period has not reached the 27th.
      expect(dayOf(days, DateTime(2026, 8, 27)).eventCount, 0);
    });
  });

  group('sources are classified the way the product rules group them', () {
    test('saved events and post events count as events, not as lectures', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[
          event(
            DateTime(2026, 8, 24, 16),
            id: 'savedEvent:calendar:1',
            source: CalendarSource.savedEvents,
          ),
          event(
            DateTime(2026, 8, 24, 18),
            id: 'post:2',
            source: CalendarSource.postEvent,
          ),
        ],
      );

      final DailySummaryDay day = dayOf(days, today);
      expect(day.eventCount, 2);
      expect(day.lectureCount, 0);
      expect(day.moodleDeadlineCount, 0);
    });

    test('personal Exchange entries never enter persistent notifications', () {
      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[
          event(
            DateTime(2026, 8, 24, 16),
            id: 'exchange:private',
            title: 'Persönlicher Termin',
            source: CalendarSource.exchangeCalendar,
          ),
        ],
      );

      expect(dayOf(days, today).hasRelevantEntry, isFalse);
    });
  });
}
