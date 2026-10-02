// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/core/cache/cache_providers.dart';
import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/news/application/channel_subscriptions.dart';
import 'package:campus_koethen/features/news/application/news_feed_controller.dart';
import 'package:campus_koethen/features/news/application/tag_filter.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';

Map<String, dynamic> _article(String slug) => <String, dynamic>{
  'slug': slug,
  'title': 'Titel $slug',
  'publishedAt': '2026-07-20T09:00:00.000Z',
  'heroImage': null,
  'channels': <Object>[],
  'tag': <String, dynamic>{'slug': 'news', 'name': 'News'},
  'primaryChannel': <String, dynamic>{
    'slug': 'campus-news',
    'name': 'Campus News',
  },
  'sourceName': null,
  'sourceUrl': null,
  'content': <Object>[],
};

Map<String, dynamic> get _channel => <String, dynamic>{
  'slug': 'campus-news',
  'name': 'Campus News',
  'description': null,
  'colorHex': '#5B3FD0',
  'sortOrder': 0,
  'defaultSubscribed': true,
};

Map<String, dynamic> get _tag => <String, dynamic>{
  'slug': 'event',
  'name': 'Event',
  'description': null,
  'sortOrder': 0,
};

/// Answers channels and tags once, then serves scripted article pages.
class _Feed {
  _Feed(this.pages, {List<Map<String, dynamic>>? tags})
    : tags = tags ?? <Map<String, dynamic>>[_tag];

  /// page number -> slugs, or `null` to make that page fail.
  final Map<int, List<String>?> pages;
  final List<Map<String, dynamic>> tags;
  final List<int> requestedPages = <int>[];
  final List<String?> requestedTagsParams = <String?>[];

  FakeHttpAdapter get adapter => FakeHttpAdapter((RequestOptions options) {
    if (options.path.contains('channels')) {
      return FakeHttpResponse(envelope(<Object>[_channel]));
    }
    if (options.path.contains('tags')) {
      return FakeHttpResponse(envelope(tags));
    }
    requestedTagsParams.add(options.queryParameters['tags'] as String?);
    final int page =
        int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
    requestedPages.add(page);
    final List<String>? slugs = pages[page];
    if (slugs == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return FakeHttpResponse(
      envelope(
        slugs.map(_article).toList(),
        meta: <String, dynamic>{
          'pagination': <String, dynamic>{
            'page': page,
            'pageSize': 2,
            'total': 4,
            'totalPages': pages.length,
          },
        },
      ),
    );
  });
}

ProviderContainer _container(_Feed feed) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      contentCacheProvider.overrideWithValue(
        SafeContentCache(MemoryContentCache()),
      ),
      apiClientProvider.overrideWithValue(fakeApiClient(feed.adapter)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

List<String> _slugs(NewsFeedState state) =>
    state.articles.map((NewsArticle a) => a.slug).toList();

void main() {
  // localeCodeProvider reads the platform locale through the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the first page is what the feed starts with', () async {
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a', 'b'],
      2: <String>['c', 'd'],
    });
    final ProviderContainer container = _container(feed);

    final NewsFeedState state = await container.read(
      newsFeedControllerProvider.future,
    );

    expect(_slugs(state), <String>['a', 'b']);
    expect(state.hasMore, isTrue);
    expect(feed.requestedPages, <int>[1]);
  });

  test('the next page is appended, not substituted', () async {
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a', 'b'],
      2: <String>['c', 'd'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(newsFeedControllerProvider.future);

    await container.read(newsFeedControllerProvider.notifier).loadMore();

    expect(_slugs(container.read(newsFeedControllerProvider).value!), <String>[
      'a',
      'b',
      'c',
      'd',
    ]);
  });

  test('an article on two pages appears once', () async {
    // The server sorts pinned articles first; one pinned between two requests
    // legitimately turns up twice.
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a', 'b'],
      2: <String>['b', 'c'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(newsFeedControllerProvider.future);

    await container.read(newsFeedControllerProvider.notifier).loadMore();

    expect(_slugs(container.read(newsFeedControllerProvider).value!), <String>[
      'a',
      'b',
      'c',
    ]);
  });

  test('a failed page keeps everything already loaded', () async {
    // Losing a screenful because the next request timed out is far worse than
    // a retry button at the bottom.
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a', 'b'],
      2: null,
    });
    final ProviderContainer container = _container(feed);
    await container.read(newsFeedControllerProvider.future);

    await container.read(newsFeedControllerProvider.notifier).loadMore();

    final NewsFeedState state = container
        .read(newsFeedControllerProvider)
        .value!;
    expect(_slugs(state), <String>['a', 'b']);
    expect(state.loadMoreFailed, isTrue);
    expect(state.isLoadingMore, isFalse);
    // Still offering more, so the footer can retry.
    expect(state.hasMore, isTrue);
  });

  test('a retry after a failure appends the page', () async {
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a'],
      2: null,
    });
    final ProviderContainer container = _container(feed);
    await container.read(newsFeedControllerProvider.future);
    await container.read(newsFeedControllerProvider.notifier).loadMore();

    feed.pages[2] = <String>['b'];
    await container.read(newsFeedControllerProvider.notifier).loadMore();

    final NewsFeedState state = container
        .read(newsFeedControllerProvider)
        .value!;
    expect(_slugs(state), <String>['a', 'b']);
    expect(state.loadMoreFailed, isFalse);
  });

  test('the last page is not asked for again', () async {
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(newsFeedControllerProvider.future);

    expect(container.read(newsFeedControllerProvider).value!.hasMore, isFalse);
    await container.read(newsFeedControllerProvider.notifier).loadMore();

    expect(feed.requestedPages, <int>[1]);
  });

  test('refreshing starts again at page one', () async {
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a'],
      2: <String>['b'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(newsFeedControllerProvider.future);
    await container.read(newsFeedControllerProvider.notifier).loadMore();

    await container.read(newsFeedControllerProvider.notifier).refresh();

    final NewsFeedState state = container
        .read(newsFeedControllerProvider)
        .value!;
    expect(_slugs(state), <String>['a']);
    expect(state.page, 1);
  });

  test('changing the channel selection starts over at page one', () async {
    // Page three of the old selection says nothing about the new one.
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a'],
      2: <String>['b'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(newsFeedControllerProvider.future);
    await container.read(newsFeedControllerProvider.notifier).loadMore();
    expect(feed.requestedPages, <int>[1, 2]);

    await container
        .read(channelSubscriptionProvider.notifier)
        .setSubscribed('campus-news', subscribed: false);
    final NewsFeedState state = await container.read(
      newsFeedControllerProvider.future,
    );

    expect(state.page, 1);
    expect(feed.requestedPages, <int>[1, 2, 1]);
  });

  test('no tag filter omits the tags parameter', () async {
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a'],
    });
    final ProviderContainer container = _container(feed);

    await container.read(newsFeedControllerProvider.future);

    expect(feed.requestedTagsParams.single, isNull);
  });

  test('selecting a tag scopes the feed and restarts at page one', () async {
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a'],
      2: <String>['b'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(newsFeedControllerProvider.future);
    await container.read(newsFeedControllerProvider.notifier).loadMore();
    expect(feed.requestedPages, <int>[1, 2]);

    await container.read(newsTagFilterProvider.notifier).select('event');
    final NewsFeedState state = await container.read(
      newsFeedControllerProvider.future,
    );

    expect(state.page, 1);
    expect(feed.requestedTagsParams.last, 'event');
  });

  test('a late page from the old tag never enters the new feed', () async {
    final Completer<void> releaseOldPage = Completer<void>();
    final Completer<void> oldPageStarted = Completer<void>();
    final FakeHttpAdapter adapter = FakeHttpAdapter((
      RequestOptions options,
    ) async {
      if (options.path.contains('channels')) {
        return FakeHttpResponse(envelope(<Object>[_channel]));
      }
      if (options.path.contains('tags')) {
        return FakeHttpResponse(envelope(<Object>[_tag]));
      }
      final int page =
          int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
      final String? tag = options.queryParameters['tags'] as String?;
      if (page == 2 && tag == null) {
        oldPageStarted.complete();
        await releaseOldPage.future;
      }
      final List<String> slugs = tag == 'event'
          ? <String>['new-filter']
          : page == 1
          ? <String>['old-filter']
          : <String>['late-old-page'];
      return FakeHttpResponse(
        envelope(
          slugs.map(_article).toList(),
          meta: <String, dynamic>{
            'pagination': <String, dynamic>{
              'page': page,
              'pageSize': 2,
              'total': 2,
              'totalPages': 2,
            },
          },
        ),
      );
    });
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        contentCacheProvider.overrideWithValue(
          SafeContentCache(MemoryContentCache()),
        ),
        apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(newsFeedControllerProvider.future);

    final Future<void> oldLoadMore = container
        .read(newsFeedControllerProvider.notifier)
        .loadMore();
    await oldPageStarted.future;
    await container.read(newsTagFilterProvider.notifier).select('event');
    final NewsFeedState refreshed = await container.read(
      newsFeedControllerProvider.future,
    );
    expect(_slugs(refreshed), <String>['new-filter']);

    releaseOldPage.complete();
    await oldLoadMore;

    expect(
      _slugs(container.read(newsFeedControllerProvider).requireValue),
      <String>['new-filter'],
    );
  });

  test(
    'a tag no longer offered by the API resets the feed to "Alle"',
    () async {
      final _Feed feed = _Feed(<int, List<String>?>{
        1: <String>['a'],
      }, tags: <Map<String, dynamic>>[]);
      final ProviderContainer container = _container(feed);
      // Persist a selection the upcoming fetch will not confirm.
      await container.read(newsTagFilterProvider.notifier).select('event');

      await container.read(newsFeedControllerProvider.future);

      expect(container.read(newsTagFilterProvider), isNull);
      expect(feed.requestedTagsParams.single, isNull);
    },
  );

  test('the channel and tag catalogues are requested together', () async {
    // Two independent endpoints. Awaiting the first before asking for the
    // second put a full extra round trip in front of the first article.
    int inFlight = 0;
    int peakInFlight = 0;
    final FakeHttpAdapter adapter = FakeHttpAdapter((
      RequestOptions options,
    ) async {
      inFlight++;
      if (inFlight > peakInFlight) peakInFlight = inFlight;
      try {
        await Future<void>.delayed(Duration.zero);
        if (options.path.contains('channels')) {
          return FakeHttpResponse(envelope(<Object>[_channel]));
        }
        if (options.path.contains('tags')) {
          return FakeHttpResponse(envelope(<Object>[_tag]));
        }
        return FakeHttpResponse(envelope(<Object>[_article('a')]));
      } finally {
        inFlight--;
      }
    });
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        contentCacheProvider.overrideWithValue(
          SafeContentCache(MemoryContentCache()),
        ),
        apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(newsFeedControllerProvider.future);

    expect(
      peakInFlight,
      greaterThanOrEqualTo(2),
      reason: 'run one after the other, the peak would be 1',
    );
  });

  test('each article carries the content the list endpoint delivers', () async {
    // Which is what lets the feed render inline without a request per card.
    final _Feed feed = _Feed(<int, List<String>?>{
      1: <String>['a'],
    });
    final ProviderContainer container = _container(feed);

    final NewsFeedState state = await container.read(
      newsFeedControllerProvider.future,
    );
    expect(state.articles.single.content, isEmpty);
    expect(feed.requestedPages, <int>[1]);
  });
}
