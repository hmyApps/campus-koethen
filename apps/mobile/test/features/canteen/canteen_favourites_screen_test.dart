// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_client.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/theme/app_dimensions.dart';
import 'package:campus_koethen/features/canteen/application/canteen_filter_controller.dart';
import 'package:campus_koethen/features/canteen/presentation/canteen_favourites_screen.dart';
import 'package:campus_koethen/features/canteen/presentation/meal_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/fake_http_adapter.dart';
import '../../support/pump_app.dart';

String _today() {
  final DateTime now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _meal(String id, String name) => <String, dynamic>{
  'id': id,
  'name': name,
  'subtitle': null,
  'sourceLanguage': 'de',
  'isSprint': false,
  'extras': <String>[],
  'markers': <Map<String, dynamic>>[],
  'traits': <String>[],
  'allergens': <String>[],
  'prices': <Map<String, dynamic>>[
    <String, dynamic>{
      'group': 'student',
      'label': 'Studierende',
      'amount': '1.95',
      'currency': 'EUR',
    },
  ],
};

ApiClient _api(List<Map<String, dynamic>> meals) => fakeApiClient(
  FakeHttpAdapter((RequestOptions options) {
    if (options.path.contains('/canteens/')) {
      return FakeHttpResponse(
        envelope(
          <String, dynamic>{
            'canteen': <String, dynamic>{
              'slug': 'mensa',
              'displayName': 'Mensa Köthen',
              'campusLabel': null,
            },
            'days': <Map<String, dynamic>>[
              <String, dynamic>{'date': _today(), 'meals': meals},
            ],
          },
          meta: <String, dynamic>{'dataStale': false},
        ),
      );
    }
    if (options.path.contains('/canteens')) {
      return FakeHttpResponse(
        envelope(<Map<String, dynamic>>[
          <String, dynamic>{
            'slug': 'mensa',
            'displayName': 'Mensa Köthen',
            'sortOrder': 10,
          },
        ]),
      );
    }
    return FakeHttpResponse(envelope(<Object>[]));
  }),
);

Future<ProviderContainer> pumpFavourites(
  WidgetTester tester, {
  List<Map<String, dynamic>>? meals,
  KeyValueStore? store,
}) async {
  final ProviderContainer container = await pumpScreen(
    tester,
    const CanteenFavouritesScreen(),
    keyValueStore: store,
    overrides: <Override>[
      apiClientProvider.overrideWithValue(
        _api(meals ?? <Map<String, dynamic>>[_meal('1', 'Gemüsepfanne')]),
      ),
    ],
  );
  // Two providers resolve in sequence (the canteen list, then its menu), each
  // over a real Future — `pump()` twice rather than `pumpAndSettle()`, which
  // this screen's chained FutureProviders leave unable to detect quiescence.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

void main() {
  testWidgets('explains itself when nothing is starred yet', (
    WidgetTester tester,
  ) async {
    await pumpFavourites(tester, store: InMemoryKeyValueStore());

    expect(find.text('Noch keine Favoriten'), findsOneWidget);
    expect(
      find.text(
        'Tippe im Speiseplan auf den Stern eines Gerichts, um es hier zu sammeln.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('lists a favourite with its current recognition data', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.canteenFavourites: <String>['Gemüsepfanne'],
    });

    await pumpFavourites(tester, store: store);

    expect(find.text('Gemüsepfanne'), findsOneWidget);
    expect(find.textContaining('1,95'), findsOneWidget);
    expect(find.byIcon(AppIcons.star), findsOneWidget);
  });

  testWidgets('a favourite no longer on any menu stays listed, not crashed', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.canteenFavourites: <String>['Verschwundenes Gericht'],
    });

    await pumpFavourites(tester, store: store);

    expect(find.text('Verschwundenes Gericht'), findsOneWidget);
    expect(find.text('Aktuell nicht im Speiseplan'), findsOneWidget);
  });

  testWidgets('every remove button is at least 48dp (G-06)', (
    WidgetTester tester,
  ) async {
    // One favourite on today's menu (rendered as a meal card) and one that
    // is not (the "unavailable" row) — both carry a remove button.
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.canteenFavourites: <String>[
        'Gemüsepfanne',
        'Verschwundenes Gericht',
      ],
    });

    await pumpFavourites(tester, store: store);

    final Finder buttons = find.byTooltip('Aus Favoriten entfernen');
    expect(buttons, findsNWidgets(2));
    for (final Element button in buttons.evaluate()) {
      final Size size = tester.getSize(find.byWidget(button.widget));
      expect(size.width, greaterThanOrEqualTo(AppSizes.minTouchTarget));
      expect(size.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
    }
  });

  testWidgets('removing a favourite here persists immediately', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.canteenFavourites: <String>['Gemüsepfanne'],
    });

    final ProviderContainer container = await pumpFavourites(
      tester,
      store: store,
    );

    await tester.tap(find.byTooltip('Aus Favoriten entfernen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(canteenFilterProvider).favourites,
      isNot(contains('Gemüsepfanne')),
    );
    expect(
      store.getStringList(PreferenceKeys.canteenFavourites),
      isNot(contains('Gemüsepfanne')),
    );
    expect(find.byType(MealCard), findsNothing);
    expect(find.text('Noch keine Favoriten'), findsOneWidget);
  });

  testWidgets(
    'removing an unavailable favourite by name persists immediately',
    (WidgetTester tester) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{
          PreferenceKeys.canteenFavourites: <String>['Verschwundenes Gericht'],
        },
      );

      final ProviderContainer container = await pumpFavourites(
        tester,
        store: store,
      );

      await tester.tap(find.byTooltip('Aus Favoriten entfernen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(canteenFilterProvider).favourites, isEmpty);
      expect(store.getStringList(PreferenceKeys.canteenFavourites), isEmpty);
      expect(find.text('Noch keine Favoriten'), findsOneWidget);
    },
  );

  testWidgets('lists many favourites in name order, built as they scroll', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final List<String> names = <String>[
      for (int i = 0; i < 30; i++) 'Gericht ${i.toString().padLeft(2, '0')}',
    ];
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      // Deliberately out of order: the screen sorts by name.
      PreferenceKeys.canteenFavourites: names.reversed.toList(),
    });

    await pumpFavourites(
      tester,
      store: store,
      meals: <Map<String, dynamic>>[
        for (int i = 0; i < names.length; i++) _meal('$i', names[i]),
      ],
    );

    final int built = tester.widgetList(find.byType(MealCard)).length;
    expect(built, greaterThan(0));
    expect(built, lessThan(names.length));

    // The first card is the alphabetically first name, not the stored one.
    expect(find.text('Gericht 00'), findsOneWidget);
    expect(find.text('Gericht 29'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Gericht 29'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Gericht 29'), findsOneWidget);
  });
}
