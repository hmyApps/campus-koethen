// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../data/timetable_models.dart';

Timetable filterTimetableModules(Timetable timetable, Set<String> moduleKeys) =>
    Timetable(
      group: timetable.group,
      days: timetable.days
          .map(
            (day) => TimetableDay(
              date: day.date,
              entries: day.entries
                  .where(
                    (entry) =>
                        entry.moduleKey != null &&
                        moduleKeys.contains(entry.moduleKey),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );

/// Merges multiple subscribed groups while keeping shared lessons exactly once.
Timetable mergeTimetables(List<Timetable> timetables) {
  if (timetables.isEmpty) {
    throw ArgumentError.value(timetables, 'timetables', 'must not be empty');
  }
  final Map<DateTime, Map<String, TimetableEntry>> byDay =
      <DateTime, Map<String, TimetableEntry>>{};
  for (final Timetable timetable in timetables) {
    for (final TimetableDay day in timetable.days) {
      final DateTime key = DateTime(
        day.date.year,
        day.date.month,
        day.date.day,
      );
      final Map<String, TimetableEntry> entries = byDay.putIfAbsent(
        key,
        () => <String, TimetableEntry>{},
      );
      for (final TimetableEntry entry in day.entries) {
        entries.putIfAbsent(entry.id, () => entry);
      }
    }
  }
  final List<TimetableDay> days = byDay.entries.map((day) {
    final List<TimetableEntry> entries = day.value.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return TimetableDay(date: day.key, entries: entries);
  }).toList()..sort((a, b) => a.date.compareTo(b.date));
  return Timetable(group: timetables.first.group, days: days);
}
