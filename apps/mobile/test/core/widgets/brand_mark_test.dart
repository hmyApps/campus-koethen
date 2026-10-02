// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/widgets/brand_mark.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {double devicePixelRatio = 3}) => MaterialApp(
  supportedLocales: AppLocales.supported,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: MediaQuery(
    data: MediaQueryData(devicePixelRatio: devicePixelRatio),
    child: Scaffold(body: Center(child: child)),
  ),
);

ResizeImage _providerOf(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).image as ResizeImage;

void main() {
  testWidgets('the compact mark decodes at its physical paint width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(const BrandMark(size: 28)));

    expect(_providerOf(tester).width, 84);
  });

  testWidgets('the wordmark follows its logical width and device pixel ratio', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(const BrandWordmark(width: 300), devicePixelRatio: 2.5),
    );

    expect(_providerOf(tester).width, 750);
  });

  testWidgets('a decode request never exceeds the bundled raster width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(const BrandMark(size: 300), devicePixelRatio: 5),
    );

    expect(_providerOf(tester).width, 1024);
  });
}
