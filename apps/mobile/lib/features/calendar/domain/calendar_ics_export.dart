// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'calendar_entry.dart';

/// Serialises the already-merged, on-device calendar to one RFC 5545 file —
/// a one-time, local export the reader shares or saves wherever they like,
/// never a server-hosted subscription feed. Every entry here already crossed
/// onto the device through its own source (AGENTS.md §2); this only writes
/// out what is already merged in the app, nothing is fetched to build it.
///
/// Deliberately does not fold long lines at 75 octets the way RFC 5545
/// recommends: every mainstream calendar app this is meant to be imported
/// into (Google Calendar, Apple Calendar, Outlook) parses an unfolded line
/// without complaint, and folding correctly for multi-byte UTF-8 text adds
/// real complexity for a one-shot personal export.
String icsFromCalendarEntries(
  List<CalendarEntry> entries, {
  required String calendarName,
  DateTime Function() now = DateTime.now,
}) {
  final StringBuffer buffer = StringBuffer()
    ..write('BEGIN:VCALENDAR\r\n')
    ..write('VERSION:2.0\r\n')
    ..write('PRODID:-//Campus Koethen//Kalenderexport//DE\r\n')
    ..write('CALSCALE:GREGORIAN\r\n')
    ..write('X-WR-CALNAME:${_escape(calendarName)}\r\n');

  final String stamp = _utcStamp(now().toUtc());
  for (final CalendarEntry entry in entries) {
    buffer.write('BEGIN:VEVENT\r\n');
    buffer.write('UID:${_escape(entry.id)}@campus-koethen.app\r\n');
    buffer.write('DTSTAMP:$stamp\r\n');
    if (entry.allDay) {
      // DTEND for an all-day event is the exclusive day-after, the same
      // convention `CalendarEntry.lastDay`'s own doc comment already
      // documents this app's all-day entries as using.
      final DateTime end = entry.end ?? _nextCalendarDay(entry.start);
      buffer.write('DTSTART;VALUE=DATE:${_dateStamp(entry.start)}\r\n');
      buffer.write('DTEND;VALUE=DATE:${_dateStamp(end)}\r\n');
    } else {
      buffer.write('DTSTART:${_utcStamp(entry.start.toUtc())}\r\n');
      final DateTime? end = entry.end;
      if (end != null) {
        buffer.write('DTEND:${_utcStamp(end.toUtc())}\r\n');
      }
    }
    final String summary = entry.title.isEmpty ? calendarName : entry.title;
    buffer.write('SUMMARY:${_escape(summary)}\r\n');
    final String? location = entry.location;
    if (location != null && location.isNotEmpty) {
      buffer.write('LOCATION:${_escape(location)}\r\n');
    }
    final String? description = entry.subtitle;
    if (description != null && description.isNotEmpty) {
      buffer.write('DESCRIPTION:${_escape(description)}\r\n');
    }
    if (entry.isCancelled) {
      buffer.write('STATUS:CANCELLED\r\n');
    }
    buffer.write('END:VEVENT\r\n');
  }

  buffer.write('END:VCALENDAR\r\n');
  return buffer.toString();
}

/// RFC 5545 §3.3.11 TEXT escaping — backslash first, so escaping the other
/// three characters never doubles up on a backslash this step just added.
String _escape(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\r', '\\n')
    .replaceAll('\n', '\\n');

DateTime _nextCalendarDay(DateTime date) => date.isUtc
    ? DateTime.utc(date.year, date.month, date.day + 1)
    : DateTime(date.year, date.month, date.day + 1);

String _pad(int value, int width) => value.toString().padLeft(width, '0');

String _utcStamp(DateTime utc) =>
    '${_pad(utc.year, 4)}${_pad(utc.month, 2)}${_pad(utc.day, 2)}'
    'T${_pad(utc.hour, 2)}${_pad(utc.minute, 2)}${_pad(utc.second, 2)}Z';

String _dateStamp(DateTime date) =>
    '${_pad(date.year, 4)}${_pad(date.month, 2)}${_pad(date.day, 2)}';
