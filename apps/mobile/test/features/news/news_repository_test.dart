// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/network/api_failure.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:campus_koethen/features/news/data/news_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';

Map<String, dynamic> get _article => <String, dynamic>{
  'slug': 'semesterstart-2026',
  'title': 'Semesterstart 2026',
  'publishedAt': '2026-07-20T09:00:00.000Z',
  'heroImage': null,
  'channels': <Object>[
    <String, dynamic>{'slug': 'campus-news', 'name': 'Campus News'},
  ],
  'tag': <String, dynamic>{'slug': 'news', 'name': 'News'},
  'primaryChannel': <String, dynamic>{
    'slug': 'campus-news',
    'name': 'Campus News',
  },
  'sourceName': null,
  'sourceUrl': null,
};

void main() {
  group('channels query parameter', () {
    test('is omitted when the repository is given null', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(envelope(<Object>[_article])),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchArticles(locale: 'de', channelsParameter: null);

      expect(adapter.queries.single, isNot(contains('channels')));
    });

    test('is present but empty when nothing is selected', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(envelope(<Object>[])),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchArticles(locale: 'de', channelsParameter: '');

      final String query = adapter.queries.single;
      expect(query, contains('channels='));
      expect(
        RegExp(r'channels=([^&]*)').firstMatch(query)!.group(1),
        isEmpty,
        reason: 'an empty value means "deliberately no channels"',
      );
    });

    test('carries the selected slugs as a CSV', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(envelope(<Object>[_article])),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchArticles(
        locale: 'de',
        channelsParameter: 'campus-news,fb5-news',
      );

      expect(
        Uri.decodeQueryComponent(
          RegExp(
            r'channels=([^&]*)',
          ).firstMatch(adapter.queries.single)!.group(1)!,
        ),
        'campus-news,fb5-news',
      );
    });

    test('sends the resolved locale', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(envelope(<Object>[])),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchArticles(locale: 'en', channelsParameter: null);

      expect(adapter.queries.single, contains('locale=en'));
    });
  });

  group('tags query parameter', () {
    test('is omitted when the repository is given null', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(envelope(<Object>[_article])),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchArticles(
        locale: 'de',
        channelsParameter: null,
        tagsParameter: null,
      );

      expect(adapter.queries.single, isNot(contains('tags')));
    });

    test('is present but empty when the caller sends zero tags', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(envelope(<Object>[])),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchArticles(
        locale: 'de',
        channelsParameter: null,
        tagsParameter: '',
      );

      final String query = adapter.queries.single;
      expect(query, contains('tags='));
      expect(RegExp(r'tags=([^&]*)').firstMatch(query)!.group(1), isEmpty);
    });

    test('combines with channels rather than replacing it', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(envelope(<Object>[_article])),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchArticles(
        locale: 'de',
        channelsParameter: 'campus-news',
        tagsParameter: 'event',
      );

      final String query = adapter.queries.single;
      expect(
        Uri.decodeQueryComponent(
          RegExp(r'channels=([^&]*)').firstMatch(query)!.group(1)!,
        ),
        'campus-news',
      );
      expect(
        Uri.decodeQueryComponent(
          RegExp(r'tags=([^&]*)').firstMatch(query)!.group(1)!,
        ),
        'event',
      );
    });
  });

  group('fetchTags', () {
    test('sends the resolved locale', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(envelope(<Object>[])),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchTags(locale: 'en');

      expect(adapter.queries.single, contains('locale=en'));
    });

    test('parses active tags', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (_) => FakeHttpResponse(
          envelope(<Object>[
            <String, dynamic>{
              'slug': 'event',
              'name': 'Event',
              'description': null,
              'sortOrder': 10,
            },
          ]),
        ),
      );
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      final Loaded<List<NewsTag>> loaded = await repository.fetchTags(
        locale: 'de',
      );

      expect(loaded.value.single.slug, 'event');
      expect(loaded.value.single.name, 'Event');
    });
  });

  group('offline cache', () {
    test(
      'serves the last successful response when the network fails',
      () async {
        bool fail = false;
        final FakeHttpAdapter adapter = FakeHttpAdapter((_) {
          if (fail) throw Exception('offline');
          return FakeHttpResponse(envelope(<Object>[_article]));
        });
        final ContentCache cache = SafeContentCache(MemoryContentCache());
        final NewsRepository repository = NewsRepository(
          client: fakeApiClient(adapter),
          cache: cache,
        );

        final Loaded<NewsPage> live = await repository.fetchArticles(
          locale: 'de',
          channelsParameter: 'campus-news',
        );
        expect(live.fromCache, isFalse);
        expect(live.value.articles, hasLength(1));

        fail = true;
        final Loaded<NewsPage> cached = await repository.fetchArticles(
          locale: 'de',
          channelsParameter: 'campus-news',
        );
        expect(cached.fromCache, isTrue);
        expect(cached.cachedAt, isNotNull);
        expect(cached.value.articles.single.title, 'Semesterstart 2026');
      },
    );

    test('rethrows when neither network nor cache can serve', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter((_) {
        throw Exception('offline');
      });
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      expect(
        () => repository.fetchArticles(
          locale: 'de',
          channelsParameter: 'campus-news',
        ),
        throwsA(isA<ApiFailure>()),
      );
    });

    test('page two never replaces the cached first page', () async {
      bool offline = false;
      final FakeHttpAdapter adapter = FakeHttpAdapter((options) {
        if (offline) throw Exception('offline');
        final int page =
            int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
        final Map<String, dynamic> article = Map<String, dynamic>.of(_article)
          ..['slug'] = 'page-$page'
          ..['title'] = 'Page $page';
        return FakeHttpResponse(
          envelope(
            <Object>[article],
            meta: <String, dynamic>{
              'pagination': <String, dynamic>{
                'page': page,
                'pageSize': 20,
                'total': 2,
                'totalPages': 2,
              },
            },
          ),
        );
      });
      final NewsRepository repository = NewsRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      );

      await repository.fetchArticles(
        locale: 'de',
        channelsParameter: 'campus-news',
      );
      await repository.fetchArticles(
        locale: 'de',
        channelsParameter: 'campus-news',
        page: 2,
      );
      offline = true;

      final Loaded<NewsPage> cached = await repository.fetchArticles(
        locale: 'de',
        channelsParameter: 'campus-news',
      );

      expect(cached.fromCache, isTrue);
      expect(cached.value.page, 1);
      expect(cached.value.articles.single.slug, 'page-1');
    });
  });
}
