// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../domain/calendar_entry.dart';

const int kMaximumCalendarHomeWidgetEvents = 12;

@immutable
class CalendarHomeWidgetEvent {
  const CalendarHomeWidgetEvent({
    required this.id,
    required this.startMillis,
    required this.endMillis,
    required this.allDay,
    this.title,
    this.location,
  });

  final String id;
  final int startMillis;
  final int endMillis;
  final bool allDay;
  final String? title;
  final String? location;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'start': startMillis,
    'end': endMillis,
    'allDay': allDay,
    if (title != null) 'title': title,
    if (location != null) 'location': location,
  };
}

@immutable
class CalendarHomeWidgetPayload {
  const CalendarHomeWidgetPayload({
    required this.generatedAtMillis,
    required this.locale,
    required this.showDetails,
    required this.events,
    this.enabled = true,
  });

  final int generatedAtMillis;
  final String locale;
  final bool showDetails;
  final List<CalendarHomeWidgetEvent> events;
  final bool enabled;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'enabled': enabled,
    'generatedAt': generatedAtMillis,
    'locale': locale,
    'showDetails': showDetails,
    'events': events
        .map((CalendarHomeWidgetEvent event) => event.toJson())
        .toList(growable: false),
  };

  static CalendarHomeWidgetPayload disabled({
    required DateTime now,
    required String locale,
  }) => CalendarHomeWidgetPayload(
    generatedAtMillis: now.millisecondsSinceEpoch,
    locale: locale == 'en' ? 'en' : 'de',
    showDetails: false,
    events: const <CalendarHomeWidgetEvent>[],
    enabled: false,
  );
}

CalendarHomeWidgetPayload buildCalendarHomeWidgetPayload({
  required Iterable<CalendarEntry> entries,
  required DateTime now,
  required String locale,
  required bool showDetails,
}) {
  final DateTime localNow = now.toLocal();
  final DateTime today = DateTime(localNow.year, localNow.month, localNow.day);
  final List<_Candidate> candidates = <_Candidate>[];
  for (final CalendarEntry entry in entries) {
    if (entry.isCancelled) continue;
    final DateTime start;
    final DateTime end;
    if (entry.allDay) {
      start = entry.day;
      final DateTime last = entry.lastDay;
      end = DateTime(last.year, last.month, last.day + 1);
      if (!end.isAfter(today)) continue;
    } else {
      start = entry.start.toLocal();
      end = (entry.end ?? entry.start).toLocal();
      if (end.isAfter(start)) {
        if (!end.isAfter(localNow)) continue;
      } else if (!start.isAfter(localNow)) {
        continue;
      }
    }
    candidates.add(_Candidate(entry: entry, start: start, end: end));
  }
  candidates.sort((_Candidate a, _Candidate b) {
    final int byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    final int byTitle = a.entry.title.compareTo(b.entry.title);
    return byTitle != 0 ? byTitle : a.entry.id.compareTo(b.entry.id);
  });
  final List<CalendarHomeWidgetEvent> events = candidates
      .take(kMaximumCalendarHomeWidgetEvents)
      .map(
        (_Candidate candidate) => CalendarHomeWidgetEvent(
          id: _boundedText(candidate.entry.id, 160) ?? '',
          startMillis: candidate.start.millisecondsSinceEpoch,
          endMillis: candidate.end.millisecondsSinceEpoch,
          allDay: candidate.entry.allDay,
          title: showDetails ? _boundedText(candidate.entry.title, 120) : null,
          location: showDetails
              ? _boundedText(candidate.entry.location, 120)
              : null,
        ),
      )
      .toList(growable: false);
  return CalendarHomeWidgetPayload(
    generatedAtMillis: localNow.millisecondsSinceEpoch,
    locale: locale == 'en' ? 'en' : 'de',
    showDetails: showDetails,
    events: List<CalendarHomeWidgetEvent>.unmodifiable(events),
  );
}

String? _boundedText(String? value, int maximumLength) {
  if (value == null) return null;
  final String clean = value.replaceAll(_controlCharacters, '').trim();
  if (clean.isEmpty) return null;
  return clean.length <= maximumLength
      ? clean
      : clean.substring(0, maximumLength);
}

final RegExp _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

class _Candidate {
  const _Candidate({
    required this.entry,
    required this.start,
    required this.end,
  });

  final CalendarEntry entry;
  final DateTime start;
  final DateTime end;
}
