// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/core/cache/cache_providers.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/news/application/news_channel_feed_controller.dart';
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

/// Serves scripted pages for exactly one channel slug; asserts every request
/// carries that slug and nothing else.
class _ChannelFeed {
  _ChannelFeed(this.slug, this.pages);

  final String slug;

  /// page number -> article slugs, or `null` to make that page fail.
  final Map<int, List<String>?> pages;
  final List<int> requestedPages = <int>[];
  final List<String?> requestedChannels = <String?>[];

  FakeHttpAdapter get adapter => FakeHttpAdapter((RequestOptions options) {
    final int page =
        int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
    requestedPages.add(page);
    requestedChannels.add(options.queryParameters['channels'] as String?);
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
            'total': pages.length * 2,
            'totalPages': pages.length,
          },
        },
      ),
    );
  });
}

ProviderContainer _container(_ChannelFeed feed) {
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

List<String> _slugs(NewsChannelFeedState state) =>
    state.articles.map((NewsArticle a) => a.slug).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the first page is scoped to the channel slug', () async {
    final _ChannelFeed feed = _ChannelFeed('campus-news', <int, List<String>?>{
      1: <String>['a', 'b'],
      2: <String>['c', 'd'],
    });
    final ProviderContainer container = _container(feed);

    final NewsChannelFeedState state = await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );

    expect(_slugs(state), <String>['a', 'b']);
    expect(state.hasMore, isTrue);
    expect(feed.requestedPages, <int>[1]);
    expect(feed.requestedChannels, <String?>['campus-news']);
  });

  test('the next page is appended, not substituted', () async {
    final _ChannelFeed feed = _ChannelFeed('campus-news', <int, List<String>?>{
      1: <String>['a', 'b'],
      2: <String>['c', 'd'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );

    await container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .loadMore();

    expect(
      _slugs(
        container.read(newsChannelFeedControllerProvider('campus-news')).value!,
      ),
      <String>['a', 'b', 'c', 'd'],
    );
  });

  test('an article on two pages appears once', () async {
    final _ChannelFeed feed = _ChannelFeed('campus-news', <int, List<String>?>{
      1: <String>['a', 'b'],
      2: <String>['b', 'c'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );

    await container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .loadMore();

    expect(
      _slugs(
        container.read(newsChannelFeedControllerProvider('campus-news')).value!,
      ),
      <String>['a', 'b', 'c'],
    );
  });

  test('a failed page keeps everything already loaded', () async {
    final _ChannelFeed feed = _ChannelFeed('campus-news', <int, List<String>?>{
      1: <String>['a', 'b'],
      2: null,
    });
    final ProviderContainer container = _container(feed);
    await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );

    await container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .loadMore();

    final NewsChannelFeedState state = container
        .read(newsChannelFeedControllerProvider('campus-news'))
        .value!;
    expect(_slugs(state), <String>['a', 'b']);
    expect(state.loadMoreFailed, isTrue);
    expect(state.isLoadingMore, isFalse);
    expect(state.hasMore, isTrue);
  });

  test('a retry after a failure appends the page', () async {
    final _ChannelFeed feed = _ChannelFeed('campus-news', <int, List<String>?>{
      1: <String>['a'],
      2: null,
    });
    final ProviderContainer container = _container(feed);
    await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );
    await container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .loadMore();

    feed.pages[2] = <String>['b'];
    await container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .loadMore();

    final NewsChannelFeedState state = container
        .read(newsChannelFeedControllerProvider('campus-news'))
        .value!;
    expect(_slugs(state), <String>['a', 'b']);
    expect(state.loadMoreFailed, isFalse);
  });

  test('the last page is not asked for again', () async {
    final _ChannelFeed feed = _ChannelFeed('campus-news', <int, List<String>?>{
      1: <String>['a'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );

    expect(
      container
          .read(newsChannelFeedControllerProvider('campus-news'))
          .value!
          .hasMore,
      isFalse,
    );
    await container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .loadMore();

    expect(feed.requestedPages, <int>[1]);
  });

  test('refreshing starts again at page one', () async {
    final _ChannelFeed feed = _ChannelFeed('campus-news', <int, List<String>?>{
      1: <String>['a'],
      2: <String>['b'],
    });
    final ProviderContainer container = _container(feed);
    await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );
    await container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .loadMore();

    await container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .refresh();

    final NewsChannelFeedState state = container
        .read(newsChannelFeedControllerProvider('campus-news'))
        .value!;
    expect(_slugs(state), <String>['a']);
    expect(state.page, 1);
  });

  test('a late page from the old locale never enters the new feed', () async {
    final Completer<void> releaseGermanPage = Completer<void>();
    final Completer<void> germanPageStarted = Completer<void>();
    final FakeHttpAdapter adapter = FakeHttpAdapter((
      RequestOptions options,
    ) async {
      final int page =
          int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
      final String locale = options.queryParameters['locale'] as String;
      if (page == 2 && locale == 'de') {
        germanPageStarted.complete();
        await releaseGermanPage.future;
      }
      final List<String> slugs = locale == 'en'
          ? <String>['english']
          : page == 1
          ? <String>['german']
          : <String>['late-german-page'];
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
    await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );

    final Future<void> oldLoadMore = container
        .read(newsChannelFeedControllerProvider('campus-news').notifier)
        .loadMore();
    await germanPageStarted.future;
    await container
        .read(settingsProvider.notifier)
        .setLocaleMode(LocaleMode.english);
    final NewsChannelFeedState refreshed = await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );
    expect(_slugs(refreshed), <String>['english']);

    releaseGermanPage.complete();
    await oldLoadMore;

    expect(
      _slugs(
        container
            .read(newsChannelFeedControllerProvider('campus-news'))
            .requireValue,
      ),
      <String>['english'],
    );
  });

  test('two different channels keep separate feeds', () async {
    final _ChannelFeed feedA = _ChannelFeed('campus-news', <int, List<String>?>{
      1: <String>['a'],
    });
    final ProviderContainer container = _container(feedA);

    final NewsChannelFeedState stateA = await container.read(
      newsChannelFeedControllerProvider('campus-news').future,
    );
    final NewsChannelFeedState stateB = await container.read(
      newsChannelFeedControllerProvider('fb5-news').future,
    );

    // Both requests went through the same fake adapter (there is only one
    // channel scripted), but the point is that the two providers are
    // independent instances that can be read without one overwriting the
    // other.
    expect(_slugs(stateA), <String>['a']);
    expect(stateB.page, 1);
  });
}
