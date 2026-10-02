// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/calendar/application/calendar_merge.dart';
import 'package:campus_koethen/features/calendar/application/calendar_providers.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry_details.dart';
import 'package:campus_koethen/features/canteen/data/canteen_models.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_test/flutter_test.dart';

Timetable _timetable() => Timetable(
  group: const TimetableGroup(id: 'g1', shortName: 'INF-1'),
  days: <TimetableDay>[
    TimetableDay(
      date: DateTime(2026, 7, 27),
      entries: <TimetableEntry>[
        TimetableEntry(
          id: 'e1',
          start: DateTime(2026, 7, 27, 9),
          end: DateTime(2026, 7, 27, 10, 30),
          title: 'Mathematik I',
          status: TimetableEntryStatus.regular,
          rooms: const <TimetableRoom>[TimetableRoom(shortName: 'A1.01')],
        ),
        TimetableEntry(
          id: 'e2',
          start: DateTime(2026, 7, 27, 11),
          end: DateTime(2026, 7, 27, 12, 30),
          title: 'Programmieren',
          status: TimetableEntryStatus.cancelled,
        ),
      ],
    ),
  ],
);

MoodleDeadline _deadline() => MoodleDeadline(
  id: 55,
  title: 'Übungsblatt 1 ist fällig',
  dueAt: DateTime(2026, 7, 27, 23, 59),
  courseId: 101,
  courseName: 'Beispielkurs Informatik',
  moduleName: 'assign',
);

void main() {
  group('timetable mapping', () {
    test('maps entries to calendar entries and flags cancellation', () {
      final List<CalendarEntry> entries = timetableToCalendarEntries(
        _timetable(),
      );
      expect(entries, hasLength(2));
      expect(entries[0].source, CalendarSource.timetable);
      expect(entries[0].title, 'Mathematik I');
      expect(entries[0].location, 'A1.01');
      expect(entries[0].isCancelled, isFalse);
      expect(entries[1].isCancelled, isTrue);
    });
  });

  group('moodle mapping', () {
    test('maps deadlines to calendar entries', () {
      final List<CalendarEntry> entries = moodleDeadlinesToCalendarEntries(
        <MoodleDeadline>[_deadline()],
      );
      expect(entries, hasLength(1));
      expect(entries.first.source, CalendarSource.moodle);
      expect(entries.first.title, 'Übungsblatt 1 ist fällig');
      expect(entries.first.subtitle, 'Beispielkurs Informatik');
      expect(entries.first.start, DateTime(2026, 7, 27, 23, 59));
    });
  });

  group('aggregation', () {
    test('merges, sorts by start and keeps both sources', () {
      final List<CalendarEntry> merged = mergeCalendarEntries(<CalendarEntry>[
        ...timetableToCalendarEntries(_timetable()),
        ...moodleDeadlinesToCalendarEntries(<MoodleDeadline>[_deadline()]),
      ]);
      expect(merged, hasLength(3));
      // Sorted ascending by start.
      for (int i = 1; i < merged.length; i++) {
        expect(merged[i - 1].start.isAfter(merged[i].start), isFalse);
      }
      expect(
        merged.where((CalendarEntry e) => e.source == CalendarSource.moodle),
        hasLength(1),
      );
    });

    test('deduplicates entries with the same id', () {
      final List<CalendarEntry> a = timetableToCalendarEntries(_timetable());
      final List<CalendarEntry> merged = mergeCalendarEntries(<CalendarEntry>[
        ...a,
        ...a,
      ]);
      expect(merged, hasLength(2));
    });

    test('entriesForDay returns only that local day, sorted', () {
      final List<CalendarEntry> all = mergeCalendarEntries(<CalendarEntry>[
        ...timetableToCalendarEntries(_timetable()),
        ...moodleDeadlinesToCalendarEntries(<MoodleDeadline>[_deadline()]),
      ]);
      final List<CalendarEntry> day = entriesForDay(all, DateTime(2026, 7, 27));
      expect(day, hasLength(3));
      final List<CalendarEntry> other = entriesForDay(
        all,
        DateTime(2026, 7, 28),
      );
      expect(other, isEmpty);
    });

    test('calendarEventDays returns the distinct day keys', () {
      final Set<DateTime> days = calendarEventDays(
        moodleDeadlinesToCalendarEntries(<MoodleDeadline>[_deadline()]),
      );
      expect(days, contains(DateTime(2026, 7, 27)));
      expect(days, hasLength(1));
    });
  });

  group('CalendarDayIndex', () {
    List<CalendarEntry> merged() => mergeCalendarEntries(<CalendarEntry>[
      ...timetableToCalendarEntries(_timetable()),
      ...moodleDeadlinesToCalendarEntries(<MoodleDeadline>[_deadline()]),
    ]);

    test('answers exactly what entriesForDay answers', () {
      final List<CalendarEntry> all = merged();
      final CalendarDayIndex index = CalendarDayIndex.of(all);
      for (int day = 25; day <= 30; day++) {
        final DateTime date = DateTime(2026, 7, day);
        expect(
          index.forDay(date),
          entriesForDay(all, date),
          reason: 'day $day must not change just because it is indexed',
        );
      }
    });

    test('a multi-day entry is answered on every day it runs on', () {
      final CalendarEntry examWeek = CalendarEntry(
        id: 'exam',
        source: CalendarSource.publicCalendar,
        title: 'Prüfungszeitraum',
        start: DateTime.utc(2026, 2, 2),
        end: DateTime.utc(2026, 2, 7),
        allDay: true,
      );
      final CalendarEntry single = CalendarEntry(
        id: 'single',
        source: CalendarSource.moodle,
        title: 'Abgabe',
        start: DateTime(2026, 2, 4, 23, 59),
      );
      final List<CalendarEntry> all = mergeCalendarEntries(<CalendarEntry>[
        examWeek,
        single,
      ]);
      final CalendarDayIndex index = CalendarDayIndex.of(all);

      for (int day = 2; day <= 6; day++) {
        expect(
          index.forDay(DateTime(2026, 2, day)),
          entriesForDay(all, DateTime(2026, 2, day)),
        );
      }
      expect(index.forDay(DateTime(2026, 2, 4)), <CalendarEntry>[
        examWeek,
        single,
      ]);
      expect(index.forDay(DateTime(2026, 2, 7)), isEmpty);
      expect(index.forDay(DateTime(2026, 2, 1)), isEmpty);
    });

    test('repeated lookups keep giving the same answer', () {
      final CalendarData data = CalendarData(
        entries: merged(),
        enabledSources: const <CalendarSource>{},
      );
      final List<CalendarEntry> first = data.forDay(DateTime(2026, 7, 27));
      final List<CalendarEntry> second = data.forDay(DateTime(2026, 7, 27));
      expect(second, first);
      expect(data.eventDays, data.eventDays);
      expect(data.eventDays, contains(DateTime(2026, 7, 27)));
    });
  });

  group('canteen favourite meal mapping', () {
    CanteenMenu menu() => CanteenMenu(
      canteenSlug: 'mensa-koethen',
      displayName: 'Mensa Köthen',
      days: <MenuDay>[
        MenuDay(
          date: DateTime.utc(2026, 7, 27),
          meals: const <Meal>[
            Meal(id: '1', name: 'Bulgur-Pfanne'),
            Meal(id: '2', name: 'Schnitzel'),
          ],
        ),
        MenuDay(
          date: DateTime.utc(2026, 7, 28),
          meals: const <Meal>[Meal(id: '3', name: 'Schnitzel')],
        ),
      ],
    );

    test('maps only the dishes that are favourited, one entry per day', () {
      final List<CalendarEntry> entries =
          canteenFavouriteMealsToCalendarEntries(menu(), <String>{
            'Bulgur-Pfanne',
          });

      expect(entries, hasLength(1));
      final CalendarEntry entry = entries.single;
      expect(entry.title, 'Bulgur-Pfanne');
      expect(entry.source, CalendarSource.canteenFavourite);
      expect(entry.allDay, isTrue);
      expect(entry.day, DateTime(2026, 7, 27));
      expect(
        entry.details,
        const CanteenFavouriteMealCalendarDetails(canteenName: 'Mensa Köthen'),
      );
    });

    test('a dish served on several days gets one entry per day', () {
      final List<CalendarEntry> entries =
          canteenFavouriteMealsToCalendarEntries(menu(), <String>{'Schnitzel'});

      expect(entries, hasLength(2));
      expect(entries.map((CalendarEntry e) => e.day), <DateTime>[
        DateTime(2026, 7, 27),
        DateTime(2026, 7, 28),
      ]);
    });

    test('no favourites means no entries, never a guess', () {
      expect(
        canteenFavouriteMealsToCalendarEntries(menu(), const <String>{}),
        isEmpty,
      );
    });
  });

  group('monthWeekStarts', () {
    test('covers every week overlapping the focused month, Mondays only', () {
      // July 2026: 1st is a Wednesday, 31st is a Friday.
      final List<DateTime> starts = monthWeekStarts(DateTime(2026, 7, 15));
      expect(starts.first, DateTime(2026, 6, 29)); // Monday before the 1st
      for (final DateTime start in starts) {
        expect(start.weekday, DateTime.monday);
      }
      // The last week must include the 31st.
      expect(starts.last.isBefore(DateTime(2026, 8, 1)), isTrue);
      expect(
        starts.last.add(const Duration(days: 6)).isAfter(DateTime(2026, 7, 30)),
        isTrue,
      );
    });
  });
}
