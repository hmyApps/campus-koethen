// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The canteen's selected day follows the calendar day (G-04).
///
/// The menu window is re-requested from "today" on every refresh, so a
/// selection left on yesterday after midnight pointed at a day the menu no
/// longer contains — "no data", plus an offered "Today" button.
library;

import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/features/canteen/application/canteen_providers.dart';
import 'package:campus_koethen/features/canteen/presentation/canteen_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/pump_app.dart';

void main() {
  late DateTime now;

  setUp(() => now = DateTime(2026, 10, 14, 23, 50));

  ProviderContainer container() {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[canteenClockProvider.overrideWithValue(() => now)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the selected menu day', () {
    test('starts on today', () {
      expect(container().read(selectedMenuDayProvider), DateTime(2026, 10, 14));
    });

    test('moves on to the new day when it was following today', () {
      final ProviderContainer c = container();
      expect(c.read(selectedMenuDayProvider), DateTime(2026, 10, 14));

      now = DateTime(2026, 10, 15, 7);
      c.read(selectedMenuDayProvider.notifier).followToday();

      expect(c.read(selectedMenuDayProvider), DateTime(2026, 10, 15));
    });

    test('keeps a day the reader chose deliberately', () {
      final ProviderContainer c = container();
      c.read(selectedMenuDayProvider.notifier).select(DateTime(2026, 10, 16));

      now = DateTime(2026, 10, 15, 7);
      c.read(selectedMenuDayProvider.notifier).followToday();

      expect(c.read(selectedMenuDayProvider), DateTime(2026, 10, 16));
    });

    test('follows today again once the reader went back to it', () {
      final ProviderContainer c = container();
      final SelectedMenuDayController controller = c.read(
        selectedMenuDayProvider.notifier,
      );
      controller.shiftBy(1);
      controller.shiftBy(-1);

      now = DateTime(2026, 10, 15, 7);
      controller.followToday();

      expect(c.read(selectedMenuDayProvider), DateTime(2026, 10, 15));
    });
  });

  testWidgets('the canteen screen catches up with a new day on resume', (
    WidgetTester tester,
  ) async {
    final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.path.contains('/canteens/')) {
        return FakeHttpResponse(
          envelope(<String, dynamic>{
            'canteen': <String, dynamic>{
              'slug': 'demo-mensa',
              'displayName': 'Demo-Mensa',
            },
            'days': <Object>[],
          }),
        );
      }
      return FakeHttpResponse(
        envelope(<Map<String, dynamic>>[
          <String, dynamic>{'slug': 'demo-mensa', 'displayName': 'Demo-Mensa'},
        ]),
      );
    });
    final ProviderContainer c = await pumpScreen(
      tester,
      const CanteenScreen(),
      overrides: <Override>[
        canteenClockProvider.overrideWithValue(() => now),
        apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
      ],
    );
    await tester.pumpAndSettle();
    expect(c.read(selectedMenuDayProvider), DateTime(2026, 10, 14));

    // The phone sat in a pocket over midnight.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 10, 15, 7);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(c.read(selectedMenuDayProvider), DateTime(2026, 10, 15));
  });
}
