// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../calendar/domain/calendar_entry.dart' show calendarDayOf;
import 'unified_event.dart';

/// Visibility and time-boundary rules for the general event overview.
///
/// These rules apply **only** to the event overview — never to the normal
/// calendar, which keeps showing every entry regardless of whether it has
/// ended, and never to the saved-events list's "past" group, which is a
/// deliberately separate state.
///
/// * A timed event with an end disappears exactly when `eventEnd <= now`
///   (minute-exact, since [DateTime] comparisons are instant-based).
/// * A timed event without an end stays visible until local midnight of its
///   start day — no duration is ever invented for it.
/// * An all-day event disappears at local midnight after its exclusive last
///   day (reusing [calendarDayOf], the same day-boundary rule the calendar
///   already uses, so the two never disagree about what "day" means).

final Expando<DateTime> _hiddenBoundaryCache = Expando<DateTime>(
  'eventHiddenBoundary',
);

/// The instant at which [event] stops being visible in the overview, or
/// `null` if it can never become invisible (should not occur for a
/// well-formed event, but guards a caller against dividing by nothing).
DateTime hiddenAtBoundary(UnifiedEvent event) =>
    _hiddenBoundaryCache[event] ??= _computeHiddenAtBoundary(event);

DateTime _computeHiddenAtBoundary(UnifiedEvent event) {
  if (event.allDay) return _allDayHiddenBoundary(event);
  if (event.end != null) return event.end!;
  return _noEndHiddenBoundary(event);
}

/// Whether [event] is currently visible in the event overview at [now].
bool isEventVisibleInOverview(UnifiedEvent event, {required DateTime now}) {
  return now.isBefore(hiddenAtBoundary(event));
}

/// Filters [events] to the ones visible in the overview at [now] — running
/// and upcoming only.
List<UnifiedEvent> visibleEventsInOverview(
  List<UnifiedEvent> events, {
  required DateTime now,
}) => events
    .where((UnifiedEvent e) => isEventVisibleInOverview(e, now: now))
    .toList(growable: false);

/// Filters [events] to the ones that have already ended at [now] — the
/// exact complement of [visibleEventsInOverview], used by the overview's
/// "Vergangene Events" section. An event that ended earlier today is past
/// here even though it still lies inside today's default load window.
List<UnifiedEvent> pastEventsInOverview(
  List<UnifiedEvent> events, {
  required DateTime now,
}) => events
    .where((UnifiedEvent e) => !isEventVisibleInOverview(e, now: now))
    .toList(growable: false);

/// The earliest boundary among [events] that is still strictly after [now],
/// or `null` when nothing is scheduled to disappear — used to arm exactly one
/// timer rather than polling.
DateTime? nextVisibilityBoundary(
  List<UnifiedEvent> events, {
  required DateTime now,
}) {
  DateTime? next;
  for (final UnifiedEvent event in events) {
    final DateTime boundary = hiddenAtBoundary(event);
    if (!boundary.isAfter(now)) continue;
    if (next == null || boundary.isBefore(next)) next = boundary;
  }
  return next;
}

DateTime _allDayHiddenBoundary(UnifiedEvent event) {
  final DateTime startDay = calendarDayOf(event.start, allDay: true);
  DateTime lastDay = startDay;
  final DateTime? end = event.end;
  if (end != null && end.isAfter(event.start)) {
    lastDay = calendarDayOf(
      end.subtract(const Duration(microseconds: 1)),
      allDay: true,
    );
  }
  return DateTime(lastDay.year, lastDay.month, lastDay.day + 1);
}

DateTime _noEndHiddenBoundary(UnifiedEvent event) {
  final DateTime startLocal = event.start.toLocal();
  return DateTime(startLocal.year, startLocal.month, startLocal.day + 1);
}
