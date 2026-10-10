// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../../../core/network/json.dart';
import '../../../core/time/all_day_post_start.dart';
import 'unified_event.dart';

/// One entry of the offline saved-events list ("Meine gemerkten Events").
///
/// A self-contained snapshot, not a reference: the list must keep working
/// fully offline and must keep showing a saved event even after it vanishes
/// from a live response (see [isOrphaned]), so every field the UI needs is
/// copied in at save time rather than looked up later.
@immutable
class SavedEventSnapshot {
  const SavedEventSnapshot({
    required this.eventRef,
    required this.kind,
    required this.title,
    required this.start,
    required this.savedAt,
    this.end,
    this.allDay = false,
    this.channelSlug,
    this.calendarSlug,
    this.sourceLabel,
    this.colorArgb,
    this.isCancelled = false,
    this.location,
    this.description,
    this.isOrphaned = false,
  });

  final String eventRef;
  final UnifiedEventKind kind;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String? channelSlug;
  final String? calendarSlug;
  final String? sourceLabel;
  final int? colorArgb;
  final bool isCancelled;

  /// Copied in at save time, not looked up later: the saved list has to render
  /// the same card offline that the overview rendered online. Without these two
  /// a bookmarked event lost exactly the information it was bookmarked for.
  final String? location;
  final String? description;

  final DateTime savedAt;

  /// Set when a successful load of this event's source covered its start and
  /// still did not include it — see the repository-level orphan rule. Never
  /// set on a failure, a timeout, being offline, or a load that never
  /// actually covered this event's start.
  final bool isOrphaned;

  SavedEventSnapshot copyWith({bool? isOrphaned}) => SavedEventSnapshot(
    eventRef: eventRef,
    kind: kind,
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    channelSlug: channelSlug,
    calendarSlug: calendarSlug,
    sourceLabel: sourceLabel,
    colorArgb: colorArgb,
    isCancelled: isCancelled,
    location: location,
    description: description,
    savedAt: savedAt,
    isOrphaned: isOrphaned ?? this.isOrphaned,
  );

  /// Renders this snapshot back into a [UnifiedEvent] for display. The saved
  /// list shows snapshots only; the calendar reconciles them against live
  /// entries in `calendar_merge.savedEventEntriesForCalendar`, which reuses
  /// `event_dedup.isDuplicateCalendarEvent` rather than repeating the rule.
  UnifiedEvent toUnifiedEvent() => UnifiedEvent(
    eventRef: eventRef,
    kind: kind,
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    channelSlug: channelSlug,
    calendarSlug: calendarSlug,
    sourceLabel: sourceLabel,
    colorArgb: colorArgb,
    isCancelled: isCancelled,
    location: location,
    description: description,
  );

  static SavedEventSnapshot fromUnifiedEvent(
    UnifiedEvent event, {
    required DateTime savedAt,
  }) => SavedEventSnapshot(
    eventRef: event.eventRef,
    kind: event.kind,
    title: event.title,
    start: event.start,
    end: event.end,
    allDay: event.allDay,
    channelSlug: event.channelSlug,
    calendarSlug: event.calendarSlug,
    sourceLabel: event.sourceLabel,
    colorArgb: event.colorArgb,
    isCancelled: event.isCancelled,
    location: event.location,
    description: event.description,
    savedAt: savedAt,
  );

  static SavedEventSnapshot? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? eventRef = asString(map['eventRef']);
    final String? title = asString(map['title']);
    final DateTime? start = asDateTime(map['start']);
    final DateTime? savedAt = asDateTime(map['savedAt']);
    final UnifiedEventKind? kind = _kindFromStorage(asString(map['kind']));
    if (eventRef == null ||
        title == null ||
        start == null ||
        savedAt == null ||
        kind == null) {
      return null;
    }
    final bool allDay = asBool(map['allDay']) ?? false;
    return SavedEventSnapshot(
      eventRef: eventRef,
      kind: kind,
      title: title,
      // Bookmarks written before VF-N01 hold an all-day post start as the
      // instant of local midnight; read them like a fresh API answer.
      start: allDay && kind == UnifiedEventKind.postEvent
          ? allDayPostStart(start)
          : start,
      end: asDateTime(map['end']),
      allDay: allDay,
      channelSlug: asString(map['channelSlug']),
      calendarSlug: asString(map['calendarSlug']),
      sourceLabel: asString(map['sourceLabel']),
      // Absent in entries written before these fields existed — read as null
      // rather than rejecting the whole snapshot.
      colorArgb: asInt(map['colorArgb']),
      isCancelled: asBool(map['isCancelled']) ?? false,
      location: asString(map['location']),
      description: asString(map['description']),
      savedAt: savedAt,
      isOrphaned: asBool(map['isOrphaned']) ?? false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'eventRef': eventRef,
    'kind': _kindToStorage(kind),
    'title': title,
    'start': start.toUtc().toIso8601String(),
    'end': end?.toUtc().toIso8601String(),
    'allDay': allDay,
    'channelSlug': channelSlug,
    'calendarSlug': calendarSlug,
    'sourceLabel': sourceLabel,
    'colorArgb': colorArgb,
    'isCancelled': isCancelled,
    'location': location,
    'description': description,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'isOrphaned': isOrphaned,
  };

  static List<SavedEventSnapshot> listFromJson(Object? json) => asList(
    json,
  ).map(SavedEventSnapshot.fromJson).whereType<SavedEventSnapshot>().toList();

  static String _kindToStorage(UnifiedEventKind kind) => switch (kind) {
    UnifiedEventKind.postEvent => 'post-event',
    UnifiedEventKind.calendarEvent => 'calendar-event',
  };

  static UnifiedEventKind? _kindFromStorage(String? value) => switch (value) {
    'post-event' => UnifiedEventKind.postEvent,
    'calendar-event' => UnifiedEventKind.calendarEvent,
    _ => null,
  };
}
