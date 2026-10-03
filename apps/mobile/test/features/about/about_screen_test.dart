// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/widgets/brand_mark.dart';
import 'package:campus_koethen/features/about/presentation/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('the about wordmark uses a DPR-sized decode', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpScreen(
      tester,
      const AboutScreen(),
      overrides: <Override>[
        appVersionProvider.overrideWith(
          (ref) async =>
              const AppVersionInfo(version: '1.0.0', buildNumber: '1'),
        ),
      ],
    );
    await tester.pumpAndSettle();

    final Image image = tester.widget<Image>(
      find.descendant(
        of: find.byType(BrandWordmark),
        matching: find.byType(Image),
      ),
    );
    expect((image.image as ResizeImage).width, 900);
  });

  testWidgets('the licence page reuses the bounded brand mark', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpScreen(
      tester,
      const AboutScreen(),
      overrides: <Override>[
        appVersionProvider.overrideWith(
          (ref) async =>
              const AppVersionInfo(version: '1.0.0', buildNumber: '1'),
        ),
      ],
    );
    await tester.pumpAndSettle();
    final Finder licenses = find.byType(OutlinedButton);
    await tester.scrollUntilVisible(
      licenses,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // The fixed scroll step above only has to get the button built and
    // roughly on screen; shorter copy above it can leave the button's tap
    // point just past the viewport edge. ensureVisible() then aligns it
    // precisely, independent of exactly how much content sits above it.
    await tester.ensureVisible(licenses);
    await tester.pumpAndSettle();
    await tester.tap(licenses);
    await tester.pumpAndSettle();

    expect(find.byType(BrandMark), findsOneWidget);
    final Image image = tester.widget<Image>(
      find.descendant(of: find.byType(BrandMark), matching: find.byType(Image)),
    );
    expect((image.image as ResizeImage).width, 192);
  });
}
