// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/widgets.dart';

import '../../../core/widgets/time_rail.dart';
import '../domain/calendar_entry.dart';

/// A lazily rendered row in the continuous calendar list.
sealed class CalendarListRow {
  const CalendarListRow();
}

class StaticCalendarListRow extends CalendarListRow {
  const StaticCalendarListRow(this.child);

  final Widget child;
}

class DayHeadingCalendarListRow extends CalendarListRow {
  const DayHeadingCalendarListRow(this.day);

  final DateTime day;
}

class NowRuleCalendarListRow extends CalendarListRow {
  const NowRuleCalendarListRow(this.at);

  final DateTime at;
}

class EntryCalendarListRow extends CalendarListRow {
  const EntryCalendarListRow({required this.entry, required this.now});

  final CalendarEntry entry;
  final DateTime? now;
}

/// Describes list contents in one pure pass, independently of lazy rendering.
List<CalendarListRow> buildCalendarListRows({
  required List<Widget> header,
  required List<CalendarEntry> entries,
  required DateTime today,
  required DateTime now,
}) {
  final List<DateTime> orderedDays = <DateTime>[];
  final Map<DateTime, List<CalendarEntry>> byDay =
      <DateTime, List<CalendarEntry>>{};
  for (final CalendarEntry entry in entries) {
    // An entry still running from an earlier day belongs to today: the list
    // starts today, and a heading for a past day would read as history.
    final DateTime key = entry.day.isBefore(today) ? today : entry.day;
    byDay
        .putIfAbsent(key, () {
          orderedDays.add(key);
          return <CalendarEntry>[];
        })
        .add(entry);
  }

  final List<CalendarListRow> rows = <CalendarListRow>[
    for (final Widget widget in header) StaticCalendarListRow(widget),
  ];
  for (final DateTime day in orderedDays) {
    rows.add(DayHeadingCalendarListRow(day));
    final bool isToday = day == today;
    bool nowPlaced = !isToday;
    for (final CalendarEntry entry in byDay[day]!) {
      // All-day entries span the whole day and carry a date-only start, so
      // their instant says nothing about where "now" falls.
      if (!nowPlaced && !entry.allDay && entry.start.toLocal().isAfter(now)) {
        rows.add(NowRuleCalendarListRow(now));
        nowPlaced = true;
      }
      rows.add(EntryCalendarListRow(entry: entry, now: isToday ? now : null));
    }
    if (!nowPlaced) rows.add(NowRuleCalendarListRow(now));
  }
  return List<CalendarListRow>.unmodifiable(rows);
}

/// How strongly an entry on today's rail is emphasised at [now].
///
/// `null` for [now] means the day being read is not today. All-day entries
/// cover the whole day and are therefore never dimmed as past; a deadline has
/// no duration, so its start doubles as its end.
TimeRailEmphasis calendarEntryEmphasis(CalendarEntry entry, DateTime? now) {
  if (now == null || entry.allDay) return TimeRailEmphasis.normal;
  final DateTime start = entry.start.toLocal();
  final DateTime finish = entry.end?.toLocal() ?? start;
  if (!start.isAfter(now) && finish.isAfter(now)) return TimeRailEmphasis.now;
  if (!finish.isAfter(now)) return TimeRailEmphasis.past;
  return TimeRailEmphasis.normal;
}
