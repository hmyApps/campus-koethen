// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/network/api_failure.dart';
import 'package:campus_koethen/features/events/data/event_posts_repository.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:campus_koethen/features/news/data/news_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';

Map<String, dynamic> _article(String slug) => <String, dynamic>{
  'slug': slug,
  'title': 'Event $slug',
  'publishedAt': '2026-08-01T09:00:00.000Z',
  'heroImage': null,
  'channels': <Object>[],
  'tag': <String, dynamic>{'slug': 'event', 'name': 'Event'},
  'primaryChannel': <String, dynamic>{
    'slug': 'campus-events',
    'name': 'Campus Events',
  },
  'sourceName': null,
  'sourceUrl': null,
  'content': <Object>[],
  'eventStart': '2026-08-10T18:00:00.000Z',
  'eventEnd': '2026-08-10T20:00:00.000Z',
  'eventAllDay': false,
};

/// Scripts `totalPages` worth of pages, each with one article, and records
/// every requested `from`/`to`/`page`.
class _ScriptedEventPages {
  _ScriptedEventPages({required this.totalPages, this.failOnPage});

  final int totalPages;

  /// Throws a connection error once this page is requested, if set.
  final int? failOnPage;

  final List<String?> requestedFrom = <String?>[];
  final List<String?> requestedTo = <String?>[];
  final List<int> requestedPages = <int>[];

  FakeHttpAdapter get adapter => FakeHttpAdapter((RequestOptions options) {
    final int page =
        int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
    requestedPages.add(page);
    requestedFrom.add(options.queryParameters['from'] as String?);
    requestedTo.add(options.queryParameters['to'] as String?);

    if (failOnPage == page) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }

    return FakeHttpResponse(
      envelope(
        <Object>[_article('p$page')],
        meta: <String, dynamic>{
          'from': '2026-08-01',
          'to': '2026-08-31',
          'pagination': <String, dynamic>{
            'page': page,
            'pageSize': kEventPostsPageSize,
            'total': totalPages,
            'totalPages': totalPages,
          },
        },
      ),
    );
  });
}

/// An in-memory cache that remembers which keys were written.
class _RecordingContentCache extends MemoryContentCache {
  final List<String> writtenKeys = <String>[];

  @override
  Future<void> write(String key, Map<String, dynamic> payload) {
    writtenKeys.add(key);
    return super.write(key, payload);
  }
}

EventPostsRepository _repository(
  FakeHttpAdapter adapter, {
  ContentCache? cache,
}) => EventPostsRepository(
  NewsRepository(
    client: fakeApiClient(adapter),
    cache: cache ?? SafeContentCache(MemoryContentCache()),
  ),
);

void main() {
  group('pagination', () {
    test(
      'follows totalPages until exhausted, well under the ceiling',
      () async {
        final _ScriptedEventPages pages = _ScriptedEventPages(totalPages: 3);
        final EventPostsResult result = await _repository(
          pages.adapter,
        ).fetchAllEventPosts(locale: 'de');

        expect(result.articles, hasLength(3));
        expect(result.isTruncated, isFalse);
        // Page 1 first — it resolves the window — then the rest together, so
        // their arrival order is not fixed.
        expect(pages.requestedPages.first, 1);
        expect(pages.requestedPages, unorderedEquals(<int>[1, 2, 3]));
        expect(
          result.articles.map((NewsArticle a) => a.slug),
          <String>['p1', 'p2', 'p3'],
          reason:
              'the pages are folded in page order, whatever order they '
              'came back in',
        );
      },
    );

    test('stops at the 10×50 ceiling and flags isTruncated', () async {
      final _ScriptedEventPages pages = _ScriptedEventPages(totalPages: 25);
      final EventPostsResult result = await _repository(
        pages.adapter,
      ).fetchAllEventPosts(locale: 'de');

      expect(result.articles, hasLength(kEventPostsMaxPages));
      expect(result.isTruncated, isTrue);
      expect(
        pages.requestedPages,
        unorderedEquals(List<int>.generate(10, (int i) => i + 1)),
      );
      expect(
        result.articles.map((NewsArticle a) => a.slug),
        List<String>.generate(10, (int i) => 'p${i + 1}'),
      );
    });

    test('a single page never sets isTruncated', () async {
      final _ScriptedEventPages pages = _ScriptedEventPages(totalPages: 1);
      final EventPostsResult result = await _repository(
        pages.adapter,
      ).fetchAllEventPosts(locale: 'de');

      expect(result.articles, hasLength(1));
      expect(result.isTruncated, isFalse);
    });

    test('reuses the window resolved by page 1 for every later page, never the '
        'request bounds', () async {
      final _ScriptedEventPages pages = _ScriptedEventPages(totalPages: 3);
      await _repository(pages.adapter).fetchAllEventPosts(locale: 'de');

      // The client sent no from/to of its own...
      expect(pages.requestedFrom.first, isNull);
      expect(pages.requestedTo.first, isNull);
      // ...but every later page repeats the server-resolved window
      // explicitly, so a mid-load default change can never split the load
      // across two different windows.
      expect(pages.requestedFrom.skip(1), everyElement('2026-08-01'));
      expect(pages.requestedTo.skip(1), everyElement('2026-08-31'));
    });

    test('the resolved window reaches the caller on the result', () async {
      final _ScriptedEventPages pages = _ScriptedEventPages(totalPages: 1);
      final EventPostsResult result = await _repository(
        pages.adapter,
      ).fetchAllEventPosts(locale: 'de');

      expect(result.from, '2026-08-01');
      expect(result.to, '2026-08-31');
    });
  });

  group('partial failure', () {
    test(
      'a failing later page keeps the pages already loaded and reports them as '
      'truncated instead of losing the whole load',
      () async {
        final _ScriptedEventPages pages = _ScriptedEventPages(
          totalPages: 3,
          failOnPage: 2,
        );
        final EventPostsRepository repository = _repository(pages.adapter);

        final EventPostsResult result = await repository.fetchAllEventPosts(
          locale: 'de',
        );

        // Only page 1 has a cache fallback, so offline page 2 simply cannot be
        // had. Throwing would leave the reader with an empty screen although a
        // cached first page was in hand.
        expect(result.articles, hasLength(1)); // page 1 survived
        expect(result.isTruncated, isTrue);
        // Pages 2 and 3 were asked for together, so page 3 was requested even
        // though page 2 turned out to be the end of what could be used.
        expect(pages.requestedPages, unorderedEquals(<int>[1, 2, 3]));
      },
    );

    test('the first page falls back to cache when the network fails', () async {
      final ContentCache cache = SafeContentCache(MemoryContentCache());
      bool fail = false;
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        if (fail) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        return FakeHttpResponse(
          envelope(
            <Object>[_article('cached')],
            meta: <String, dynamic>{
              'from': '2026-08-01',
              'to': '2026-08-31',
              'pagination': <String, dynamic>{
                'page': 1,
                'pageSize': kEventPostsPageSize,
                'total': 1,
                'totalPages': 1,
              },
            },
          ),
        );
      });
      final EventPostsRepository repository = _repository(
        adapter,
        cache: cache,
      );

      final EventPostsResult live = await repository.fetchAllEventPosts(
        locale: 'de',
      );
      expect(live.fromCache, isFalse);

      fail = true;
      final EventPostsResult cached = await repository.fetchAllEventPosts(
        locale: 'de',
      );
      expect(cached.fromCache, isTrue);
      expect(cached.articles.single.slug, 'cached');
    });

    test('only page 1 is ever written to the cache (VG-N02)', () async {
      // Later pages have no cache fallback, so a stored copy of one is never
      // read again — it only takes a slot in the range budget it shares with
      // timetable and calendar weeks, and pushes those out.
      final _RecordingContentCache cache = _RecordingContentCache();
      final _ScriptedEventPages pages = _ScriptedEventPages(totalPages: 3);

      final EventPostsResult result = await _repository(
        pages.adapter,
        cache: cache,
      ).fetchAllEventPosts(locale: 'de');

      expect(result.articles, hasLength(3));
      expect(cache.writtenKeys, hasLength(1));
      expect(cache.writtenKeys.single, endsWith('.p1'));
    });

    test('rethrows when neither the network nor the cache can serve', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      await expectLater(
        _repository(adapter).fetchAllEventPosts(locale: 'de'),
        throwsA(isA<ApiFailure>()),
      );
    });
  });

  group('concurrency', () {
    test('the later pages are in flight at the same time', () async {
      int inFlight = 0;
      int mostAtOnce = 0;
      final List<int> requested = <int>[];

      final FakeHttpAdapter adapter = FakeHttpAdapter((
        RequestOptions options,
      ) async {
        final int page =
            int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
        requested.add(page);
        inFlight += 1;
        if (inFlight > mostAtOnce) mostAtOnce = inFlight;
        // Yield, so a sequential caller can never overlap here and a
        // concurrent one always does.
        await Future<void>.delayed(Duration.zero);
        inFlight -= 1;
        return FakeHttpResponse(
          envelope(
            <Object>[_article('p$page')],
            meta: <String, dynamic>{
              'from': '2026-08-01',
              'to': '2026-08-31',
              'pagination': <String, dynamic>{
                'page': page,
                'pageSize': kEventPostsPageSize,
                'total': 5,
                'totalPages': 5,
              },
            },
          ),
        );
      });

      final EventPostsResult result = await _repository(
        adapter,
      ).fetchAllEventPosts(locale: 'de');

      expect(result.articles, hasLength(5));
      expect(
        mostAtOnce,
        greaterThan(1),
        reason: 'pages 2..5 must not wait for one another',
      );
      expect(requested.first, 1, reason: 'page 1 resolves the window first');
    });

    test('a later page reporting fewer pages stops the load there', () async {
      // The first page announces four; page 2 comes back saying there are
      // only two. Nothing beyond page 2 may be folded in.
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        final int page =
            int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
        final int totalPages = page == 1 ? 4 : 2;
        return FakeHttpResponse(
          envelope(
            <Object>[_article('p$page')],
            meta: <String, dynamic>{
              'from': '2026-08-01',
              'to': '2026-08-31',
              'pagination': <String, dynamic>{
                'page': page,
                'pageSize': kEventPostsPageSize,
                'total': totalPages,
                'totalPages': totalPages,
              },
            },
          ),
        );
      });

      final EventPostsResult result = await _repository(
        adapter,
      ).fetchAllEventPosts(locale: 'de');

      expect(result.articles.map((NewsArticle a) => a.slug), <String>[
        'p1',
        'p2',
      ]);
      expect(result.isTruncated, isFalse);
    });

    test('a later page reporting more pages is still followed', () async {
      // The first page announces two; page 2 comes back saying there are
      // four. The two extra pages were not planned for and are fetched after.
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        final int page =
            int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
        final int totalPages = page == 1 ? 2 : 4;
        return FakeHttpResponse(
          envelope(
            <Object>[_article('p$page')],
            meta: <String, dynamic>{
              'from': '2026-08-01',
              'to': '2026-08-31',
              'pagination': <String, dynamic>{
                'page': page,
                'pageSize': kEventPostsPageSize,
                'total': totalPages,
                'totalPages': totalPages,
              },
            },
          ),
        );
      });

      final EventPostsResult result = await _repository(
        adapter,
      ).fetchAllEventPosts(locale: 'de');

      expect(result.articles.map((NewsArticle a) => a.slug), <String>[
        'p1',
        'p2',
        'p3',
        'p4',
      ]);
      expect(result.isTruncated, isFalse);
    });
  });
}
