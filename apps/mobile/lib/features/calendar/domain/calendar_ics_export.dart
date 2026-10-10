// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'calendar_entry.dart';

/// Serialises the already-merged, on-device calendar to one RFC 5545 file —
/// a one-time, local export the reader shares or saves wherever they like,
/// never a server-hosted subscription feed. Every entry here already crossed
/// onto the device through its own source (AGENTS.md §2); this only writes
/// out what is already merged in the app, nothing is fetched to build it.
String icsFromCalendarEntries(
  List<CalendarEntry> entries, {
  required String calendarName,
  DateTime Function() now = DateTime.now,
}) {
  final StringBuffer buffer = StringBuffer();
  _writeContentLine(buffer, 'BEGIN:VCALENDAR');
  _writeContentLine(buffer, 'VERSION:2.0');
  _writeContentLine(buffer, 'PRODID:-//Campus Koethen//Kalenderexport//DE');
  _writeContentLine(buffer, 'CALSCALE:GREGORIAN');
  _writeContentLine(buffer, 'X-WR-CALNAME:${_escape(calendarName)}');

  final String stamp = _utcStamp(now().toUtc());
  for (final CalendarEntry entry in entries) {
    _writeContentLine(buffer, 'BEGIN:VEVENT');
    _writeContentLine(buffer, 'UID:${_escape(entry.id)}@campus-koethen.app');
    _writeContentLine(buffer, 'DTSTAMP:$stamp');
    if (entry.allDay) {
      // DTEND for an all-day event is the exclusive day after its last day.
      // Derived from `CalendarEntry.lastDay` rather than copied from `end`: a
      // source end on the start day (23:59, or equal to the start) would give
      // DTEND <= DTSTART, which RFC 5545 forbids, and a multi-day end at 23:59
      // would drop the last day (VF-N02). Rebuilt from the date parts, so a
      // daylight saving change cannot land it on the same day again.
      final DateTime last = entry.lastDay;
      final DateTime end = DateTime(last.year, last.month, last.day + 1);
      _writeContentLine(buffer, 'DTSTART;VALUE=DATE:${_dateStamp(entry.day)}');
      _writeContentLine(buffer, 'DTEND;VALUE=DATE:${_dateStamp(end)}');
    } else {
      _writeContentLine(buffer, 'DTSTART:${_utcStamp(entry.start.toUtc())}');
      final DateTime? end = entry.end;
      if (end != null) {
        _writeContentLine(buffer, 'DTEND:${_utcStamp(end.toUtc())}');
      }
    }
    final String summary = entry.title.isEmpty ? calendarName : entry.title;
    _writeContentLine(buffer, 'SUMMARY:${_escape(summary)}');
    final String? location = entry.location;
    if (location != null && location.isNotEmpty) {
      _writeContentLine(buffer, 'LOCATION:${_escape(location)}');
    }
    final String? description = entry.subtitle;
    if (description != null && description.isNotEmpty) {
      _writeContentLine(buffer, 'DESCRIPTION:${_escape(description)}');
    }
    if (entry.isCancelled) {
      _writeContentLine(buffer, 'STATUS:CANCELLED');
    }
    _writeContentLine(buffer, 'END:VEVENT');
  }

  _writeContentLine(buffer, 'END:VCALENDAR');
  return buffer.toString();
}

/// RFC 5545 section 3.1 limits one physical content line to 75 octets. A
/// continuation starts with one space, which counts towards that same limit.
/// Iterating Unicode scalar values keeps a fold from splitting a UTF-8 code
/// point (for example an umlaut or emoji) across two physical lines.
void _writeContentLine(StringBuffer output, String line) {
  const int maximumOctets = 75;
  StringBuffer physicalLine = StringBuffer();
  int physicalOctets = 0;
  for (final int rune in line.runes) {
    final String character = String.fromCharCode(rune);
    final int characterOctets = utf8.encode(character).length;
    if (physicalOctets + characterOctets > maximumOctets &&
        physicalLine.isNotEmpty) {
      output
        ..write(physicalLine)
        ..write('\r\n');
      physicalLine = StringBuffer(' ');
      physicalOctets = 1;
    }
    physicalLine.write(character);
    physicalOctets += characterOctets;
  }
  output
    ..write(physicalLine)
    ..write('\r\n');
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

String _pad(int value, int width) => value.toString().padLeft(width, '0');

String _utcStamp(DateTime utc) =>
    '${_pad(utc.year, 4)}${_pad(utc.month, 2)}${_pad(utc.day, 2)}'
    'T${_pad(utc.hour, 2)}${_pad(utc.minute, 2)}${_pad(utc.second, 2)}Z';

String _dateStamp(DateTime date) =>
    '${_pad(date.year, 4)}${_pad(date.month, 2)}${_pad(date.day, 2)}';
