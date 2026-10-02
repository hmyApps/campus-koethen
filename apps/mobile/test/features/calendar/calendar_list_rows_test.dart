// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

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
}
