// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/events/domain/event_past_window.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:flutter_test/flutter_test.dart';

UnifiedEvent ev(String ref, UnifiedEventKind kind, {String title = 'Event'}) =>
    UnifiedEvent(
      eventRef: ref,
      kind: kind,
      title: title,
      start: DateTime.utc(2026, 8, 1, 10),
    );

void main() {
  group('pastEventsWindow', () {
    test('spans the last 180 local days up to and including today', () {
      final PastEventsWindow window = pastEventsWindow(
        DateTime(2026, 10, 14, 18),
      );
      expect(window.from, '2026-04-17');
      expect(window.to, '2026-10-14');
    });

    test('always names both bounds explicitly as YYYY-MM-DD', () {
      final PastEventsWindow window = pastEventsWindow(
        DateTime(2026, 3, 5, 0, 5),
        days: 10,
      );
      expect(window.from, '2026-02-23');
      expect(window.to, '2026-03-05');
    });

    test('uses the local calendar day of a UTC instant', () {
      final DateTime now = DateTime.utc(2026, 10, 14, 12);
      final DateTime local = now.toLocal();
      final PastEventsWindow window = pastEventsWindow(now, days: 0);
      final String expected =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      expect(window.to, expected);
      expect(window.from, expected);
    });

    test('the default span stays inside the API maximum range', () {
      expect(kPastEventsWindowDays, 180);
      expect(kPastEventsWindowDays, lessThanOrEqualTo(400));
    });
  });

  group('unionEventsByRef', () {
    test('keeps the primary copy of an event present in both lists', () {
      final UnifiedEvent current = ev(
        'post:a',
        UnifiedEventKind.postEvent,
        title: 'current',
      );
      final UnifiedEvent stale = ev(
        'post:a',
        UnifiedEventKind.postEvent,
        title: 'stale',
      );
      final UnifiedEvent onlyPast = ev(
        'calendar:b',
        UnifiedEventKind.calendarEvent,
      );
      final List<UnifiedEvent> union = unionEventsByRef(
        primary: <UnifiedEvent>[current],
        secondary: <UnifiedEvent>[stale, onlyPast],
      );
      expect(union.map((UnifiedEvent e) => e.eventRef), <String>[
        'post:a',
        'calendar:b',
      ]);
      expect(union.first.title, 'current');
    });

    test('returns the primary list unchanged when secondary is empty', () {
      final List<UnifiedEvent> primary = <UnifiedEvent>[
        ev('post:a', UnifiedEventKind.postEvent),
      ];
      expect(
        unionEventsByRef(primary: primary, secondary: const <UnifiedEvent>[]),
        primary,
      );
    });
  });
}
