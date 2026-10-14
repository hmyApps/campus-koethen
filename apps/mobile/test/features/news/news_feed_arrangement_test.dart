// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/events/domain/event_visibility.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:campus_koethen/features/news/domain/news_feed_arrangement.dart';
import 'package:flutter_test/flutter_test.dart';

const NewsTagRef _tag = NewsTagRef(slug: 'news', name: 'News');
const NewsChannelRef _channel = NewsChannelRef(
  slug: 'campus-news',
  name: 'Campus News',
);

NewsArticle _post(String slug) =>
    NewsArticle(slug: slug, title: slug, tag: _tag, primaryChannel: _channel);

NewsArticle _event(
  String slug, {
  required DateTime start,
  DateTime? end,
  bool allDay = false,
}) => NewsArticle(
  slug: slug,
  title: slug,
  tag: _tag,
  primaryChannel: _channel,
  eventStart: start,
  eventEnd: end,
  eventAllDay: allDay,
);

List<String> _slugs(NewsFeedArrangement a) =>
    a.articles.map((NewsArticle x) => x.slug).toList();

void main() {
  final DateTime now = DateTime(2026, 10, 14, 12);

  group('isEndedEventPost', () {
    test('a normal post is never ended', () {
      expect(isEndedEventPost(_post('a'), now: now), isFalse);
    });

    test('a timed event ends exactly at its end instant', () {
      final NewsArticle e = _event(
        'e',
        start: DateTime(2026, 10, 14, 10),
        end: DateTime(2026, 10, 14, 12),
      );
      expect(isEndedEventPost(e, now: now), isTrue);
      expect(
        isEndedEventPost(e, now: now.subtract(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('agrees with the event overview rule for every shape', () {
      final List<NewsArticle> events = <NewsArticle>[
        _event('no-end', start: DateTime(2026, 10, 14, 8)),
        _event('no-end-yesterday', start: DateTime(2026, 10, 13, 8)),
        _event(
          'all-day-today',
          start: DateTime.utc(2026, 10, 14),
          end: DateTime.utc(2026, 10, 15),
          allDay: true,
        ),
        _event(
          'running',
          start: DateTime(2026, 10, 14, 11),
          end: DateTime(2026, 10, 14, 13),
        ),
      ];
      for (final NewsArticle e in events) {
        expect(
          isEndedEventPost(e, now: now),
          !isEventVisibleInOverview(postToUnifiedEvent(e), now: now),
          reason: e.slug,
        );
      }
      expect(isEndedEventPost(events[0], now: now), isFalse);
      expect(isEndedEventPost(events[1], now: now), isTrue);
    });
  });

  group('arrangeNewsFeed', () {
    final NewsArticle past = _event(
      'past',
      start: DateTime(2026, 10, 1, 10),
      end: DateTime(2026, 10, 1, 12),
    );
    final NewsArticle pastOlder = _event(
      'past-older',
      start: DateTime(2026, 9, 1, 10),
      end: DateTime(2026, 9, 1, 12),
    );
    final NewsArticle soon = _event(
      'soon',
      start: DateTime(2026, 10, 15, 10),
      end: DateTime(2026, 10, 15, 12),
    );
    final NewsArticle later = _event(
      'later',
      start: DateTime(2026, 11, 1, 10),
      end: DateTime(2026, 11, 1, 12),
    );
    final NewsArticle running = _event(
      'running',
      start: DateTime(2026, 10, 14, 11),
      end: DateTime(2026, 10, 14, 13),
    );
    // Server order (publishedAt desc), events interleaved with posts.
    final List<NewsArticle> loaded = <NewsArticle>[
      _post('p1'),
      later,
      pastOlder,
      _post('p2'),
      soon,
      past,
      running,
      _post('p3'),
    ];

    test('newest hides ended events and keeps server order', () {
      final NewsFeedArrangement a = arrangeNewsFeed(
        loaded,
        now: now,
        sort: NewsFeedSort.newest,
        showEnded: false,
      );
      expect(_slugs(a), <String>['p1', 'later', 'p2', 'soon', 'running', 'p3']);
      expect(a.hiddenEndedCount, 2);
      expect(a.endedSlugs, <String>{'past', 'past-older'});
    });

    test('newest with showEnded reveals ended events in place', () {
      final NewsFeedArrangement a = arrangeNewsFeed(
        loaded,
        now: now,
        sort: NewsFeedSort.newest,
        showEnded: true,
      );
      expect(_slugs(a), loaded.map((NewsArticle x) => x.slug).toList());
      expect(a.hiddenEndedCount, 0);
      expect(a.endedCount, 2);
      expect(a.isEnded(past), isTrue);
      expect(a.isEnded(soon), isFalse);
    });

    test('chronological puts running/upcoming events first by start, '
        'then posts in server order', () {
      final NewsFeedArrangement a = arrangeNewsFeed(
        loaded,
        now: now,
        sort: NewsFeedSort.chronological,
        showEnded: false,
      );
      expect(_slugs(a), <String>['running', 'soon', 'later', 'p1', 'p2', 'p3']);
      expect(a.hiddenEndedCount, 2);
    });

    test('chronological with showEnded lists ended events most recent first '
        'after the upcoming ones', () {
      final NewsFeedArrangement a = arrangeNewsFeed(
        loaded,
        now: now,
        sort: NewsFeedSort.chronological,
        showEnded: true,
      );
      expect(_slugs(a), <String>[
        'running',
        'soon',
        'later',
        'past',
        'past-older',
        'p1',
        'p2',
        'p3',
      ]);
    });

    test('an event list with only normal posts is untouched', () {
      final List<NewsArticle> posts = <NewsArticle>[_post('a'), _post('b')];
      for (final NewsFeedSort sort in NewsFeedSort.values) {
        final NewsFeedArrangement a = arrangeNewsFeed(
          posts,
          now: now,
          sort: sort,
          showEnded: false,
        );
        expect(_slugs(a), <String>['a', 'b']);
        expect(a.hiddenEndedCount, 0);
      }
    });

    test('everything hidden yields an empty list with a count', () {
      final NewsFeedArrangement a = arrangeNewsFeed(
        <NewsArticle>[past, pastOlder],
        now: now,
        sort: NewsFeedSort.newest,
        showEnded: false,
      );
      expect(a.articles, isEmpty);
      expect(a.hiddenEndedCount, 2);
    });
  });

  group('nextNewsFeedBoundary', () {
    test('is the earliest future end among loaded event posts', () {
      final DateTime? next = nextNewsFeedBoundary(<NewsArticle>[
        _post('p'),
        _event(
          'a',
          start: DateTime(2026, 10, 14, 11),
          end: DateTime(2026, 10, 14, 15),
        ),
        _event(
          'b',
          start: DateTime(2026, 10, 14, 11),
          end: DateTime(2026, 10, 14, 13),
        ),
      ], now: now);
      expect(next, DateTime(2026, 10, 14, 13));
    });

    test('is null without event posts', () {
      expect(nextNewsFeedBoundary(<NewsArticle>[_post('p')], now: now), isNull);
    });
  });

  group('NewsFeedSort storage value', () {
    test('round-trips and falls back to newest', () {
      for (final NewsFeedSort sort in NewsFeedSort.values) {
        expect(NewsFeedSort.fromStorage(sort.storageValue), sort);
      }
      expect(NewsFeedSort.fromStorage(null), NewsFeedSort.newest);
      expect(NewsFeedSort.fromStorage('garbage'), NewsFeedSort.newest);
    });
  });
}
