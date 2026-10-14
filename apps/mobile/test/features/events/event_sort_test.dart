// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/events/domain/event_sort.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:flutter_test/flutter_test.dart';

UnifiedEvent ev(
  String ref, {
  required DateTime start,
  DateTime? publishedAt,
  bool allDay = false,
  String title = 'Event',
  UnifiedEventKind kind = UnifiedEventKind.postEvent,
}) => UnifiedEvent(
  eventRef: ref,
  kind: kind,
  title: title,
  start: start,
  allDay: allDay,
  publishedAt: publishedAt,
);

List<String> refs(List<UnifiedEvent> events) =>
    events.map((UnifiedEvent e) => e.eventRef).toList();

void main() {
  group('EventSortOrder storage', () {
    test('round-trips every value through its storage name', () {
      for (final EventSortOrder order in EventSortOrder.values) {
        expect(EventSortOrder.fromStorage(order.storageValue), order);
      }
    });

    test('defaults to chronological for a missing or unknown value', () {
      expect(EventSortOrder.fromStorage(null), EventSortOrder.chronological);
      expect(EventSortOrder.fromStorage('bogus'), EventSortOrder.chronological);
      expect(EventSortOrder.defaultOrder, EventSortOrder.chronological);
    });
  });

  group('newest first', () {
    test('sorts event posts by publishedAt descending', () {
      final List<UnifiedEvent> sorted = sortCurrentEvents(<UnifiedEvent>[
        ev(
          'post:old',
          start: DateTime.utc(2026, 9, 2),
          publishedAt: DateTime.utc(2026, 8, 1),
        ),
        ev(
          'post:new',
          start: DateTime.utc(2026, 9, 10),
          publishedAt: DateTime.utc(2026, 8, 20),
        ),
      ], EventSortOrder.newestFirst);
      expect(refs(sorted), <String>['post:new', 'post:old']);
    });

    test('an event without publishedAt falls back to its start', () {
      final List<UnifiedEvent> sorted = sortCurrentEvents(<UnifiedEvent>[
        ev(
          'post:published',
          start: DateTime.utc(2026, 9, 30),
          publishedAt: DateTime.utc(2026, 8, 15),
        ),
        ev(
          'calendar:later-start',
          start: DateTime.utc(2026, 8, 25),
          kind: UnifiedEventKind.calendarEvent,
        ),
        ev(
          'calendar:early-start',
          start: DateTime.utc(2026, 8, 1),
          kind: UnifiedEventKind.calendarEvent,
        ),
      ], EventSortOrder.newestFirst);
      expect(refs(sorted), <String>[
        'calendar:later-start',
        'post:published',
        'calendar:early-start',
      ]);
    });

    test('equal sort keys fall back to the chronological order, '
        'independent of the input order', () {
      final DateTime published = DateTime.utc(2026, 8, 15);
      final List<UnifiedEvent> input = <UnifiedEvent>[
        ev('post:b', start: DateTime.utc(2026, 9, 2), publishedAt: published),
        ev('post:a', start: DateTime.utc(2026, 9, 2), publishedAt: published),
        ev('post:c', start: DateTime.utc(2026, 9, 1), publishedAt: published),
      ];
      const List<String> expected = <String>['post:c', 'post:a', 'post:b'];
      expect(
        refs(sortCurrentEvents(input, EventSortOrder.newestFirst)),
        expected,
      );
      expect(
        refs(
          sortCurrentEvents(
            input.reversed.toList(),
            EventSortOrder.newestFirst,
          ),
        ),
        expected,
      );
    });
  });

  group('section orders', () {
    final List<UnifiedEvent> input = <UnifiedEvent>[
      ev(
        'post:mid',
        start: DateTime.utc(2026, 8, 10),
        publishedAt: DateTime.utc(2026, 8, 1),
      ),
      ev(
        'post:late',
        start: DateTime.utc(2026, 8, 20),
        publishedAt: DateTime.utc(2026, 7, 1),
      ),
      ev(
        'post:early',
        start: DateTime.utc(2026, 8, 1),
        publishedAt: DateTime.utc(2026, 8, 5),
      ),
    ];

    test('chronological: current events start ascending', () {
      expect(
        refs(sortCurrentEvents(input, EventSortOrder.chronological)),
        <String>['post:early', 'post:mid', 'post:late'],
      );
    });

    test('chronological: past events most recently held first', () {
      expect(
        refs(sortPastEvents(input, EventSortOrder.chronological)),
        <String>['post:late', 'post:mid', 'post:early'],
      );
    });

    test('newest first applies to both sections alike', () {
      const List<String> expected = <String>[
        'post:early',
        'post:mid',
        'post:late',
      ];
      expect(
        refs(sortCurrentEvents(input, EventSortOrder.newestFirst)),
        expected,
      );
      expect(refs(sortPastEvents(input, EventSortOrder.newestFirst)), expected);
    });

    test('chronological past ties stay deterministic', () {
      final DateTime start = DateTime.utc(2026, 8, 10);
      final List<UnifiedEvent> ties = <UnifiedEvent>[
        ev('post:b', start: start),
        ev('post:a', start: start),
        ev('post:allday', start: start, allDay: true),
      ];
      final List<String> forward = refs(
        sortPastEvents(ties, EventSortOrder.chronological),
      );
      final List<String> backward = refs(
        sortPastEvents(ties.reversed.toList(), EventSortOrder.chronological),
      );
      expect(forward, backward);
    });

    test('does not mutate its input', () {
      final List<UnifiedEvent> copy = List<UnifiedEvent>.of(input);
      sortPastEvents(input, EventSortOrder.chronological);
      sortCurrentEvents(input, EventSortOrder.newestFirst);
      expect(input, copy);
    });
  });

  test('postToUnifiedEvent carries publishedAt', () {
    final DateTime published = DateTime.utc(2026, 8, 3, 10);
    final UnifiedEvent event = postToUnifiedEvent(
      NewsArticle(
        slug: 'sommerfest',
        title: 'Sommerfest (Demo)',
        tag: const NewsTagRef(slug: 'event', name: 'Event'),
        primaryChannel: const NewsChannelRef(slug: 'campus', name: 'Campus'),
        publishedAt: published,
        eventStart: DateTime.utc(2026, 9, 1, 16),
      ),
    );
    expect(event.publishedAt, published);
  });
}
