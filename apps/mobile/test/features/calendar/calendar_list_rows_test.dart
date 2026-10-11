// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/widgets/time_rail.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/presentation/calendar_list_rows.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEntry _entry(String id, DateTime start) => CalendarEntry(
  id: id,
  source: CalendarSource.publicCalendar,
  title: id,
  start: start,
  end: start.add(const Duration(hours: 1)),
);

void main() {
  test('groups days once and places the now row before the next entry', () {
    final DateTime today = DateTime(2026, 10, 1);
    final DateTime now = DateTime(2026, 10, 1, 10);

    final List<CalendarListRow> rows = buildCalendarListRows(
      header: const <Widget>[SizedBox(key: ValueKey<String>('status'))],
      entries: <CalendarEntry>[
        _entry('past', DateTime(2026, 10, 1, 9)),
        _entry('future', DateTime(2026, 10, 1, 11)),
        _entry('tomorrow', DateTime(2026, 10, 2, 9)),
      ],
      today: today,
      now: now,
    );

    expect(rows.whereType<StaticCalendarListRow>(), hasLength(1));
    expect(rows.whereType<DayHeadingCalendarListRow>(), hasLength(2));
    expect(rows.whereType<NowRuleCalendarListRow>(), hasLength(1));
    expect(rows.whereType<EntryCalendarListRow>(), hasLength(3));
    expect(
      rows.indexWhere((CalendarListRow row) => row is NowRuleCalendarListRow),
      lessThan(
        rows.indexWhere(
          (CalendarListRow row) =>
              row is EntryCalendarListRow && row.entry.id == 'future',
        ),
      ),
    );
  });

  test('an entry still running from an earlier day is listed under today', () {
    final DateTime today = DateTime(2026, 10, 1);
    final DateTime now = DateTime(2026, 10, 1, 10);

    final List<CalendarListRow> rows = buildCalendarListRows(
      header: const <Widget>[],
      entries: <CalendarEntry>[
        CalendarEntry(
          id: 'running',
          source: CalendarSource.publicCalendar,
          title: 'running',
          start: DateTime(2026, 9, 29),
          end: DateTime(2026, 10, 3),
          allDay: true,
        ),
        _entry('future', DateTime(2026, 10, 1, 11)),
      ],
      today: today,
      now: now,
    );

    expect(
      rows.whereType<DayHeadingCalendarListRow>().map(
        (DayHeadingCalendarListRow row) => row.day,
      ),
      <DateTime>[today],
    );
  });

  test('the now rule never lands before an all-day entry', () {
    final DateTime today = DateTime(2026, 10, 1);
    final DateTime now = DateTime(2026, 10, 1, 0, 30);

    final List<CalendarListRow> rows = buildCalendarListRows(
      header: const <Widget>[],
      entries: <CalendarEntry>[
        CalendarEntry(
          id: 'all-day',
          source: CalendarSource.publicCalendar,
          title: 'all-day',
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 2),
          allDay: true,
        ),
        _entry('future', DateTime(2026, 10, 1, 11)),
      ],
      today: today,
      now: now,
    );

    expect(
      rows.indexWhere((CalendarListRow row) => row is NowRuleCalendarListRow),
      greaterThan(
        rows.indexWhere(
          (CalendarListRow row) =>
              row is EntryCalendarListRow && row.entry.id == 'all-day',
        ),
      ),
    );
  });

  test('an all-day entry of today is never dimmed as past', () {
    final CalendarEntry allDay = CalendarEntry(
      id: 'all-day',
      source: CalendarSource.savedEvents,
      title: 'all-day',
      start: DateTime.utc(2026, 10, 1),
      allDay: true,
    );

    expect(
      calendarEntryEmphasis(allDay, DateTime(2026, 10, 1, 15)),
      isNot(TimeRailEmphasis.past),
    );
    expect(
      calendarEntryEmphasis(
        _entry('earlier', DateTime(2026, 10, 1, 9)),
        DateTime(2026, 10, 1, 15),
      ),
      TimeRailEmphasis.past,
    );
  });
}
