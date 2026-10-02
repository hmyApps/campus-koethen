// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/api_client.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/widgets/sheet_body.dart';
import 'package:campus_koethen/core/widgets/screen_scaffold.dart';
import 'package:campus_koethen/core/widgets/state_views.dart';
import 'package:campus_koethen/features/canteen/application/canteen_filter_controller.dart';
import 'package:campus_koethen/features/canteen/application/canteen_providers.dart';
import 'package:campus_koethen/features/canteen/presentation/canteen_screen.dart';
import 'package:campus_koethen/features/canteen/presentation/meal_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/fake_http_adapter.dart';
import '../../support/pump_app.dart';

String _today() {
  return _dayFromToday(0);
}

String _dayFromToday(int offset) {
  final DateTime now = DateTime.now();
  final DateTime date = DateTime(now.year, now.month, now.day + offset);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _meal(
  String id,
  String name, {
  List<String> traits = const <String>[],
  List<String> allergens = const <String>[],
  List<Map<String, dynamic>> prices = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'subtitle': null,
  'sourceLanguage': 'de',
  'isSprint': false,
  'extras': <String>[],
  'markers': <Map<String, dynamic>>[],
  'traits': traits,
  'allergens': allergens,
  'prices': prices.isEmpty ? _bothPrices : prices,
};

const List<Map<String, dynamic>> _bothPrices = <Map<String, dynamic>>[
  <String, dynamic>{
    'group': 'student',
    'label': 'Studierende',
    'amount': '1.95',
    'currency': 'EUR',
  },
  <String, dynamic>{
    'group': 'employee',
    'label': 'Beschäftigte',
    'amount': '4.95',
    'currency': 'EUR',
  },
];

ApiClient _api(
  List<Map<String, dynamic>> meals, {
  Map<int, List<Map<String, dynamic>>> additionalDays =
      const <int, List<Map<String, dynamic>>>{},
}) => fakeApiClient(
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
              for (final MapEntry<int, List<Map<String, dynamic>>> entry
                  in additionalDays.entries)
                <String, dynamic>{
                  'date': _dayFromToday(entry.key),
                  'meals': entry.value,
                },
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

Future<ProviderContainer> pumpCanteen(
  WidgetTester tester, {
  List<Map<String, dynamic>>? meals,
  KeyValueStore? store,
  Locale locale = AppLocales.german,
  Map<int, List<Map<String, dynamic>>> additionalDays =
      const <int, List<Map<String, dynamic>>>{},
}) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final ProviderContainer container = await pumpScreen(
    tester,
    const CanteenScreen(),
    locale: locale,
    keyValueStore: store,
    overrides: <Override>[
      apiClientProvider.overrideWithValue(
        _api(
          meals ??
              <Map<String, dynamic>>[
                _meal('1', 'Gemüsepfanne', traits: <String>['vegan']),
                _meal('2', 'Schnitzel'),
              ],
          additionalDays: additionalDays,
        ),
      ),
    ],
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('is named after the canteen and carries its two actions', (
    WidgetTester tester,
  ) async {
    await pumpCanteen(tester);

    expect(find.byType(AppBar), findsNothing);
    // The selected canteen is the page title. The stable Campus eyebrow keeps
    // the hierarchy clear without repeating "Mensa" twice.
    expect(find.text('Mensa Köthen'), findsOneWidget);
    final ScreenHeader header = tester.widget<ScreenHeader>(
      find.byType(ScreenHeader),
    );
    expect(header.eyebrow, 'Campus');
    expect(header.title, 'Mensa Köthen');
    expect(find.byTooltip('Filter'), findsOneWidget);
    expect(find.byTooltip('Mensa wählen'), findsOneWidget);
    expect(find.text('Gemüsepfanne'), findsOneWidget);
    expect(find.text('Schnitzel'), findsOneWidget);
  });

  testWidgets('swiping the menu changes the day in both directions', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpCanteen(
      tester,
      meals: <Map<String, dynamic>>[_meal('today', 'Gericht heute')],
      additionalDays: <int, List<Map<String, dynamic>>>{
        1: <Map<String, dynamic>>[_meal('tomorrow', 'Gericht morgen')],
      },
    );
    final DateTime before = container.read(selectedMenuDayProvider);

    await tester.fling(
      find.byType(ListView).first,
      const Offset(-250, 0),
      1000,
    );
    await tester.pumpAndSettle();

    final DateTime tomorrow = container.read(selectedMenuDayProvider);
    expect(DateTime(tomorrow.year, tomorrow.month, tomorrow.day - 1), before);
    expect(find.text('Gericht morgen'), findsOneWidget);
    expect(find.text('Gericht heute'), findsNothing);

    await tester.fling(find.byType(ListView).first, const Offset(250, 0), 1000);
    await tester.pumpAndSettle();

    expect(container.read(selectedMenuDayProvider), before);
    expect(find.text('Gericht heute'), findsOneWidget);
  });

  group('the fixed taxonomy', () {
    testWidgets('offers the four traits whatever the day holds', (
      WidgetTester tester,
    ) async {
      // A filter that appears and disappears with the day's offer cannot be
      // relied on. "Vegan" has to be there on a day without a vegan dish too.
      await pumpCanteen(
        tester,
        meals: <Map<String, dynamic>>[_meal('1', 'Schnitzel')],
      );

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilterChip, 'Vegetarisch'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Vegan'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Fleischlos'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Sprintmenü'), findsOneWidget);
    });

    testWidgets('shows the allergen subtypes under their parent', (
      WidgetTester tester,
    ) async {
      await pumpCanteen(tester);

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();

      expect(find.text('Enthält glutenhaltige Getreide'), findsOneWidget);
      expect(find.text('Weizen'), findsOneWidget);
      expect(find.text('Dinkel'), findsOneWidget);
      expect(find.text('Enthält Schalenfrüchte'), findsOneWidget);
      expect(find.text('Macadamianuss'), findsOneWidget);
    });

    testWidgets('a trait selected in the sheet narrows the list', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await pumpCanteen(tester, store: store);

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Vegan'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Gemüsepfanne'), findsOneWidget);
      expect(find.text('Schnitzel'), findsNothing);
      expect(find.byTooltip('Filter aktiv'), findsOneWidget);
      expect(store.getStringList(PreferenceKeys.canteenTraits), <String>[
        'vegan',
      ]);
    });
  });

  testWidgets('selecting a vegetarian trait still shows a vegan dish', (
    WidgetTester tester,
  ) async {
    // A vegan dish is vegetarian by definition, even when the source only
    // tags it "vegan".
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    await pumpCanteen(
      tester,
      store: store,
      meals: <Map<String, dynamic>>[
        _meal('1', 'Falafel', traits: <String>['vegan']),
        _meal('2', 'Schnitzel'),
      ],
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Vegetarisch'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Falafel'), findsOneWidget);
    expect(find.text('Schnitzel'), findsNothing);
  });

  testWidgets('selecting a parent allergen visibly checks its subtypes', (
    WidgetTester tester,
  ) async {
    await pumpCanteen(tester);

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enthält glutenhaltige Getreide'));
    await tester.pumpAndSettle();

    final CheckboxListTile wheat = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Weizen'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(wheat.value, isTrue);
  });

  testWidgets('deselecting one subtype shows the parent as partial', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.canteenAllergens: <String>['gluten'],
    });
    await pumpCanteen(tester, store: store);

    await tester.tap(find.byIcon(AppIcons.filter_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weizen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('teilweise ausgewählt'), findsOneWidget);
    final CheckboxListTile wheat = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Weizen'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(wheat.value, isFalse);
  });

  testWidgets('excluding a parent allergen hides a dish declared by subtype', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.canteenAllergens: <String>['gluten'],
    });

    await pumpCanteen(
      tester,
      store: store,
      meals: <Map<String, dynamic>>[
        _meal('1', 'Nudeln', allergens: <String>['gluten', 'gluten_wheat']),
        _meal('2', 'Reis'),
      ],
    );

    expect(find.text('Nudeln'), findsNothing);
    expect(find.text('Reis'), findsOneWidget);
  });

  testWidgets('a filter that matches nothing offers a way out', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.canteenTraits: <String>['vegan'],
    });

    await pumpCanteen(
      tester,
      store: store,
      meals: <Map<String, dynamic>>[_meal('1', 'Schnitzel')],
    );

    // Different from "nothing on offer", and this one has a remedy.
    expect(find.text('Kein Gericht passt zu deinem Filter.'), findsOneWidget);
    expect(find.text('Filter zurücksetzen'), findsWidgets);
  });

  testWidgets('an empty menu uses the canteen navigation icon', (
    WidgetTester tester,
  ) async {
    await pumpCanteen(tester, meals: <Map<String, dynamic>>[]);

    final Finder emptyView = find.byType(EmptyView);
    expect(
      find.descendant(of: emptyView, matching: find.byIcon(AppIcons.soup)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: emptyView,
        matching: find.byIcon(AppIcons.no_meals_outlined),
      ),
      findsNothing,
    );
  });

  group('prices', () {
    testWidgets('one card shows exactly one price, the student one', (
      WidgetTester tester,
    ) async {
      await pumpCanteen(
        tester,
        meals: <Map<String, dynamic>>[_meal('1', 'Gemüsepfanne')],
      );

      expect(find.text('Studierende'), findsOneWidget);
      expect(find.text('Beschäftigte'), findsNothing);
      expect(find.textContaining('1,95'), findsOneWidget);
      expect(find.textContaining('4,95'), findsNothing);
    });

    testWidgets('choosing another group replaces the price, not adds to it', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{PreferenceKeys.canteenPriceGroup: 'employee'},
      );

      await pumpCanteen(
        tester,
        store: store,
        meals: <Map<String, dynamic>>[_meal('1', 'Gemüsepfanne')],
      );

      expect(find.text('Beschäftigte'), findsOneWidget);
      expect(find.textContaining('4,95'), findsOneWidget);
      expect(find.text('Studierende'), findsNothing);
      expect(find.textContaining('1,95'), findsNothing);
    });

    testWidgets('a missing price is stated, never substituted', (
      WidgetTester tester,
    ) async {
      // Another group's price is a different number for a different person.
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{PreferenceKeys.canteenPriceGroup: 'guest'},
      );

      await pumpCanteen(
        tester,
        store: store,
        meals: <Map<String, dynamic>>[_meal('1', 'Gemüsepfanne')],
      );

      expect(
        find.text('Für diese Preisgruppe ist kein Preis hinterlegt.'),
        findsOneWidget,
      );
      expect(find.textContaining('1,95'), findsNothing);
    });

    testWidgets('the sheet offers only the groups this canteen has', (
      WidgetTester tester,
    ) async {
      await pumpCanteen(tester);

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(RadioListTile<String>, 'Studierende'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(RadioListTile<String>, 'Beschäftigte'),
        findsOneWidget,
      );
      expect(find.widgetWithText(RadioListTile<String>, 'Gäste'), findsNothing);
    });
  });

  group('favourites', () {
    testWidgets('starring a dish persists and marks it in words', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = await pumpCanteen(
        tester,
        store: store,
      );

      await tester.tap(find.byTooltip('Zu Favoriten').first);
      await tester.pumpAndSettle();

      expect(
        container.read(canteenFilterProvider).favourites,
        contains('Gemüsepfanne'),
      );
      expect(
        store.getStringList(PreferenceKeys.canteenFavourites),
        contains('Gemüsepfanne'),
      );
      // A filled star and a semantic label, never colour alone.
      expect(find.byIcon(AppIcons.star), findsNWidgets(2));
      expect(find.bySemanticsLabel(RegExp('Favorit')), findsWidgets);
    });

    testWidgets('do not change the order and do not hide anything', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{
          PreferenceKeys.canteenFavourites: <String>['Schnitzel'],
        },
      );

      await pumpCanteen(tester, store: store);

      final List<MealCard> cards = tester
          .widgetList<MealCard>(find.byType(MealCard))
          .toList();
      expect(cards.map((MealCard card) => card.meal.name), <String>[
        'Gemüsepfanne',
        'Schnitzel',
      ]);
    });
  });

  testWidgets('a dish can no longer be hidden', (WidgetTester tester) async {
    await pumpCanteen(tester);
    expect(find.byTooltip('Gericht ausblenden'), findsNothing);
  });

  testWidgets('renders in English', (WidgetTester tester) async {
    await pumpCanteen(tester, locale: AppLocales.english);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Must contain'), findsOneWidget);
    expect(find.text('Must not contain'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Vegan'), findsOneWidget);
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
      const CanteenScreen(),
      textScaler: const TextScaler.linear(2),
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          _api(<Map<String, dynamic>>[
            _meal('1', 'Ein sehr langer Gerichtname für den Umbruchtest'),
          ]),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('filter reset in bottom sheet', () {
    testWidgets(
      'is positioned directly below the title, before first section, and shows active state',
      (WidgetTester tester) async {
        await pumpCanteen(tester);

        await tester.tap(find.byTooltip('Filter'));
        await tester.pumpAndSettle();

        final Finder titleFinder = find.descendant(
          of: find.byType(SheetBody),
          matching: find.text('Filter'),
        );
        final Finder clearFinder = find.descendant(
          of: find.byType(SheetBody),
          matching: find.widgetWithText(TextButton, 'Filter zurücksetzen'),
        );
        final Finder mustContainFinder = find.descendant(
          of: find.byType(SheetBody),
          matching: find.text('Muss enthalten'),
        );

        expect(titleFinder, findsOneWidget);
        expect(clearFinder, findsOneWidget);
        expect(mustContainFinder, findsOneWidget);

        final double titleTop = tester.getTopLeft(titleFinder).dy;
        final double clearTop = tester.getTopLeft(clearFinder).dy;
        final double mustContainTop = tester.getTopLeft(mustContainFinder).dy;

        expect(titleTop, lessThan(clearTop));
        expect(clearTop, lessThan(mustContainTop));

        // When no filters are set, button is disabled.
        TextButton button = tester.widget<TextButton>(clearFinder);
        expect(button.onPressed, isNull);

        // Selecting a trait enables the button.
        await tester.tap(find.widgetWithText(FilterChip, 'Vegan'));
        await tester.pumpAndSettle();

        button = tester.widget<TextButton>(clearFinder);
        expect(button.onPressed, isNotNull);

        // Tapping reset clears traits and disables the button.
        await tester.tap(clearFinder);
        await tester.pumpAndSettle();

        button = tester.widget<TextButton>(clearFinder);
        expect(button.onPressed, isNull);

        final FilterChip chip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'Vegan'),
        );
        expect(chip.selected, isFalse);
      },
    );

    testWidgets('resets active filters and restores unfiltered list', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{
          PreferenceKeys.canteenTraits: <String>['vegan'],
        },
      );
      await pumpCanteen(
        tester,
        store: store,
        meals: <Map<String, dynamic>>[
          _meal('1', 'Gemüsepfanne', traits: <String>['vegan']),
          _meal('2', 'Schnitzel'),
        ],
      );

      // List initially filtered
      expect(find.text('Gemüsepfanne'), findsOneWidget);
      expect(find.text('Schnitzel'), findsNothing);

      await tester.tap(find.byTooltip('Filter aktiv'));
      await tester.pumpAndSettle();

      final Finder clearFinder = find.descendant(
        of: find.byType(SheetBody),
        matching: find.widgetWithText(TextButton, 'Filter zurücksetzen'),
      );
      expect(tester.widget<TextButton>(clearFinder).onPressed, isNotNull);

      await tester.tap(clearFinder);
      await tester.pumpAndSettle();

      // Close sheet
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Both meals visible again
      expect(find.text('Gemüsepfanne'), findsOneWidget);
      expect(find.text('Schnitzel'), findsOneWidget);
      expect(store.getStringList(PreferenceKeys.canteenTraits), isEmpty);
    });

    testWidgets('renders English title and clear button in correct order', (
      WidgetTester tester,
    ) async {
      await pumpCanteen(tester, locale: AppLocales.english);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();

      final Finder titleFinder = find.descendant(
        of: find.byType(SheetBody),
        matching: find.text('Filters'),
      );
      final Finder clearFinder = find.descendant(
        of: find.byType(SheetBody),
        matching: find.widgetWithText(TextButton, 'Clear filters'),
      );
      final Finder mustContainFinder = find.descendant(
        of: find.byType(SheetBody),
        matching: find.text('Must contain'),
      );

      expect(titleFinder, findsOneWidget);
      expect(clearFinder, findsOneWidget);
      expect(mustContainFinder, findsOneWidget);

      final double titleTop = tester.getTopLeft(titleFinder).dy;
      final double clearTop = tester.getTopLeft(clearFinder).dy;
      final double mustContainTop = tester.getTopLeft(mustContainFinder).dy;

      expect(titleTop, lessThan(clearTop));
      expect(clearTop, lessThan(mustContainTop));

      expect(tester.widget<TextButton>(clearFinder).onPressed, isNull);

      await tester.tap(find.widgetWithText(FilterChip, 'Vegan'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextButton>(clearFinder).onPressed, isNotNull);
    });

    testWidgets(
      'filter sheet survives a narrow phone with doubled text without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await pumpScreen(
          tester,
          const CanteenScreen(),
          textScaler: const TextScaler.linear(2),
          overrides: <Override>[
            apiClientProvider.overrideWithValue(
              _api(<Map<String, dynamic>>[
                _meal('1', 'Gemüsepfanne', traits: <String>['vegan']),
              ]),
            ),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Filter'));
        await tester.pumpAndSettle();

        expect(find.byType(SheetBody), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SheetBody),
            matching: find.widgetWithText(TextButton, 'Filter zurücksetzen'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
