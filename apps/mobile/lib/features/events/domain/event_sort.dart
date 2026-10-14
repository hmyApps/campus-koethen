// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'unified_event.dart';

/// The reader's chosen order for the event overview ("Sortierung" in the
/// source filter sheet). Persisted as [storageValue].
enum EventSortOrder {
  /// By start: running/upcoming events ascending, past events with the most
  /// recently held one first. The default.
  chronological('chronological'),

  /// Most recently announced first — event posts by `publishedAt`
  /// descending; calendar events (no publication date) by their start.
  newestFirst('newestFirst');

  const EventSortOrder(this.storageValue);

  /// The stable value written to the key-value store.
  final String storageValue;

  static const EventSortOrder defaultOrder = EventSortOrder.chronological;

  /// Parses a stored value; anything missing or unknown is [defaultOrder].
  static EventSortOrder fromStorage(String? value) {
    for (final EventSortOrder order in values) {
      if (order.storageValue == value) return order;
    }
    return defaultOrder;
  }
}

/// Deterministic order for the merged current/running event list: start
/// ascending, all-day before timed within the same start/day, then title,
/// then [UnifiedEvent.eventRef] as a stable final tie-breaker.
int compareUnifiedEvents(UnifiedEvent a, UnifiedEvent b) {
  final int byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;

  final int byAllDay = (a.allDay == b.allDay)
      ? 0
      : (a.allDay ? -1 : 1); // all-day sorts first
  if (byAllDay != 0) return byAllDay;

  final int byTitle = a.title.compareTo(b.title);
  if (byTitle != 0) return byTitle;

  return a.eventRef.compareTo(b.eventRef);
}

/// Past events, chronologically: the most recently started first, with the
/// remaining ties broken exactly like [compareUnifiedEvents].
int _comparePastChronological(UnifiedEvent a, UnifiedEvent b) {
  final int byStart = b.start.compareTo(a.start);
  if (byStart != 0) return byStart;
  return compareUnifiedEvents(a, b);
}

/// "Neueste zuerst": the announcement instant ([UnifiedEvent.publishedAt],
/// falling back to [UnifiedEvent.start] where there is none) descending,
/// then [compareUnifiedEvents] for a deterministic result on ties.
int _compareNewestFirst(UnifiedEvent a, UnifiedEvent b) {
  final int byAnnounced = (b.publishedAt ?? b.start).compareTo(
    a.publishedAt ?? a.start,
  );
  if (byAnnounced != 0) return byAnnounced;
  return compareUnifiedEvents(a, b);
}

/// Sorts a copy of [events] with [compareUnifiedEvents].
List<UnifiedEvent> sortedUnifiedEvents(List<UnifiedEvent> events) =>
    List<UnifiedEvent>.of(events)..sort(compareUnifiedEvents);

/// Sorts a copy of the running/upcoming [events] in [order].
List<UnifiedEvent> sortCurrentEvents(
  List<UnifiedEvent> events,
  EventSortOrder order,
) => List<UnifiedEvent>.of(events)
  ..sort(switch (order) {
    EventSortOrder.chronological => compareUnifiedEvents,
    EventSortOrder.newestFirst => _compareNewestFirst,
  });

/// Sorts a copy of the already-ended [events] in [order].
List<UnifiedEvent> sortPastEvents(
  List<UnifiedEvent> events,
  EventSortOrder order,
) => List<UnifiedEvent>.of(events)
  ..sort(switch (order) {
    EventSortOrder.chronological => _comparePastChronological,
    EventSortOrder.newestFirst => _compareNewestFirst,
  });
