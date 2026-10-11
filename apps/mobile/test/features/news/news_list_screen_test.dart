// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/features/news/application/news_feed_controller.dart';
import 'package:campus_koethen/features/news/presentation/news_filter_sheet.dart';
import 'package:campus_koethen/features/news/presentation/news_list_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/fixtures.dart';
import '../../support/news_harness.dart';
import '../../support/pump_app.dart';
import '../../support/throwing_content_cache.dart';

FakeHttpAdapter workingApi({List<Map<String, dynamic>>? articles}) {
  return FakeHttpAdapter((RequestOptions options) {
    if (options.path.endsWith('/posts/channels')) {
      return FakeHttpResponse(envelope(channelsFixture));
    }
    if (options.path.endsWith('/posts/tags')) {
      return FakeHttpResponse(envelope(tagsFixture));
    }
    return FakeHttpResponse(
      envelope(
        articles ?? articlesFixture,
        meta: <String, dynamic>{
          'pagination': <String, dynamic>{
            'page': 1,
            'pageSize': 20,
            'total': (articles ?? articlesFixture).length,
            'totalPages': 1,
          },
        },
      ),
    );
  });
}

/// An article with a title long enough to give the card a real height.
Map<String, dynamic> _article(String slug) => <String, dynamic>{
  'slug': slug,
  'title': 'Meldung $slug',
  'publishedAt': '2026-08-04T09:00:00.000Z',
  'heroImage': null,
  'channels': <Object>[],
  'tag': <String, dynamic>{'slug': 'news', 'name': 'News'},
  'primaryChannel': <String, dynamic>{
    'slug': 'campus-news',
    'name': 'Campus News',
  },
  'content': <Object>[
    <String, dynamic>{
      'type': 'paragraph',
      'children': <Object>[
        <String, dynamic>{'type': 'text', 'text': 'Der Text von $slug.'},
      ],
    },
  ],
};

/// Serves scripted pages; a `null` page fails the request.
class _PagedApi {
  _PagedApi(this.pages);

  final Map<int, List<String>?> pages;
  final List<int> requested = <int>[];

  FakeHttpAdapter get adapter => FakeHttpAdapter((RequestOptions options) {
    if (options.path.endsWith('/posts/channels')) {
      return FakeHttpResponse(envelope(channelsFixture));
    }
    if (options.path.endsWith('/posts/tags')) {
      return FakeHttpResponse(envelope(tagsFixture));
    }
    final int page =
        int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
    requested.add(page);
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
            'pageSize': slugs.length,
            'total': pages.length * slugs.length,
            'totalPages': pages.length,
          },
        },
      ),
    );
  });
}

Future<ProviderContainer> _pumpFeed(
  WidgetTester tester, {
  required FakeHttpAdapter adapter,
  KeyValueStore? store,
  Size size = const Size(390, 1200),
  Locale locale = AppLocales.german,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final ProviderContainer container = await pumpScreen(
    tester,
    const NewsListScreen(),
    locale: locale,
    keyValueStore: store ?? InMemoryKeyValueStore(<String, Object>{}),
    overrides: <Override>[
      frozenNewsClock(),
      apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
    ],
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('renders the article list under one centred title', (
    WidgetTester tester,
  ) async {
    await _pumpFeed(tester, adapter: workingApi());

    // The title and its byline may carry the same exact channel name.
    expect(find.text('Campus News'), findsNWidgets(2));
    expect(find.text('Semesterstart 2026'), findsOneWidget);
    // Exactly one action at the top, and no search.
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byTooltip('Filter'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('the filter sheet offers "Alle" plus every active tag', (
    WidgetTester tester,
  ) async {
    await _pumpFeed(tester, adapter: workingApi());

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    // Scoped to the sheet itself: every post now carries a mandatory tag
    // pill, so the feed card behind the sheet also renders a "News" chip —
    // an unscoped text finder would double count it.
    final Finder sheet = find.byType(NewsFilterSheet);
    expect(find.text('Themen'), findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Alle')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('News')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Event')),
      findsOneWidget,
    );
    final Finder channelRows = find.byType(SwitchListTile);
    expect(channelRows, findsNWidgets(2));
    expect(
      find.descendant(of: channelRows, matching: find.byType(Icon)),
      findsNothing,
      reason: 'news channels are identified by name, not by an icon',
    );
  });

  testWidgets('selecting a tag re-fetches the feed scoped to that tag', (
    WidgetTester tester,
  ) async {
    final FakeHttpAdapter adapter = workingApi();
    await _pumpFeed(tester, adapter: adapter);

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event'));
    await tester.pumpAndSettle();

    final RequestOptions last = adapter.requests.last;
    expect(last.path, endsWith('/posts'));
    expect(last.queryParameters['tags'], 'event');
  });

  testWidgets('a screen reader can pick a tag in the filter sheet', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final FakeHttpAdapter adapter = workingApi();
    await _pumpFeed(tester, adapter: adapter);

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.bySemanticsLabel('Alle Themen anzeigen')),
      isSemantics(hasTapAction: true),
    );
    tester.semantics.tap(find.semantics.byLabel('Nach Event filtern'));
    await tester.pumpAndSettle();

    expect(adapter.requests.last.queryParameters['tags'], 'event');
    handle.dispose();
  });

  testWidgets('the event view has a visibly labelled entry point', (
    WidgetTester tester,
  ) async {
    await _pumpFeed(tester, adapter: workingApi());

    expect(find.widgetWithText(OutlinedButton, 'Events'), findsOneWidget);
  });

  testWidgets('a throwing cache still yields a working screen', (
    WidgetTester tester,
  ) async {
    final ThrowingContentCache cache = ThrowingContentCache();

    await pumpScreen(
      tester,
      const NewsListScreen(),
      contentCache: cache,
      overrides: <Override>[
        frozenNewsClock(),
        apiClientProvider.overrideWithValue(fakeApiClient(workingApi())),
      ],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(cache.writeAttempts, greaterThan(0), reason: 'the cache was used');
    expect(
      find.text('Semesterstart 2026'),
      findsOneWidget,
      reason: 'a broken cache degrades to a plain network fetch',
    );
  });

  testWidgets('a throwing cache degrades a network error to the error state', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const NewsListScreen(),
      contentCache: ThrowingContentCache(),
      overrides: <Override>[
        frozenNewsClock(),
        apiClientProvider.overrideWithValue(
          fakeApiClient(
            FakeHttpAdapter((RequestOptions _) => throw Exception('offline')),
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text(
        'Keine Verbindung zum Server. Bitte prüfe deine Internetverbindung.',
      ),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets(
    'shows a dedicated empty state when every channel is deselected',
    (WidgetTester tester) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{
          PreferenceKeys.channelStoreVersion:
              PreferenceKeys.channelStoreCurrentVersion,
          PreferenceKeys.channelSeenSlugs: <String>['campus-news', 'fb5-news'],
          PreferenceKeys.channelSelectedSlugs: <String>[],
        },
      );
      final FakeHttpAdapter adapter = workingApi(
        articles: <Map<String, dynamic>>[],
      );

      await _pumpFeed(tester, adapter: adapter, store: store);

      expect(find.text('Keine Kanäle ausgewählt'), findsOneWidget);

      final String newsQuery = adapter.requests
          .firstWhere(
            (RequestOptions options) =>
                !options.path.contains('channels') &&
                !options.path.contains('tags'),
          )
          .uri
          .query;
      expect(
        newsQuery,
        contains('channels='),
        reason: 'the parameter must be present but empty, never omitted',
      );
    },
  );

  testWidgets('shows the empty state when a channel has no articles', (
    WidgetTester tester,
  ) async {
    await _pumpFeed(
      tester,
      adapter: workingApi(articles: <Map<String, dynamic>>[]),
    );

    expect(find.text('Keine Beiträge'), findsOneWidget);
  });

  testWidgets('renders English when the locale is en', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const NewsListScreen(),
      locale: AppLocales.english,
      overrides: <Override>[
        frozenNewsClock(),
        apiClientProvider.overrideWithValue(
          fakeApiClient(workingApi(articles: <Map<String, dynamic>>[])),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('No articles'), findsOneWidget);
    expect(find.text('Keine Beiträge'), findsNothing);
  });

  testWidgets('labels cached content as offline', (WidgetTester tester) async {
    bool offline = false;
    final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
      if (offline) throw Exception('offline');
      if (options.path.endsWith('/posts/channels')) {
        return FakeHttpResponse(envelope(channelsFixture));
      }
      if (options.path.endsWith('/posts/tags')) {
        return FakeHttpResponse(envelope(tagsFixture));
      }
      return FakeHttpResponse(envelope(articlesFixture));
    });

    final ProviderContainer container = await _pumpFeed(
      tester,
      adapter: adapter,
    );
    expect(find.text('Offline gespeicherte Inhalte'), findsNothing);

    offline = true;
    container.invalidate(newsFeedControllerProvider);
    await tester.pumpAndSettle();

    expect(find.text('Offline gespeicherte Inhalte'), findsOneWidget);
    expect(find.text('Semesterstart 2026'), findsOneWidget);
  });

  testWidgets('says once when an article is only available in German', (
    WidgetTester tester,
  ) async {
    // The contract reports the fallback per response, and the reader is told
    // once — not once per card.
    final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.path.endsWith('/posts/channels')) {
        return FakeHttpResponse(envelope(channelsFixture));
      }
      if (options.path.endsWith('/posts/tags')) {
        return FakeHttpResponse(envelope(tagsFixture));
      }
      return FakeHttpResponse(
        envelope(
          articlesFixture,
          meta: <String, dynamic>{'translationFallback': true},
        ),
      );
    });

    await _pumpFeed(tester, adapter: adapter);

    expect(
      find.textContaining('keine englische Fassung'),
      findsOneWidget,
      reason: 'the hint belongs to the response, not to a card',
    );
  });

  testWidgets('describes mixed-language content naturally in English', (
    WidgetTester tester,
  ) async {
    final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.path.endsWith('/posts/channels')) {
        return FakeHttpResponse(envelope(channelsFixture));
      }
      if (options.path.endsWith('/posts/tags')) {
        return FakeHttpResponse(envelope(tagsFixture));
      }
      return FakeHttpResponse(
        envelope(
          articlesFixture,
          meta: <String, dynamic>{'translationFallback': true},
        ),
      );
    });

    await _pumpFeed(tester, adapter: adapter, locale: AppLocales.english);

    expect(
      find.text(
        'Some content is not available in English yet. '
        'The original German text is shown.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('No English version'), findsNothing);
  });

  group('infinite scrolling', () {
    testWidgets('loads the next page when the end comes into view', (
      WidgetTester tester,
    ) async {
      final _PagedApi api = _PagedApi(<int, List<String>?>{
        1: <String>['a01', 'a02', 'a03', 'a04', 'a05', 'a06', 'a07', 'a08'],
        2: <String>['b01', 'b02'],
      });

      await _pumpFeed(tester, adapter: api.adapter, size: const Size(390, 600));
      // Only the first page so far — the end of the list is far below.
      expect(api.requested, <int>[1]);

      // Dragged from the list itself, not from an article card: a card's
      // position shifts as the list scrolls, but the scrollable's own
      // viewport stays put.
      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(api.requested, <int>[1, 2]);

      // The appended page sits below the current position; scrolling on shows
      // it, and the list has not started over.
      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(find.text('Meldung b02'), findsOneWidget);
      expect(api.requested, <int>[1, 2], reason: 'the last page is final');
    });

    testWidgets('a failed next page keeps what is already there', (
      WidgetTester tester,
    ) async {
      // Losing a screenful because the next request timed out is far worse
      // than a retry button at the bottom.
      final _PagedApi api = _PagedApi(<int, List<String>?>{
        1: <String>['a01', 'a02'],
        2: null,
      });

      await _pumpFeed(tester, adapter: api.adapter);

      expect(find.text('Meldung a01'), findsOneWidget);
      expect(
        find.text('Weitere Beiträge konnten nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('the retry appends the page it failed on', (
      WidgetTester tester,
    ) async {
      final _PagedApi api = _PagedApi(<int, List<String>?>{
        1: <String>['a01', 'a02'],
        2: null,
      });

      await _pumpFeed(tester, adapter: api.adapter);
      api.pages[2] = <String>['b01', 'b02'];

      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();

      expect(find.text('Meldung a01'), findsOneWidget);
      expect(find.text('Meldung b01'), findsOneWidget);
      expect(
        find.text('Weitere Beiträge konnten nicht geladen werden.'),
        findsNothing,
      );
    });

    testWidgets('a failed page is not retried by itself', (
      WidgetTester tester,
    ) async {
      // An endpoint that has just said no must not be hammered.
      final _PagedApi api = _PagedApi(<int, List<String>?>{
        1: <String>['a01'],
        2: null,
      });

      await _pumpFeed(tester, adapter: api.adapter);
      final int attempts = api.requested.where((int page) => page == 2).length;

      await tester.pump(const Duration(seconds: 5));

      expect(api.requested.where((int page) => page == 2).length, attempts);
      expect(attempts, 1);
    });
  });
}
