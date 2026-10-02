// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/widgets.dart';

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
    final DateTime key = entry.day;
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
      if (!nowPlaced && entry.start.toLocal().isAfter(now)) {
        rows.add(NowRuleCalendarListRow(now));
        nowPlaced = true;
      }
      rows.add(EntryCalendarListRow(entry: entry, now: isToday ? now : null));
    }
    if (!nowPlaced) rows.add(NowRuleCalendarListRow(now));
  }
  return List<CalendarListRow>.unmodifiable(rows);
}
