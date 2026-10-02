// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/widgets/status_banner.dart';
import 'package:campus_koethen/core/theme/app_dimensions.dart';
import 'package:campus_koethen/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/pump_app.dart';

const StatusBanner _banner = StatusBanner(
  title: 'Lageplan',
  message: 'Der mitgelieferte Plan passt nicht zur aktuellen Raumliste.',
  tone: StatusTone.warning,
  icon: AppIcons.map_outlined,
);

Future<double> heightIn(WidgetTester tester, Widget parent) async {
  await pumpScreen(tester, parent);
  await tester.pumpAndSettle();
  return tester.renderObject<RenderBox>(find.byType(StatusBanner)).size.height;
}

void main() {
  testWidgets('high contrast strengthens its outline and non-colour marker', (
    WidgetTester tester,
  ) async {
    Future<(double, double)> dimensions(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Center(child: _banner)),
        ),
      );
      await tester.pumpAndSettle();
      final PositionedDirectional beam = tester.widget<PositionedDirectional>(
        find.descendant(
          of: find.byType(StatusBanner),
          matching: find.byType(PositionedDirectional),
        ),
      );
      final DecoratedBox box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(StatusBanner),
          matching: find.byType(DecoratedBox),
        ),
      );
      final BoxDecoration decoration = box.decoration as BoxDecoration;
      return (beam.width!, decoration.border!.top.width);
    }

    final (double standardBeam, double standardOutline) = await dimensions(
      AppTheme.light(),
    );
    final (double strongBeam, double strongOutline) = await dimensions(
      AppTheme.highContrastLight(),
    );

    expect(standardBeam, AppSizes.beam);
    expect(strongBeam, greaterThan(standardBeam));
    expect(strongOutline, greaterThan(standardOutline));
  });

  testWidgets('hugs its content when the height is bounded', (
    WidgetTester tester,
  ) async {
    // The banner was written for a scrolling list, where the height is
    // unbounded and a `MainAxisSize.max` column happens to hug its children.
    // Put the same widget in a box that HAS a height — a centred empty state,
    // for instance — and it stretched to fill all of it, turning a three-line
    // hint into a full-screen slab that hid everything behind it.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final double height = await heightIn(
      tester,
      const Scaffold(
        body: SizedBox(height: 700, child: Center(child: _banner)),
      ),
    );

    expect(
      height,
      lessThan(300),
      reason: 'the banner filled the box instead of sizing to its text',
    );
  });

  testWidgets('is the same height bounded as unbounded', (
    WidgetTester tester,
  ) async {
    // The real invariant: how tall the banner is must follow from its content,
    // not from what happens to be around it.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final double inList = await heightIn(
      tester,
      Scaffold(body: ListView(children: const <Widget>[_banner])),
    );
    final double inBox = await heightIn(
      tester,
      const Scaffold(
        body: SizedBox(height: 700, child: Center(child: _banner)),
      ),
    );

    expect(inBox, inList);
  });

  testWidgets('a title-only banner is shorter than one with a message', (
    WidgetTester tester,
  ) async {
    final double withMessage = await heightIn(
      tester,
      Scaffold(body: ListView(children: const <Widget>[_banner])),
    );
    final double titleOnly = await heightIn(
      tester,
      Scaffold(
        body: ListView(
          children: const <Widget>[StatusBanner(title: 'Lageplan')],
        ),
      ),
    );

    expect(titleOnly, lessThan(withMessage));
  });

  testWidgets('exposes its action to a screen reader as its own control', (
    WidgetTester tester,
  ) async {
    // The banner used to merge everything under it into one label with
    // `excludeSemantics: true`, the action included. That made "try again",
    // "search on the server" and every permission prompt invisible and
    // unreachable to TalkBack and VoiceOver — a banner whose only way forward
    // was a button no screen reader could find.
    int taps = 0;
    await pumpScreen(
      tester,
      Scaffold(
        body: ListView(
          children: <Widget>[
            StatusBanner(
              title: 'Lageplan',
              message: 'Der Plan passt nicht zur Raumliste.',
              action: TextButton(
                onPressed: () => taps++,
                child: const Text('Erneut versuchen'),
              ),
            ),
          ],
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Erneut versuchen')),
      isSemantics(label: 'Erneut versuchen', hasTapAction: true),
    );

    await tester.tap(find.text('Erneut versuchen'));
    expect(taps, 1);
  });

  testWidgets('still reads its title and message as one sentence', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      Scaffold(body: ListView(children: const <Widget>[_banner])),
    );

    expect(
      find.bySemanticsLabel(
        'Lageplan. Der mitgelieferte Plan passt nicht zur aktuellen Raumliste.',
      ),
      findsOneWidget,
    );
  });
}
