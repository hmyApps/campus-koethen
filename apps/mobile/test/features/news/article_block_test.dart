// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:ui' show Tristate;

import 'package:campus_koethen/core/content/content_block.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:campus_koethen/features/news/presentation/article_block.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/news_harness.dart';
import '../../support/pump_app.dart';

ParagraphBlock _p(String text) =>
    ParagraphBlock(<InlineNode>[InlineText(text: text)]);

const NewsTagRef _defaultTag = NewsTagRef(slug: 'news', name: 'News');
const NewsChannelRef _defaultPrimaryChannel = NewsChannelRef(
  slug: 'campus-news',
  name: 'Campus News',
);

NewsArticle _article({
  String slug = 'a',
  String title = 'Semesterstart 2026',
  List<ContentBlock>? content,
  List<NewsChannelRef> channels = const <NewsChannelRef>[],
  NewsTagRef tag = _defaultTag,
  NewsChannelRef primaryChannel = _defaultPrimaryChannel,
  DateTime? publishedAt,
}) => NewsArticle(
  slug: slug,
  title: title,
  publishedAt: publishedAt ?? newsTestNow.subtract(const Duration(hours: 2)),
  channels: channels,
  tag: tag,
  primaryChannel: primaryChannel,
  content: content ?? <ContentBlock>[_p('Kurzer Text.')],
);

/// Several lines' worth of text, comfortably more than the preview shows.
List<ContentBlock> get _longArticle => <ContentBlock>[
  for (int i = 1; i <= 12; i++) _p('Absatz Nummer $i mit etwas Fließtext.'),
];

Future<void> _pumpCard(
  WidgetTester tester,
  NewsArticle article, {
  Locale locale = AppLocales.german,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await pumpScreen(
    tester,
    Scaffold(
      body: ListView(children: <Widget>[ArticleBlock(article: article)]),
    ),
    locale: locale,
    overrides: <Override>[frozenNewsClock()],
  );
  await tester.pump();
}

/// Pumps [article] behind a minimal router carrying the real nested channel
/// route, so a tap on a channel handle can be asserted against real
/// navigation instead of a mock — the same convention `app_navigation_test`
/// uses for the full app router, scaled down to just the two routes this
/// widget's link can reach.
Future<ProviderContainer> _pumpCardWithRouter(
  WidgetTester tester,
  NewsArticle article,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[frozenNewsClock()],
  );
  addTearDown(container.dispose);

  final GoRouter router = GoRouter(
    initialLocation: '/news',
    routes: <RouteBase>[
      GoRoute(
        path: '/news',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: ListView(children: <Widget>[ArticleBlock(article: article)]),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: ':slug',
            name: 'news-channel',
            builder: (BuildContext context, GoRouterState state) =>
                Scaffold(body: Text('channel:${state.pathParameters['slug']}')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: AppLocales.german,
        supportedLocales: AppLocales.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Every semantics label under the card, optionally only the buttons.
List<String> _semanticsLabels(WidgetTester tester, {bool isButton = false}) {
  final List<String> labels = <String>[];
  void visit(SemanticsNode node) {
    if (!isButton || node.flagsCollection.isButton) {
      if (node.label.isNotEmpty) labels.add(node.label);
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(ArticleBlock)));
  return labels;
}

/// Every semantics node under the card that carries the link flag.
List<SemanticsNode> _linkNodes(WidgetTester tester) {
  final List<SemanticsNode> nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.flagsCollection.isLink) nodes.add(node);
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(ArticleBlock)));
  return nodes;
}

void main() {
  testWidgets('shows the title, the exact channel names and the article', (
    WidgetTester tester,
  ) async {
    await _pumpCard(
      tester,
      _article(
        channels: const <NewsChannelRef>[
          NewsChannelRef(slug: 'fb5-news', name: 'FB5-News'),
          NewsChannelRef(slug: 'fsr-ins', name: 'FSR.INS'),
        ],
        content: <ContentBlock>[_p('Der Artikeltext.')],
      ),
    );

    expect(find.text('Semesterstart 2026'), findsOneWidget);
    // Each channel is its own tappable link, not one combined tap target for
    // the whole byline — so each handle is its own Text, not one joined
    // string.
    expect(find.text('FB5-News'), findsOneWidget);
    expect(find.text('FSR.INS'), findsOneWidget);
    expect(find.text('FB5-News FSR.INS'), findsNothing);
    expect(find.text('Der Artikeltext.'), findsOneWidget);
  });

  testWidgets('an event post can be saved and unsaved from the news feed', (
    WidgetTester tester,
  ) async {
    final MemorySavedEventsStore saved = MemorySavedEventsStore();
    final InMemoryKeyValueStore preferences = InMemoryKeyValueStore();
    await preferences.setInt(PreferenceKeys.notificationsPrePromptDeclined, 1);
    final ProviderContainer container = await pumpScreen(
      tester,
      Scaffold(
        body: ListView(
          children: <Widget>[
            ArticleBlock(
              article: NewsArticle(
                slug: 'campus-event',
                title: 'Campus Event',
                tag: _defaultTag,
                primaryChannel: _defaultPrimaryChannel,
                eventStart: DateTime.utc(2026, 10, 5, 10),
              ),
            ),
          ],
        ),
      ),
      keyValueStore: preferences,
      overrides: <Override>[
        frozenNewsClock(),
        savedEventsStoreProvider.overrideWithValue(saved),
      ],
    );
    await container.read(savedEventsControllerProvider.future);
    await tester.pump();

    await tester.tap(find.byTooltip('Event merken'));
    await tester.pump();
    expect((await saved.readAll()).single.eventRef, 'post:campus-event');

    await tester.tap(find.byTooltip('Event nicht mehr merken'));
    await tester.pump();
    expect(await saved.readAll(), isEmpty);
  });

  group('channel links', () {
    testWidgets('exposes every channel handle as a link, not plain text', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        _article(
          channels: const <NewsChannelRef>[
            NewsChannelRef(slug: 'fb5-news', name: 'FB5-News'),
            NewsChannelRef(slug: 'fsr-ins', name: 'FSR.INS'),
          ],
        ),
      );

      final List<SemanticsNode> linkNodes = _linkNodes(tester);

      expect(
        linkNodes.map((SemanticsNode n) => n.label),
        containsAll(<String>['Kanal FB5-News öffnen', 'Kanal FSR.INS öffnen']),
      );
    });

    testWidgets('uses a focusable 48 dp button for every channel', (
      WidgetTester tester,
    ) async {
      await _pumpCardWithRouter(
        tester,
        _article(
          channels: const <NewsChannelRef>[
            NewsChannelRef(slug: 'fb5-news', name: 'FB5-News'),
          ],
        ),
      );

      final Finder button = find.ancestor(
        of: find.text('FB5-News'),
        matching: find.byType(TextButton),
      );
      expect(button, findsOneWidget);
      expect(
        tester.getSize(button).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );

      for (
        int i = 0;
        i < 8 && !Focus.of(tester.element(find.text('FB5-News'))).hasFocus;
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(Focus.of(tester.element(find.text('FB5-News'))).hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('channel:fb5-news'), findsOneWidget);
    });

    testWidgets(
      'tapping a channel handle navigates, without toggling the card',
      (WidgetTester tester) async {
        await _pumpCardWithRouter(
          tester,
          _article(
            content: _longArticle,
            channels: const <NewsChannelRef>[
              NewsChannelRef(slug: 'fb5-news', name: 'FB5-News'),
            ],
          ),
        );

        // Still collapsed before the tap.
        expect(find.text('Mehr anzeigen'), findsOneWidget);

        await tester.tap(find.text('FB5-News'));
        await tester.pumpAndSettle();

        // Navigation happened — the channel route is now on screen, and the
        // article card (with its expand state) is gone with it. If the tap
        // had fallen through to the card's own toggle instead of the link, the
        // card would still be here, now expanded.
        expect(find.text('channel:fb5-news'), findsOneWidget);
        expect(find.text('Mehr anzeigen'), findsNothing);
        expect(find.byType(ArticleBlock), findsNothing);
      },
    );
  });

  testWidgets('the whole card is one tappable area, even without an explicit '
      'expand button', (WidgetTester tester) async {
    // Every card is a large interaction surface, per the acceptance criteria,
    // even one whose content is short enough that the explicit toggle button
    // stays hidden.
    await _pumpCard(tester, _article(content: <ContentBlock>[_p('Kurz.')]));

    // `Chip` (the mandatory tag pill) always builds its own InkWell
    // internally, tappable or not — Material's `RawChip` does this
    // unconditionally. So the real assertion is "one InkWell that actually
    // responds to a tap", not "one InkWell anywhere in the tree".
    final Iterable<InkWell> inkWells = tester.widgetList<InkWell>(
      find.byType(InkWell),
    );
    expect(inkWells.where((InkWell w) => w.onTap != null), hasLength(1));
  });

  testWidgets('only the real actions announce themselves as buttons', (
    WidgetTester tester,
  ) async {
    await _pumpCard(tester, _article(content: _longArticle));

    expect(_semanticsLabels(tester, isButton: true), <String>['Mehr anzeigen']);
  });

  testWidgets('exposes the card open/closed state to a screen reader', (
    WidgetTester tester,
  ) async {
    await _pumpCard(tester, _article(content: _longArticle));

    SemanticsNode cardNode() => tester.getSemantics(find.byType(ArticleBlock));

    expect(cardNode().flagsCollection.isToggled, Tristate.isFalse);

    await tester.tap(find.text('Mehr anzeigen'));
    await tester.pumpAndSettle();

    expect(cardNode().flagsCollection.isToggled, Tristate.isTrue);
  });

  group('expanding', () {
    testWidgets('a short article offers nothing to expand', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, _article(content: <ContentBlock>[_p('Kurz.')]));

      expect(find.text('Mehr anzeigen'), findsNothing);
    });

    testWidgets('a long article shows five lines and then the whole text', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, _article(content: _longArticle));

      final Text preview = tester.widget<Text>(
        find.textContaining('Absatz Nummer 1'),
      );
      expect(preview.maxLines, 5);
      expect(preview.overflow, TextOverflow.ellipsis);
      // The twelfth paragraph is in the preview STRING but clipped; it becomes
      // a block of its own only once expanded.
      expect(find.text('Absatz Nummer 12 mit etwas Fließtext.'), findsNothing);

      await tester.tap(find.text('Mehr anzeigen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Absatz Nummer 12 mit etwas Fließtext.'),
        findsOneWidget,
      );
      expect(find.text('Weniger anzeigen'), findsOneWidget);
      expect(find.text('Mehr anzeigen'), findsNothing);
    });

    testWidgets('tapping a free spot on the card expands and collapses it', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, _article(content: _longArticle));

      expect(find.text('Mehr anzeigen'), findsOneWidget);

      // The headline is a free spot: not a link, not a button.
      await tester.tap(find.text('Semesterstart 2026'));
      await tester.pumpAndSettle();

      expect(find.text('Weniger anzeigen'), findsOneWidget);
      expect(
        find.text('Absatz Nummer 12 mit etwas Fließtext.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Semesterstart 2026'));
      await tester.pumpAndSettle();

      expect(find.text('Mehr anzeigen'), findsOneWidget);
      expect(find.text('Absatz Nummer 12 mit etwas Fließtext.'), findsNothing);
    });

    testWidgets(
      'tapping the source link opens it instead of toggling the card',
      (WidgetTester tester) async {
        await _pumpCard(
          tester,
          NewsArticle(
            slug: 'a',
            title: 'Mit Quelle',
            tag: _defaultTag,
            primaryChannel: _defaultPrimaryChannel,
            publishedAt: newsTestNow,
            sourceName: 'Beispielquelle',
            sourceUrl: 'https://example.org/artikel',
            content: _longArticle,
          ),
        );

        await tester.tap(find.text('Mehr anzeigen'));
        await tester.pumpAndSettle();
        expect(find.text('Weniger anzeigen'), findsOneWidget);

        await tester.tap(find.text('Quelle öffnen'));
        await tester.pumpAndSettle();

        // The card is still expanded: the tap opened the source link, it did
        // not also collapse the card underneath it.
        expect(find.text('Weniger anzeigen'), findsOneWidget);
      },
    );

    testWidgets('an article that is only an image can still be opened', (
      WidgetTester tester,
    ) async {
      // Nothing to truncate, so the text alone would never offer a way in.
      await _pumpCard(
        tester,
        _article(
          content: const <ContentBlock>[
            ImageBlock(url: 'https://cdn.example.org/plakat.png'),
          ],
        ),
      );

      expect(find.text('Mehr anzeigen'), findsOneWidget);
    });

    testWidgets('the source link is reachable in the expanded article', (
      WidgetTester tester,
    ) async {
      // The editorial rule is to summarise with a link, so the way back to the
      // original has to survive the loss of the detail page.
      await _pumpCard(
        tester,
        NewsArticle(
          slug: 'a',
          title: 'Mit Quelle',
          publishedAt: newsTestNow,
          tag: _defaultTag,
          primaryChannel: _defaultPrimaryChannel,
          sourceName: 'Beispielquelle',
          sourceUrl: 'https://example.org/artikel',
          content: _longArticle,
        ),
      );

      expect(find.text('Quelle öffnen'), findsNothing);

      await tester.tap(find.text('Mehr anzeigen'));
      await tester.pumpAndSettle();

      expect(find.text('Quelle: Beispielquelle'), findsOneWidget);
      expect(find.text('Quelle öffnen'), findsOneWidget);
    });

    testWidgets('an article without content says so', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, _article(content: const <ContentBlock>[]));

      expect(
        find.text('Für diesen Beitrag liegt kein Text vor.'),
        findsOneWidget,
      );
      expect(find.text('Mehr anzeigen'), findsNothing);
    });
  });

  testWidgets('shows the age relative to now', (WidgetTester tester) async {
    await _pumpCard(
      tester,
      _article(publishedAt: newsTestNow.subtract(const Duration(hours: 3))),
    );

    expect(find.text('vor 3 h'), findsOneWidget);
  });

  testWidgets('sets the age on the byline, not on a row of its own', (
    WidgetTester tester,
  ) async {
    // The byline above the headline already exists for the channel handles, so
    // the timestamp shares it: it still costs no row of its own, and "who said
    // this and when" is one line instead of two facts in two places.
    await _pumpCard(
      tester,
      _article(
        title: 'Semesterstart',
        publishedAt: newsTestNow.subtract(const Duration(hours: 3)),
        channels: const <NewsChannelRef>[
          NewsChannelRef(slug: 'stura', name: 'StuRa'),
        ],
      ),
    );

    final Rect title = tester.getRect(find.text('Semesterstart'));
    final Rect handles = tester.getRect(find.text('StuRa'));
    final Rect age = tester.getRect(find.text('vor 3 h'));

    expect(
      age.center.dy,
      closeTo(handles.center.dy, handles.height),
      reason: 'the age shares the byline with the channels',
    );
    expect(
      age.left,
      greaterThan(handles.right - 1),
      reason: 'and sits at the end of it',
    );
    expect(
      age.bottom,
      lessThanOrEqualTo(title.top),
      reason: 'the whole byline stays above the headline',
    );
  });

  testWidgets('does not break a long age onto two lines needlessly', (
    WidgetTester tester,
  ) async {
    // "vor 4 Tagen" is the everyday case, not an edge one. It has to fit on
    // one line next to a short headline on an ordinary phone.
    await _pumpCard(
      tester,
      _article(
        title: 'Testartikel',
        publishedAt: newsTestNow.subtract(const Duration(days: 4)),
      ),
    );

    final RenderParagraph age = tester.renderObject<RenderParagraph>(
      find.text('vor 4 Tagen'),
    );
    expect(
      age.size.height,
      closeTo(age.getMinIntrinsicHeight(double.infinity), 1),
      reason: 'one line, not two',
    );
  });

  testWidgets('invents no timestamp when the article has none', (
    WidgetTester tester,
  ) async {
    await _pumpCard(
      tester,
      NewsArticle(
        slug: 'a',
        title: 'Ohne Datum',
        tag: _defaultTag,
        primaryChannel: _defaultPrimaryChannel,
        content: <ContentBlock>[_p('Text.')],
      ),
    );

    expect(find.textContaining('vor'), findsNothing);
  });

  testWidgets('shows its single mandatory tag as a pill', (
    WidgetTester tester,
  ) async {
    // The merged Posts contract dropped the old multi-tag list: every post
    // carries exactly one tag, so exactly one pill is ever shown.
    await _pumpCard(
      tester,
      _article(
        tag: const NewsTagRef(slug: 'event', name: 'Event'),
      ),
    );

    expect(find.text('Event'), findsOneWidget);
    expect(find.byType(Chip), findsOneWidget);
  });

  testWidgets('renders in English', (WidgetTester tester) async {
    await _pumpCard(
      tester,
      _article(content: _longArticle),
      locale: AppLocales.english,
    );

    expect(find.text('Show more'), findsOneWidget);
  });

  testWidgets('survives a narrow phone with doubled text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpScreen(
      tester,
      Scaffold(
        body: ListView(
          children: <Widget>[
            ArticleBlock(
              article: _article(
                title: 'Eine ziemlich lange Überschrift für den Umbruchtest',
                content: _longArticle,
                channels: const <NewsChannelRef>[
                  NewsChannelRef(slug: 'campus-news', name: 'Campus News'),
                ],
              ),
            ),
          ],
        ),
      ),
      textScaler: const TextScaler.linear(2),
      overrides: <Override>[frozenNewsClock()],
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
