// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_ics_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

DateTime _now() => DateTime.utc(2026, 10, 2, 12);

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('wraps every entry in one VCALENDAR with the expected header', () {
    final String ics = icsFromCalendarEntries(
      const <CalendarEntry>[],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, contains('X-WR-CALNAME:Campus Köthen\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
  });

  test('a timed entry gets UTC DTSTART/DTEND and its UID carries the id', () {
    final CalendarEntry entry = CalendarEntry(
      id: 'timetable:e1',
      source: CalendarSource.timetable,
      title: 'Mathematik 2',
      start: DateTime.utc(2026, 10, 5, 9),
      end: DateTime.utc(2026, 10, 5, 10, 30),
    );

    final String ics = icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    expect(ics, contains('UID:timetable:e1@campus-koethen.app\r\n'));
    expect(ics, contains('DTSTART:20261005T090000Z\r\n'));
    expect(ics, contains('DTEND:20261005T103000Z\r\n'));
    expect(ics, contains('SUMMARY:Mathematik 2\r\n'));
  });

  test('an all-day entry uses VALUE=DATE and defaults DTEND to the exclusive '
      'day after when the source gave no end', () {
    final CalendarEntry entry = CalendarEntry(
      id: 'canteenFavourite:mensa:1',
      source: CalendarSource.canteenFavourite,
      title: 'Bulgur-Pfanne',
      start: DateTime(2026, 10, 5),
      allDay: true,
    );

    final String ics = icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    expect(ics, contains('DTSTART;VALUE=DATE:20261005\r\n'));
    expect(ics, contains('DTEND;VALUE=DATE:20261006\r\n'));
  });

  test('an all-day fallback advances the calendar date across DST', () {
    final tz.Location berlin = tz.getLocation('Europe/Berlin');
    final CalendarEntry entry = CalendarEntry(
      id: 'canteenFavourite:mensa:dst',
      source: CalendarSource.canteenFavourite,
      title: 'Herbstgericht',
      start: tz.TZDateTime(berlin, 2026, 10, 25),
      allDay: true,
    );

    final String ics = icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    expect(ics, contains('DTSTART;VALUE=DATE:20261025\r\n'));
    expect(ics, contains('DTEND;VALUE=DATE:20261026\r\n'));
  });

  group('an all-day DTEND is always the exclusive day after the last day '
      '(VF-N02)', () {
    String exportOf(CalendarEntry entry) => icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    CalendarEntry allDay(DateTime start, DateTime? end) => CalendarEntry(
      id: 'publicCalendar:demo:1',
      source: CalendarSource.publicCalendar,
      title: 'Demo-Termin',
      start: start,
      end: end,
      allDay: true,
    );

    test('an end on the start day never yields DTEND <= DTSTART', () {
      final String ics = exportOf(
        allDay(DateTime(2026, 2, 3), DateTime(2026, 2, 3, 23, 59)),
      );
      expect(ics, contains('DTSTART;VALUE=DATE:20260203\r\n'));
      expect(ics, contains('DTEND;VALUE=DATE:20260204\r\n'));
    });

    test('an end equal to the start still spans that one day', () {
      final String ics = exportOf(
        allDay(DateTime.utc(2026, 2, 3), DateTime.utc(2026, 2, 3)),
      );
      expect(ics, contains('DTSTART;VALUE=DATE:20260203\r\n'));
      expect(ics, contains('DTEND;VALUE=DATE:20260204\r\n'));
    });

    test('a multi-day entry ending 23:59 keeps its last day', () {
      final String ics = exportOf(
        allDay(DateTime(2026, 2, 2), DateTime(2026, 2, 6, 23, 59)),
      );
      expect(ics, contains('DTSTART;VALUE=DATE:20260202\r\n'));
      expect(ics, contains('DTEND;VALUE=DATE:20260207\r\n'));
    });

    test('an already exclusive UTC-midnight end is kept as it is', () {
      final String ics = exportOf(
        allDay(DateTime.utc(2026, 2, 2), DateTime.utc(2026, 2, 7)),
      );
      expect(ics, contains('DTSTART;VALUE=DATE:20260202\r\n'));
      expect(ics, contains('DTEND;VALUE=DATE:20260207\r\n'));
    });

    test('the day after is counted in calendar days across DST', () {
      final tz.Location berlin = tz.getLocation('Europe/Berlin');
      final String ics = exportOf(
        allDay(
          tz.TZDateTime(berlin, 2026, 3, 27),
          tz.TZDateTime(berlin, 2026, 3, 29, 23, 59),
        ),
      );
      expect(ics, contains('DTSTART;VALUE=DATE:20260327\r\n'));
      expect(ics, contains('DTEND;VALUE=DATE:20260330\r\n'));
    });
  });

  test('a cancelled entry is marked STATUS:CANCELLED', () {
    final CalendarEntry entry = CalendarEntry(
      id: 'timetable:e2',
      source: CalendarSource.timetable,
      title: 'Programmieren',
      start: DateTime.utc(2026, 10, 5, 11),
      isCancelled: true,
    );

    final String ics = icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    expect(ics, contains('STATUS:CANCELLED\r\n'));
  });

  test(
    'location and subtitle become LOCATION/DESCRIPTION only when present',
    () {
      final CalendarEntry withBoth = CalendarEntry(
        id: 'timetable:e3',
        source: CalendarSource.timetable,
        title: 'Analysis I',
        start: DateTime.utc(2026, 10, 5, 9),
        location: 'B.202',
        subtitle: 'Prof. Muster',
      );
      final CalendarEntry withNeither = CalendarEntry(
        id: 'moodle:d1',
        source: CalendarSource.moodle,
        title: 'Übungsblatt fällig',
        start: DateTime.utc(2026, 10, 5, 23, 59),
      );

      final String ics = icsFromCalendarEntries(
        <CalendarEntry>[withBoth, withNeither],
        calendarName: 'Campus Köthen',
        now: _now,
      );

      expect(ics, contains('LOCATION:B.202\r\n'));
      expect(ics, contains('DESCRIPTION:Prof. Muster\r\n'));
      expect(ics, isNot(contains('LOCATION:\r\n')));
    },
  );

  test('backslash, semicolon, comma and newline are escaped per RFC 5545, '
      'backslash first so it is never doubled by the later steps', () {
    final CalendarEntry entry = CalendarEntry(
      id: 'publicCalendar:x:1',
      source: CalendarSource.publicCalendar,
      title:
          r'Raum A; Gebäude B, Block\C'
          '\nzweite Zeile',
      start: DateTime.utc(2026, 10, 5, 9),
    );

    final String ics = icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    expect(
      ics,
      contains(r'SUMMARY:Raum A\; Gebäude B\, Block\\C\nzweite Zeile'),
    );
  });

  test('all newline forms are normalized to escaped ICS newlines', () {
    final CalendarEntry entry = CalendarEntry(
      id: 'publicCalendar:x:line-endings',
      source: CalendarSource.publicCalendar,
      title: 'erste\rzweite\r\ndritte\nvier',
      start: DateTime.utc(2026, 10, 5, 9),
    );

    final String ics = icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    expect(
      ics,
      contains(
        r'SUMMARY:erste\nzweite\ndritte\nvier'
        '\r\n',
      ),
    );
  });

  test('an entry with no title falls back to the calendar name', () {
    final CalendarEntry entry = CalendarEntry(
      id: 'timetable:e4',
      source: CalendarSource.timetable,
      title: '',
      start: DateTime.utc(2026, 10, 5, 9),
    );

    final String ics = icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    expect(ics, contains('SUMMARY:Campus Köthen\r\n'));
  });

  test('folds long UTF-8 content lines at at most 75 octets', () {
    final String title = List<String>.filled(18, 'Übung 😀').join(' ');
    final CalendarEntry entry = CalendarEntry(
      id: 'publicCalendar:x:long-title',
      source: CalendarSource.publicCalendar,
      title: title,
      start: DateTime.utc(2026, 10, 5, 9),
    );

    final String ics = icsFromCalendarEntries(
      <CalendarEntry>[entry],
      calendarName: 'Campus Köthen',
      now: _now,
    );

    final List<String> physicalLines = ics
        .split('\r\n')
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    expect(
      physicalLines.map((String line) => utf8.encode(line).length),
      everyElement(lessThanOrEqualTo(75)),
    );
    expect(ics, contains('\r\n '));
    expect(ics.replaceAll('\r\n ', ''), contains('SUMMARY:$title\r\n'));
  });
}
