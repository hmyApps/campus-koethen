// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/time/clock.dart';
import 'package:campus_koethen/features/news/application/news_feed_view_options.dart';
import 'package:campus_koethen/features/news/domain/news_feed_arrangement.dart';
import 'package:campus_koethen/features/news/presentation/news_channel_screen.dart';
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

class _MutableClock implements Clock {
  _MutableClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

String _iso(DateTime local) => local.toUtc().toIso8601String();

Map<String, dynamic> _post(String slug, {DateTime? start, DateTime? end}) =>
    <String, dynamic>{
      'slug': slug,
      'title': 'Titel $slug',
      'publishedAt': '2026-08-04T09:00:00.000Z',
      'heroImage': null,
      'channels': <Object>[],
      'tag': <String, dynamic>{'slug': 'news', 'name': 'News'},
      'primaryChannel': <String, dynamic>{
        'slug': 'campus-news',
        'name': 'Campus News',
      },
      'content': <Object>[],
      if (start != null) 'eventStart': _iso(start),
      if (end != null) 'eventEnd': _iso(end),
      'eventAllDay': false,
    };

/// newsTestNow is 2026-08-05 12:00 local.
final Map<String, dynamic> _plain = _post('plain');
final Map<String, dynamic> _ended = _post(
  'ended',
  start: DateTime(2026, 8, 1, 10),
  end: DateTime(2026, 8, 1, 12),
);
final Map<String, dynamic> _upcoming = _post(
  'upcoming',
  start: DateTime(2026, 8, 6, 10),
  end: DateTime(2026, 8, 6, 12),
);
final Map<String, dynamic> _running = _post(
  'running',
  start: DateTime(2026, 8, 5, 11),
  end: DateTime(2026, 8, 5, 12, 30),
);

/// Serves page number -> articles.
FakeHttpAdapter _api(
  Map<int, List<Map<String, dynamic>>> pages, {
  List<int>? requested,
}) => FakeHttpAdapter((RequestOptions options) {
  if (options.path.endsWith('/posts/channels')) {
    return FakeHttpResponse(envelope(channelsFixture));
  }
  if (options.path.endsWith('/posts/tags')) {
    return FakeHttpResponse(envelope(tagsFixture));
  }
  final int page = int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
  requested?.add(page);
  final List<Map<String, dynamic>> articles = pages[page]!;
  return FakeHttpResponse(
    envelope(
      articles,
      meta: <String, dynamic>{
        'pagination': <String, dynamic>{
          'page': page,
          'pageSize': 20,
          'total': 20 * pages.length,
          'totalPages': pages.length,
        },
      },
    ),
  );
});

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen, {
  required FakeHttpAdapter adapter,
  Clock? clock,
  KeyValueStore? store,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final ProviderContainer container = await pumpScreen(
    tester,
    screen,
    locale: AppLocales.german,
    keyValueStore: store ?? InMemoryKeyValueStore(<String, Object>{}),
    overrides: <Override>[
      frozenNewsClock(),
      newsFeedClockProvider.overrideWithValue(
        clock ?? _MutableClock(newsTestNow),
      ),
      apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
    ],
  );
  await tester.pumpAndSettle();
  return container;
}

List<String> _visibleTitlesInOrder(WidgetTester tester) {
  final List<Text> texts = tester
      .widgetList<Text>(find.textContaining('Titel '))
      .toList();
  return texts.map((Text t) => t.data!).toList();
}

void main() {
  group('main feed', () {
    testWidgets('hides an ended event until "Ältere Events anzeigen"', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const NewsListScreen(),
        adapter: _api(<int, List<Map<String, dynamic>>>{
          1: <Map<String, dynamic>>[_plain, _ended, _upcoming],
        }),
      );

      expect(find.text('Titel plain'), findsOneWidget);
      expect(find.text('Titel upcoming'), findsOneWidget);
      expect(find.text('Titel ended'), findsNothing);
      expect(find.text('Ältere Events anzeigen (1)'), findsOneWidget);

      await tester.tap(find.text('Ältere Events anzeigen (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Titel ended'), findsOneWidget);
      // Marked by a word, not by colour alone — and only the ended one.
      expect(find.text('Beendet'), findsOneWidget);
      expect(find.text('Ältere Events ausblenden'), findsOneWidget);

      await tester.tap(find.text('Ältere Events ausblenden'));
      await tester.pumpAndSettle();
      expect(find.text('Titel ended'), findsNothing);
    });

    testWidgets('no toggle when nothing has ended', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const NewsListScreen(),
        adapter: _api(<int, List<Map<String, dynamic>>>{
          1: <Map<String, dynamic>>[_plain, _upcoming],
        }),
      );
      expect(find.textContaining('Ältere Events'), findsNothing);
    });

    testWidgets('an event disappears once its end passes while open', (
      WidgetTester tester,
    ) async {
      final _MutableClock clock = _MutableClock(newsTestNow);
      await _pump(
        tester,
        const NewsListScreen(),
        clock: clock,
        adapter: _api(<int, List<Map<String, dynamic>>>{
          1: <Map<String, dynamic>>[_plain, _running],
        }),
      );
      expect(find.text('Titel running'), findsOneWidget);

      clock.current = newsTestNow.add(const Duration(minutes: 30));
      await tester.pump(const Duration(minutes: 30));
      await tester.pumpAndSettle();

      expect(find.text('Titel running'), findsNothing);
      expect(find.text('Ältere Events anzeigen (1)'), findsOneWidget);
    });

    testWidgets('a resume re-evaluates which events have ended', (
      WidgetTester tester,
    ) async {
      final _MutableClock clock = _MutableClock(newsTestNow);
      await _pump(
        tester,
        const NewsListScreen(),
        clock: clock,
        adapter: _api(<int, List<Map<String, dynamic>>>{
          1: <Map<String, dynamic>>[_plain, _upcoming],
        }),
      );
      expect(find.text('Titel upcoming'), findsOneWidget);

      clock.current = DateTime(2026, 8, 7);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Titel upcoming'), findsNothing);
    });

    testWidgets('everything ended: empty state offers the toggle and the '
        'next page still loads', (WidgetTester tester) async {
      final List<int> requested = <int>[];
      await _pump(
        tester,
        const NewsListScreen(),
        adapter: _api(<int, List<Map<String, dynamic>>>{
          1: <Map<String, dynamic>>[_ended],
          2: <Map<String, dynamic>>[
            _post(
              'ended-2',
              start: DateTime(2026, 7, 1, 9),
              end: DateTime(2026, 7, 1, 10),
            ),
          ],
        }, requested: requested),
      );

      expect(requested, containsAllInOrder(<int>[1, 2]));
      expect(find.text('Keine aktuellen Beiträge'), findsOneWidget);
      expect(find.text('Ältere Events anzeigen (2)'), findsOneWidget);

      await tester.tap(find.text('Ältere Events anzeigen (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Titel ended'), findsOneWidget);
      expect(find.text('Titel ended-2'), findsOneWidget);
      expect(find.text('Beendet'), findsNWidgets(2));
    });

    testWidgets('"Chronologisch" in the filter sheet orders events by start '
        'and persists the choice', (WidgetTester tester) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{},
      );
      final ProviderContainer container = await _pump(
        tester,
        const NewsListScreen(),
        store: store,
        adapter: _api(<int, List<Map<String, dynamic>>>{
          1: <Map<String, dynamic>>[_plain, _upcoming, _running],
        }),
      );
      expect(_visibleTitlesInOrder(tester), <String>[
        'Titel plain',
        'Titel upcoming',
        'Titel running',
      ]);

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Sortierung'), findsOneWidget);
      final Finder tiles = find.byType(RadioListTile<NewsFeedSort>);
      expect(tiles, findsNWidgets(2));
      for (final Element tile in tiles.evaluate()) {
        expect(tile.size!.height, greaterThanOrEqualTo(48));
      }
      expect(
        tester.getSemantics(find.text('Neueste zuerst')),
        isSemantics(
          isInMutuallyExclusiveGroup: true,
          isChecked: true,
          hasTapAction: true,
          label: 'Neueste zuerst',
        ),
      );

      await tester.tap(find.text('Chronologisch'));
      await tester.pumpAndSettle();
      expect(store.getString(PreferenceKeys.newsFeedSort), 'chronological');
      expect(container.read(newsFeedSortProvider), NewsFeedSort.chronological);

      Navigator.of(tester.element(find.text('Sortierung'))).pop();
      await tester.pumpAndSettle();
      expect(_visibleTitlesInOrder(tester), <String>[
        'Titel running',
        'Titel upcoming',
        'Titel plain',
      ]);
    });
  });

  group('channel feed', () {
    testWidgets('hides ended events with its own toggle', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const NewsChannelScreen(slug: 'campus-news'),
        adapter: _api(<int, List<Map<String, dynamic>>>{
          1: <Map<String, dynamic>>[_plain, _ended],
        }),
      );
      expect(find.text('Titel ended'), findsNothing);
      await tester.tap(find.text('Ältere Events anzeigen (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Titel ended'), findsOneWidget);
      expect(find.text('Beendet'), findsOneWidget);
    });

    testWidgets('everything ended: empty state with the toggle', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const NewsChannelScreen(slug: 'campus-news'),
        adapter: _api(<int, List<Map<String, dynamic>>>{
          1: <Map<String, dynamic>>[_ended],
        }),
      );
      expect(find.text('Keine aktuellen Beiträge'), findsOneWidget);
      expect(find.text('Ältere Events anzeigen (1)'), findsOneWidget);
    });
  });
}
