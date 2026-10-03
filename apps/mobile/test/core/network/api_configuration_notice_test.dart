// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_config.dart';
import 'package:campus_koethen/core/network/api_configuration_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

void main() {
  test('missing API configuration is visible in debug builds', () {
    expect(
      shouldShowApiConfigurationNotice(ApiConfigProblem.notConfigured),
      isTrue,
    );
  });

  testWidgets(
    'configuration failure is safe-area aware, live and large-text safe',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 32);
      addTearDown(tester.view.reset);

      await pumpScreen(
        tester,
        const Scaffold(body: ApiConfigurationNotice()),
        overrides: <Override>[
          apiConfigurationProblemProvider.overrideWithValue(
            ApiConfigProblem.insecureScheme,
          ),
        ],
        textScaler: const TextScaler.linear(2),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(ApiConfigurationNotice),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
      final Iterable<Semantics> semantics = tester.widgetList<Semantics>(
        find.descendant(
          of: find.byType(ApiConfigurationNotice),
          matching: find.byType(Semantics),
        ),
      );
      expect(
        semantics.any((Semantics node) => node.properties.liveRegion ?? false),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
