// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/calendar/application/calendar_merge.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/events/domain/event_dedup.dart';
import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// VF-N01: which day an all-day event post lands on.
///
/// `eventStart` is a Strapi `datetime`. The editorial team enters an all-day
/// event as 00:00 Berlin time, which arrives as 22:00Z (MESZ) or 23:00Z (MEZ)
/// the evening before. All-day values are read as UTC date markers, so the
/// post showed one day early everywhere — article, calendar, reminders,
/// widget, ICS — and never matched its public-calendar twin.
///
/// The inputs are built as **local** midnight, so the expectations hold in
/// any runner zone; CI pins `TZ=Europe/Berlin`, where they exercise exactly
/// the 22:00Z/23:00Z values above.
NewsArticle _post({
  required DateTime start,
  DateTime? end,
  bool allDay = true,
  String slug = 'demo-fest',
}) => NewsArticle.fromJson(<String, Object?>{
  'slug': slug,
  'title': 'Demo-Fest',
  'tag': <String, Object?>{'slug': 'event'},
  'primaryChannel': <String, Object?>{'slug': 'demo-kanal', 'name': 'Demo'},
  'eventStart': start.toUtc().toIso8601String(),
  'eventEnd': end?.toUtc().toIso8601String(),
  'eventAllDay': allDay,
})!;

CalendarEntry _calendarEntryOf(NewsArticle post) =>
    savedEventSnapshotToCalendarEntry(
      SavedEventSnapshot.fromUnifiedEvent(
        postToUnifiedEvent(post),
        savedAt: DateTime.utc(2026, 6, 1),
      ),
    );

void main() {
  for (final (String name, DateTime midnight) in <(String, DateTime)>[
    ('MESZ', DateTime(2026, 7, 1)),
    ('MEZ', DateTime(2026, 12, 1)),
  ]) {
    group('an all-day post entered as 00:00 $name', () {
      final DateTime day = DateTime(midnight.year, midnight.month, 1);

      test('keeps its own date as the event start', () {
        final NewsArticle post = _post(start: midnight);
        expect(post.eventAllDay, isTrue);
        expect(calendarDayOf(post.eventStart!, allDay: true), day);
        expect(post.eventStart, DateTime.utc(midnight.year, midnight.month));
      });

      test('lands on that date in the calendar', () {
        final CalendarEntry entry = _calendarEntryOf(_post(start: midnight));
        expect(entry.day, day);
        expect(entry.lastDay, day);
      });

      test('keeps both days of a two-day event ending 23:59', () {
        final CalendarEntry entry = _calendarEntryOf(
          _post(
            start: midnight,
            end: DateTime(midnight.year, midnight.month, 2, 23, 59),
          ),
        );
        expect(entry.day, day);
        expect(entry.lastDay, DateTime(midnight.year, midnight.month, 2));
      });

      test(
        'keeps its last day when the end is the exclusive next midnight',
        () {
          final CalendarEntry entry = _calendarEntryOf(
            _post(
              start: midnight,
              end: DateTime(midnight.year, midnight.month, 3),
            ),
          );
          expect(entry.day, day);
          expect(entry.lastDay, DateTime(midnight.year, midnight.month, 2));
        },
      );

      test('is recognised as the twin of the same public-calendar day', () {
        // The worker encodes the public calendar's all-day date as UTC
        // midnight; the post must name the same start minute to match.
        final UnifiedEvent post = postToUnifiedEvent(_post(start: midnight));
        final UnifiedEvent twin = UnifiedEvent(
          eventRef: 'calendar:demo',
          kind: UnifiedEventKind.calendarEvent,
          title: 'Demo-Fest',
          start: DateTime.utc(midnight.year, midnight.month),
          allDay: true,
          channelSlug: 'demo-kanal',
        );
        expect(
          mergeEventSources(
            postEvents: <UnifiedEvent>[post],
            calendarEvents: <UnifiedEvent>[twin],
          ),
          <UnifiedEvent>[post],
        );
      });
    });
  }

  test('a timed post keeps its exact instant', () {
    final DateTime start = DateTime(2026, 7, 1, 0, 30);
    final NewsArticle post = _post(start: start, allDay: false);
    expect(post.eventStart, start.toUtc());
  });

  test('an all-day post the server already sends as UTC midnight keeps that '
      'date', () {
    final NewsArticle post = NewsArticle.fromJson(<String, Object?>{
      'slug': 'demo-utc',
      'title': 'Demo',
      'tag': <String, Object?>{'slug': 'event'},
      'primaryChannel': <String, Object?>{'slug': 'demo-kanal'},
      'eventStart': '2026-07-01T00:00:00.000Z',
      'eventAllDay': true,
    })!;
    expect(post.eventStart, DateTime.utc(2026, 7, 1));
  });

  test('public-calendar all-day dates are not shifted', () {
    // The normalisation lives at the post source only; the UTC-midnight
    // encoding of the other all-day sources is read exactly as before.
    final CalendarEntry entry = CalendarEntry(
      id: 'publicCalendar:demo:1',
      source: CalendarSource.publicCalendar,
      title: 'Demo',
      start: DateTime.utc(2026, 7, 1),
      end: DateTime.utc(2026, 7, 2),
      allDay: true,
    );
    expect(entry.day, DateTime(2026, 7, 1));
    expect(entry.lastDay, DateTime(2026, 7, 1));
  });
}
