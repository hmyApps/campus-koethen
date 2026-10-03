// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/takt_navigation_bar.dart';
import 'package:campus_koethen/core/theme/app_colors.dart';
import 'package:campus_koethen/core/theme/app_dimensions.dart';
import 'package:campus_koethen/core/theme/app_metrics.dart';
import 'package:campus_koethen/core/widgets/brand_mark.dart';
import 'package:campus_koethen/core/widgets/marker.dart';
import 'package:campus_koethen/core/widgets/screen_scaffold.dart';
import 'package:campus_koethen/core/widgets/section_header.dart';
import 'package:campus_koethen/core/widgets/time_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/pump_app.dart';

/// The colours a light-theme test compares against.
AppColors _light(WidgetTester tester, Type type) =>
    Theme.of(tester.element(find.byType(type))).extension<AppColors>()!;

/// Every solid colour painted under [of], however it was painted.
///
/// Three widgets can fill a box and the app uses all three, so a test that
/// only knew about one of them would pass or fail on an implementation detail
/// rather than on what ends up on screen.
Iterable<Color> _fills(WidgetTester tester, Finder of) sync* {
  Iterable<T> under<T extends Widget>() =>
      tester.widgetList<T>(find.descendant(of: of, matching: find.byType(T)));

  for (final Container container in under<Container>()) {
    if (container.color != null) yield container.color!;
    final Decoration? decoration = container.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      yield decoration.color!;
    }
  }
  for (final DecoratedBox box in under<DecoratedBox>()) {
    final Decoration decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      yield decoration.color!;
    }
  }
  for (final ColoredBox box in under<ColoredBox>()) {
    yield box.color;
  }
}

void main() {
  group('Eyebrow', () {
    testWidgets('is set in capitals but never renamed for a screen reader', (
      WidgetTester tester,
    ) async {
      // The whole point of the widget: capitals are a typographic decision and
      // must not reach the accessibility tree, where "M-E-N-S-A" is what some
      // screen readers make of them.
      await pumpScreen(tester, const Scaffold(body: Eyebrow('Mensa')));

      expect(find.text('MENSA'), findsOneWidget);
      expect(find.text('Mensa'), findsNothing);
      expect(find.bySemanticsLabel('Mensa'), findsOneWidget);
    });
  });

  group('BarLine', () {
    testWidgets('is two device pixels of real ink', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const Scaffold(body: Center(child: BarLine())));

      final Size size = tester.getSize(find.byType(BarLine));
      expect(size.height, AppSizes.rule);
      expect(
        _fills(tester, find.byType(BarLine)),
        contains(_light(tester, BarLine).rule),
        reason: 'a bar line is ink, not a tinted background',
      );
    });
  });

  group('the marker', () {
    testWidgets('MarkerText uses the berry container pairing', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(body: Center(child: MarkerText('heute'))),
      );

      final AppColors colors = _light(tester, MarkerText);
      final Text text = tester.widget<Text>(find.text('heute'));
      expect(text.style!.color, colors.onPrimaryContainer);
      expect(
        _fills(tester, find.byType(MarkerText)),
        contains(colors.primaryContainer),
        reason: 'the berry tint is the fill under the word',
      );
    });

    testWidgets('MarkerBadge says in words what the number means', (
      WidgetTester tester,
    ) async {
      // "3" on its own is not information.
      await pumpScreen(
        tester,
        const Scaffold(
          body: Center(
            child: MarkerBadge(label: '3', semanticLabel: '3 ungelesen'),
          ),
        ),
      );

      expect(find.bySemanticsLabel('3 ungelesen'), findsOneWidget);
      expect(
        _fills(tester, find.byType(MarkerBadge)),
        contains(_light(tester, MarkerBadge).accent),
      );
    });

    testWidgets('a quiet badge drops the marker but keeps the shape', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: Center(
            child: MarkerBadge(
              label: '12',
              semanticLabel: '12 Nachrichten',
              quiet: true,
            ),
          ),
        ),
      );

      final AppColors colors = _light(tester, MarkerBadge);
      expect(
        _fills(tester, find.byType(MarkerBadge)),
        isNot(contains(colors.accent)),
        reason: 'a count that is merely present is not live',
      );
    });
  });

  group('ScreenHeader', () {
    testWidgets('names where you are, what this is, and closes with the rule', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: ScreenHeader(eyebrow: 'Campus', title: 'Mensa'),
        ),
      );

      expect(find.bySemanticsLabel('Campus'), findsOneWidget);
      expect(find.text('Mensa'), findsOneWidget);
      // The 2 dp ink rule under the title.
      expect(
        _fills(tester, find.byType(ScreenHeader)),
        contains(_light(tester, ScreenHeader).rule),
      );
    });

    testWidgets('offers no way back when there is nowhere to go', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(body: ScreenHeader(title: 'Mensa')),
      );

      expect(find.byIcon(AppIcons.arrow_back), findsNothing);
      expect(
        tester.getSize(find.byType(ScreenHeader)).height,
        lessThan(140),
        reason: 'no control row means no empty strip above the title',
      );
    });

    testWidgets('offers one as soon as there is', (WidgetTester tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: ScreenHeader(title: 'Mensa', showBack: true)),
      );

      expect(find.byIcon(AppIcons.arrow_back), findsOneWidget);
      final Size back = tester.getSize(
        find.ancestor(
          of: find.byIcon(AppIcons.arrow_back),
          matching: find.byType(IconButton),
        ),
      );
      expect(back.width, greaterThanOrEqualTo(AppSizes.minTouchTarget));
      expect(back.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
    });

    testWidgets('can visibly disable back navigation during an operation', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: ScreenHeader(
            title: 'Mensa',
            showBack: true,
            backEnabled: false,
          ),
        ),
      );

      final IconButton back = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(AppIcons.arrow_back),
          matching: find.byType(IconButton),
        ),
      );
      expect(back.onPressed, isNull);
    });

    testWidgets('sets the actions on the title line, not on a strip above it', (
      WidgetTester tester,
    ) async {
      // The masthead was built to stop empty 48 dp strips. A row that holds
      // nothing but two icons in the right-hand corner is exactly such a
      // strip, so the icons ride on the line the title is already set on.
      await pumpScreen(
        tester,
        Scaffold(
          body: ScreenHeader(
            title: 'Mensa',
            actions: <Widget>[
              IconButton(
                onPressed: () {},
                icon: const Icon(AppIcons.filter_list),
              ),
            ],
          ),
        ),
      );

      final Rect title = tester.getRect(find.text('Mensa'));
      final Rect action = tester.getRect(find.byIcon(AppIcons.filter_list));
      expect(
        action.center.dy,
        inInclusiveRange(title.top, title.bottom),
        reason: 'the icon shares the line the title is set on',
      );

      final double withActions = tester
          .getSize(find.byType(ScreenHeader))
          .height;

      await pumpScreen(
        tester,
        const Scaffold(body: ScreenHeader(title: 'Mensa')),
      );
      final double without = tester.getSize(find.byType(ScreenHeader)).height;

      expect(
        withActions,
        lessThan(without + AppSizes.minTouchTarget),
        reason: 'actions must not buy themselves a row of their own',
      );
    });

    testWidgets('gives the title the full width once the reader scales up', (
      WidgetTester tester,
    ) async {
      // Sharing the line is a saving, not a rule. At a doubled text size the
      // title needs every millimetre it can get, so the icons step aside
      // rather than squeeze the one string that says where the reader is.
      await pumpScreen(
        tester,
        Scaffold(
          body: ScreenHeader(
            title: 'Mensa',
            actions: <Widget>[
              IconButton(
                onPressed: () {},
                icon: const Icon(AppIcons.filter_list),
              ),
            ],
          ),
        ),
        textScaler: const TextScaler.linear(2),
      );

      final Rect title = tester.getRect(find.text('Mensa'));
      final Rect action = tester.getRect(find.byIcon(AppIcons.filter_list));
      expect(action.bottom, lessThanOrEqualTo(title.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sets the way back, the title and the actions on one line', (
      WidgetTester tester,
    ) async {
      // The masthead spends no row on controls at all: back glyph, title and
      // actions share the one line, and the rule still runs the full width of
      // the content column underneath them.
      Future<double> height({required bool back}) async {
        await pumpScreen(
          tester,
          Scaffold(
            body: ScreenHeader(
              eyebrow: 'Campus',
              title: 'Mensa',
              showBack: back,
              actions: <Widget>[
                IconButton(
                  onPressed: () {},
                  icon: const Icon(AppIcons.filter_list),
                ),
              ],
            ),
          ),
        );
        return tester.getSize(find.byType(ScreenHeader)).height;
      }

      final double pushed = await height(back: true);

      final Rect backRect = tester.getRect(find.byIcon(AppIcons.arrow_back));
      final Rect title = tester.getRect(find.text('Mensa'));
      final Rect action = tester.getRect(find.byIcon(AppIcons.filter_list));

      expect(
        backRect.center.dy,
        inInclusiveRange(title.top - AppSpacing.lg, title.bottom),
        reason: 'the back glyph rides on the line the title is set on',
      );
      expect(action.center.dy, inInclusiveRange(title.top, title.bottom));
      expect(
        title.left,
        greaterThan(backRect.right),
        reason: 'the title follows the glyph rather than sitting under it',
      );

      final double flat = await height(back: false);
      expect(
        pushed,
        flat,
        reason: 'a way back costs the masthead no height of its own',
      );
    });

    testWidgets('steps the display size down as the reader scales text up', (
      WidgetTester tester,
    ) async {
      // Not a cap on the reader's setting — a cap on the design. Twice the
      // text at the display size would be a third of the viewport spent on a
      // word the reader already knows.
      double titleSize(WidgetTester tester) =>
          tester.widget<Text>(find.text('Mensa')).style!.fontSize!;

      await pumpScreen(
        tester,
        const Scaffold(body: ScreenHeader(title: 'Mensa')),
      );
      final double normal = titleSize(tester);

      await pumpScreen(
        tester,
        const Scaffold(body: ScreenHeader(title: 'Mensa')),
        textScaler: const TextScaler.linear(2),
      );
      final double scaled = titleSize(tester);

      expect(scaled, lessThan(normal));
      expect(
        scaled * 2,
        greaterThan(normal),
        reason: 'the title still ends up larger than it was, just not doubled',
      );
    });
  });

  group('ScreenScaffold', () {
    testWidgets(
      'does not overflow with a large Android keyboard, 200% text scale '
      'and a small viewport',
      (WidgetTester tester) async {
        // The smallest supported Android viewport, a keyboard tall enough to
        // cover most of it, and doubled text — the exact combination the
        // reader hits when a big system keyboard and a large font setting
        // meet a screen that also has back/actions on the masthead.
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 400);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);

        await pumpScreen(
          tester,
          ScreenScaffold(
            title: 'Mensa',
            eyebrow: 'Campus',
            showBack: true,
            actions: <Widget>[
              IconButton(
                onPressed: () {},
                icon: const Icon(AppIcons.filter_list),
              ),
            ],
            body: ListView(
              children: <Widget>[
                const TextField(),
                FilledButton(onPressed: () {}, child: const Text('Absenden')),
              ],
            ),
          ),
          textScaler: const TextScaler.linear(2),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byIcon(AppIcons.arrow_back),
          findsOneWidget,
          reason: 'the way back must stay reachable, not squeezed off screen',
        );
        expect(
          tester.getSize(find.byType(ScreenHeader)).height,
          greaterThan(100),
          reason:
              'the masthead keeps its own height instead of being '
              'squeezed by the keyboard',
        );
      },
    );
  });

  group('the time rail', () {
    Widget rail({TimeRailEmphasis emphasis = TimeRailEmphasis.normal}) =>
        Scaffold(
          body: ListView(
            children: <Widget>[
              TimeRailTile(
                start: '08:00',
                end: '09:30',
                emphasis: emphasis,
                child: const Text('Mathematik II'),
              ),
            ],
          ),
        );

    testWidgets('lines the times up in one shared column', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, rail());

      final AppMetrics metrics = AppMetrics.standard;
      final double left = tester.getTopLeft(find.text('08:00')).dx;
      final double content = tester.getTopLeft(find.text('Mathematik II')).dx;
      expect(
        content - left,
        greaterThanOrEqualTo(metrics.timeColumn),
        reason: 'the entry starts past the time column, whatever it says',
      );
      expect(tester.getTopLeft(find.text('09:30')).dx, left);
    });

    testWidgets('keeps a row tall enough to hit', (WidgetTester tester) async {
      await pumpScreen(tester, rail());
      expect(
        tester.getSize(find.byType(TimeRailTile)).height,
        greaterThanOrEqualTo(AppSizes.minTouchTarget),
      );
    });

    testWidgets('turns the rail to marker for what is happening now', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, rail(emphasis: TimeRailEmphasis.now));

      final AppColors colors = _light(tester, TimeRailTile);
      final Iterable<BoxBorder> borders = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(TimeRailTile),
              matching: find.byType(Container),
            ),
          )
          .map((Container c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((BoxDecoration d) => d.border)
          .whereType<BoxBorder>();

      expect(
        borders.map((BoxBorder b) => (b as Border).left.color),
        contains(colors.accent),
      );
      expect(
        borders.map((BoxBorder b) => (b as Border).left.width),
        contains(AppSizes.beam),
        reason: 'now is the heaviest stroke, not only the loudest colour',
      );
    });

    testWidgets('NowRule announces itself as a live region', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: NowRule(time: '10:42', semanticLabel: 'Gerade jetzt, 10:42'),
        ),
      );

      expect(find.bySemanticsLabel('Gerade jetzt, 10:42'), findsOneWidget);
      expect(
        _fills(tester, find.byType(NowRule)),
        contains(_light(tester, NowRule).accent),
      );
    });
  });

  group('BrandMark', () {
    testWidgets('renders the binding icon asset at the requested size', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(body: Center(child: BrandMark(size: 40))),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(BrandMark)), const Size(40, 40));
      final Image image = tester.widget<Image>(
        find.descendant(
          of: find.byType(BrandMark),
          matching: find.byType(Image),
        ),
      );
      final ResizeImage provider = image.image as ResizeImage;
      expect(provider.imageProvider, const AssetImage(BrandAssets.icon));
    });

    testWidgets('renders the binding logo with one accessible app name', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(body: Center(child: BrandWordmark())),
      );

      expect(find.bySemanticsLabel('Campus Köthen'), findsOneWidget);
      final Image image = tester.widget<Image>(
        find.descendant(
          of: find.byType(BrandWordmark),
          matching: find.byType(Image),
        ),
      );
      final ResizeImage provider = image.image as ResizeImage;
      expect(provider.imageProvider, const AssetImage(BrandAssets.logo));
      expect(find.text('CAMPUS'), findsNothing);
      expect(find.text('Köthen'), findsNothing);
    });
  });

  group('TaktNavigationBar', () {
    const List<TaktDestination> destinations = <TaktDestination>[
      TaktDestination(
        icon: AppIcons.article_outlined,
        selectedIcon: AppIcons.article,
        label: 'News',
        tooltip: 'News',
      ),
      TaktDestination(
        icon: AppIcons.restaurant_outlined,
        selectedIcon: AppIcons.restaurant,
        label: 'Mensa',
        tooltip: 'Mensa',
      ),
    ];

    Widget bar() => Scaffold(
      bottomNavigationBar: TaktNavigationBar(
        semanticLabel: 'Hauptnavigation',
        destinations: destinations,
        selectedIndex: 1,
        onSelected: (int _) {},
      ),
    );

    testWidgets('marks the current tab with berry and the selected glyph', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, bar());

      final Icon selected = tester.widget<Icon>(
        find.byIcon(AppIcons.restaurant).first,
      );
      expect(selected.color, _light(tester, TaktNavigationBar).primary);
    });

    testWidgets('drops the label rather than overflowing at huge text', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, bar(), textScaler: const TextScaler.linear(6));

      expect(tester.takeException(), isNull);
      expect(find.text('Mensa'), findsNothing);
      // Nothing is lost: the accessible name was never the short label.
      expect(find.bySemanticsLabel(RegExp('^Mensa,')), findsOneWidget);
    });

    testWidgets('does not draw a marker above the selected icon', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, bar());

      expect(find.byType(MarkerBeam), findsNothing);
    });

    testWidgets('does not show pressed feedback when a tab is tapped', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, bar());

      for (final InkWell tab in tester.widgetList<InkWell>(
        find.byType(InkWell),
      )) {
        expect(tab.splashFactory, NoSplash.splashFactory);
        expect(tab.highlightColor, Colors.transparent);
      }
    });

    testWidgets('names each tab with its position in the bar', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, bar());

      // "Tab 2 of 2" in the platform's own words — the exact wording belongs
      // to MaterialLocalizations, so only the shape is asserted here.
      expect(find.bySemanticsLabel(RegExp('^News, .*1.*2')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Mensa, .*2.*2')), findsOneWidget);
    });

    testWidgets('keeps every tab a 48dp target', (WidgetTester tester) async {
      await pumpScreen(tester, bar());

      final Size size = tester.getSize(find.byType(TaktNavigationBar));
      expect(size.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
      expect(
        size.width / destinations.length,
        greaterThanOrEqualTo(AppSizes.minTouchTarget),
      );
    });
  });
}
