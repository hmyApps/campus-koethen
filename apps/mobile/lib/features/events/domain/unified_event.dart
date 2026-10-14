// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../../../core/theme/hex_color.dart';
import '../../calendar/domain/public_calendar.dart';
import '../../news/data/news_models.dart';

/// Which raw source a [UnifiedEvent] was mapped from.
enum UnifiedEventKind { postEvent, calendarEvent }

/// A source-neutral event, shared by the event overview and the calendar.
///
/// Event posts (`/v1/posts/events`) and public-calendar events
/// (`/v1/calendars/events`) are mapped onto this one shape so the dedup,
/// visibility and sort rules only have to be written once.
///
/// [eventRef] is the stable identity used everywhere an event needs to be
/// referred to across a reload: `post:<slug>` for an event post,
/// `calendar:<eventKey>` for a calendar event (the calendar event's `id` IS
/// its stable `eventKey`, per the backend contract).
@immutable
class UnifiedEvent {
  const UnifiedEvent({
    required this.eventRef,
    required this.kind,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.channelSlug,
    this.calendarSlug,
    this.sourceLabel,
    this.colorArgb,
    this.isCancelled = false,
    this.postSlug,
    this.calendarEventId,
    this.location,
    this.description,
    this.publishedAt,
  });

  final String eventRef;
  final UnifiedEventKind kind;
  final String title;

  /// Absolute start instant.
  final DateTime start;

  /// Absolute end instant, or `null` when the source named none.
  final DateTime? end;

  final bool allDay;

  /// The channel this event's source is attributed to for filtering:
  /// a post event's `primaryChannel.slug`, or a calendar event's mapped
  /// `channelSlug` (`null` when the calendar has none).
  final String? channelSlug;

  /// The calendar slug, set only for [UnifiedEventKind.calendarEvent].
  final String? calendarSlug;

  final String? sourceLabel;
  final int? colorArgb;
  final bool isCancelled;

  /// The post slug, set only for [UnifiedEventKind.postEvent] (for
  /// navigating to the post detail).
  final String? postSlug;

  /// The raw calendar event id (== its `eventKey`), set only for
  /// [UnifiedEventKind.calendarEvent].
  final String? calendarEventId;

  final String? location;
  final String? description;

  /// When the event was announced: an event post's `publishedAt`. Calendar
  /// events carry no publication date, so this is `null` for them (and for
  /// a post whose payload named none) — the "Neueste zuerst" order then
  /// falls back to [start].
  final DateTime? publishedAt;

  /// The key filter options are grouped by: the mapped channel when one
  /// exists, otherwise the calendar's own slug for an unmapped calendar.
  /// Never both — see `docs` on `event_source_filter.dart`.
  String get filterSourceKey => channelSlug ?? calendarSlug ?? eventRef;

  @override
  bool operator ==(Object other) =>
      other is UnifiedEvent &&
      other.eventRef == eventRef &&
      other.kind == kind &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.channelSlug == channelSlug &&
      other.calendarSlug == calendarSlug &&
      other.publishedAt == publishedAt;

  @override
  int get hashCode => Object.hash(
    eventRef,
    kind,
    title,
    start,
    end,
    allDay,
    channelSlug,
    calendarSlug,
    publishedAt,
  );

  @override
  String toString() =>
      'UnifiedEvent($eventRef, $kind, start: $start, allDay: $allDay, '
      'channel: $channelSlug, calendar: $calendarSlug)';
}

/// Maps an event post to its [UnifiedEvent]. The caller must only pass posts
/// for which [NewsArticle.isEventPost] is true.
UnifiedEvent postToUnifiedEvent(NewsArticle post) {
  assert(post.eventStart != null, 'only event posts map to UnifiedEvent');
  return UnifiedEvent(
    eventRef: 'post:${post.slug}',
    kind: UnifiedEventKind.postEvent,
    title: post.title,
    start: post.eventStart!,
    end: post.eventEnd,
    allDay: post.eventAllDay,
    channelSlug: post.primaryChannel.slug,
    sourceLabel: post.primaryChannel.name,
    colorArgb: _parseColorArgb(post.primaryChannel.colorHex),
    postSlug: post.slug,
    publishedAt: post.publishedAt,
  );
}

/// Maps a public-calendar event to its [UnifiedEvent]. [channelSlug] is the
/// calendar's own mapped channel slug (from `PublicCalendar.channelSlug`),
/// `null` when it has none.
UnifiedEvent calendarToUnifiedEvent(
  PublicCalendarEvent event, {
  String? channelSlug,
  String? calendarName,
  String? colorHex,
}) {
  return UnifiedEvent(
    eventRef: 'calendar:${event.id}',
    kind: UnifiedEventKind.calendarEvent,
    title: event.title,
    start: event.start,
    end: event.end,
    allDay: event.allDay,
    channelSlug: channelSlug,
    calendarSlug: event.calendarSlug,
    sourceLabel: calendarName ?? event.calendarSlug,
    colorArgb: _parseColorArgb(colorHex),
    isCancelled: event.status == 'cancelled',
    calendarEventId: event.id,
    location: event.location,
    description: event.description,
  );
}

int? _parseColorArgb(String? hex) => parseHexColorArgb(hex);
