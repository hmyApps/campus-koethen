// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

/// One validated appointment read directly from the account's Exchange
/// calendar. It is deliberately small: bodies, attendee lists and organizer
/// addresses are not needed for the merged calendar and are never requested.
@immutable
class ExchangeCalendarEvent {
  const ExchangeCalendarEvent({
    required this.id,
    required this.subject,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.isCancelled,
    this.location,
  });

  final String id;
  final String subject;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final bool isCancelled;
  final String? location;

  @override
  bool operator ==(Object other) =>
      other is ExchangeCalendarEvent &&
      other.id == id &&
      other.subject == subject &&
      other.start == start &&
      other.end == end &&
      other.isAllDay == isAllDay &&
      other.isCancelled == isCancelled &&
      other.location == location;

  @override
  int get hashCode =>
      Object.hash(id, subject, start, end, isAllDay, isCancelled, location);
}
