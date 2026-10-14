// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'unified_event.dart';

/// How far back "Ältere anzeigen" reaches, in days. Well inside the API's
/// maximum range (`PUBLIC_CALENDAR_API_MAX_RANGE_DAYS`, at most 400), which
/// both `/v1/posts/events` and `/v1/calendars/events` enforce.
const int kPastEventsWindowDays = 180;

/// The explicit request window for past events, as `YYYY-MM-DD` days.
@immutable
class PastEventsWindow {
  const PastEventsWindow({required this.from, required this.to});

  final String from;

  /// Inclusive last day — today.
  final String to;

  @override
  bool operator ==(Object other) =>
      other is PastEventsWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The past window ending today (local calendar day of [now]) and starting
/// [days] days earlier.
///
/// Both bounds are always named: an older deployed backend resolves a
/// missing `to` as `from` plus its maximum range, which for a past `from`
/// would silently pull in upcoming events as well.
PastEventsWindow pastEventsWindow(
  DateTime now, {
  int days = kPastEventsWindowDays,
}) {
  final DateTime local = now.toLocal();
  final DateTime today = DateTime(local.year, local.month, local.day);
  final DateTime first = DateTime(today.year, today.month, today.day - days);
  return PastEventsWindow(from: _isoDay(first), to: _isoDay(today));
}

String _isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Every event of [primary], followed by each event of [secondary] whose
/// [UnifiedEvent.eventRef] [primary] does not already contain. The current
/// load wins over the past load for an event both windows returned (e.g.
/// one that ended earlier today).
List<UnifiedEvent> unionEventsByRef({
  required List<UnifiedEvent> primary,
  required List<UnifiedEvent> secondary,
}) {
  if (secondary.isEmpty) return primary;
  final Set<String> seen = <String>{
    for (final UnifiedEvent e in primary) e.eventRef,
  };
  return <UnifiedEvent>[
    ...primary,
    for (final UnifiedEvent e in secondary)
      if (seen.add(e.eventRef)) e,
  ];
}
