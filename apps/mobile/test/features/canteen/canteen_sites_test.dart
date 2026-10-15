// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/site/campus_site.dart';
import 'package:campus_koethen/features/canteen/application/canteen_providers.dart';
import 'package:campus_koethen/features/canteen/data/canteen_models.dart';
import 'package:campus_koethen/features/canteen/domain/canteen_sites.dart';
import 'package:campus_koethen/features/canteen/presentation/canteen_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

const Canteen _fasanerie = Canteen(
  slug: 'koethen-fasanerieallee',
  displayName: 'Mensa Köthen',
  campusLabel: 'Fasanerieallee',
  site: CampusSite.koethen,
);
const Canteen _lohmann = Canteen(
  slug: 'koethen-lohmannstrasse',
  displayName: 'Mensa Lohmannstraße',
  campusLabel: 'Lohmannstraße',
  site: CampusSite.koethen,
);
const Canteen _dessau = Canteen(
  slug: 'dessau',
  displayName: 'Mensa Dessau',
  campusLabel: 'Dessau',
  site: CampusSite.dessau,
);
const Canteen _bernburg = Canteen(
  slug: 'bernburg',
  displayName: 'Mensa Bernburg',
  campusLabel: 'Bernburg',
  site: CampusSite.bernburg,
);
const List<Canteen> _all = <Canteen>[_fasanerie, _lohmann, _dessau, _bernburg];

Override _canteens(List<Canteen> canteens) => canteensProvider.overrideWith(
  (Ref ref) async =>
      Loaded<List<Canteen>>(value: canteens, meta: ApiMeta.empty),
);

List<String> _slugs(Iterable<Canteen> list) =>
    list.map((Canteen c) => c.slug).toList();

void main() {
  group('the site of a canteen', () {
    test('is read from the API answer', () {
      expect(
        Canteen.fromJson(<String, Object?>{
          'slug': 'dessau',
          'displayName': 'Mensa Dessau',
          'site': 'dessau',
        })!.site,
        CampusSite.dessau,
      );
    });

    test('is unknown for an older API or a site this app does not know', () {
      expect(Canteen.fromJson(<String, Object?>{'slug': 'a'})!.site, isNull);
      expect(
        Canteen.fromJson(<String, Object?>{'slug': 'a', 'site': 'halle'})!.site,
        isNull,
      );
    });
  });

  group('ordering by site', () {
    test('the own site comes first, the API order is kept', () {
      expect(_slugs(orderCanteensForSite(_all, CampusSite.dessau)), <String>[
        'dessau',
        'koethen-fasanerieallee',
        'koethen-lohmannstrasse',
        'bernburg',
      ]);
    });

    test('without a preference the API order stands', () {
      expect(_slugs(orderCanteensForSite(_all, null)), _slugs(_all));
    });

    test('canteens of an unknown site stay, after the known ones', () {
      const Canteen unknown = Canteen(slug: 'x', displayName: 'X');
      expect(
        _slugs(
          orderCanteensForSite(<Canteen>[unknown, _dessau], CampusSite.dessau),
        ),
        <String>['dessau', 'x'],
      );
    });

    test('nothing is dropped', () {
      expect(
        orderCanteensForSite(_all, CampusSite.bernburg),
        hasLength(_all.length),
      );
    });
  });

  group('the canteen shown first', () {
    Future<String?> selected(
      InMemoryKeyValueStore store, {
      List<Canteen> canteens = _all,
    }) async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          keyValueStoreProvider.overrideWithValue(store),
          _canteens(canteens),
        ],
      );
      addTearDown(container.dispose);
      container.listen(canteensProvider, (_, _) {});
      await container.read(canteensProvider.future);
      return container.read(selectedCanteenSlugProvider);
    }

    test('is the first canteen of the preferred site', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore()
        ..setString(PreferenceKeys.campusSite, 'dessau');

      expect(await selected(store), 'dessau');
    });

    test('is the first of all canteens without any preference', () async {
      expect(await selected(InMemoryKeyValueStore()), 'koethen-fasanerieallee');
    });

    test('a canteen chosen by hand beats the site', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore()
        ..setString(PreferenceKeys.campusSite, 'dessau')
        ..setString(PreferenceKeys.preferredCanteen, 'bernburg');

      expect(await selected(store), 'bernburg');
    });

    test('a site without a canteen falls back to the first one', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore()
        ..setString(PreferenceKeys.campusSite, 'bernburg');

      expect(
        await selected(store, canteens: const <Canteen>[_fasanerie, _lohmann]),
        'koethen-fasanerieallee',
      );
    });
  });

  group('the picker', () {
    Future<void> pumpPicker(
      WidgetTester tester, {
      CampusSite? site,
      List<Canteen> canteens = _all,
    }) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      if (site != null) {
        await store.setString(PreferenceKeys.campusSite, site.storageValue);
      }
      await pumpScreen(
        tester,
        const Scaffold(body: SingleChildScrollView(child: CanteenPickerList())),
        keyValueStore: store,
        overrides: <Override>[_canteens(canteens)],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('groups the canteens by site, the own site first', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, site: CampusSite.dessau);

      final double dessau = tester.getTopLeft(find.text('Dessau').first).dy;
      final double koethen = tester.getTopLeft(find.text('Köthen').first).dy;
      final double bernburg = tester.getTopLeft(find.text('Bernburg').first).dy;
      expect(dessau, lessThan(koethen));
      expect(koethen, lessThan(bernburg));
      expect(find.text('Mensa Dessau'), findsOneWidget);
      expect(find.text('Mensa Köthen'), findsOneWidget);
    });

    testWidgets('shows no headings when there is only one site', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, canteens: const <Canteen>[_fasanerie, _lohmann]);

      expect(find.text('Köthen'), findsNothing);
      expect(find.text('Mensa Köthen'), findsOneWidget);
    });

    testWidgets('picking a canteen of another site is remembered', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(CanteenPickerList)),
      );

      await tester.tap(find.text('Mensa Bernburg'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).preferredCanteenSlug, 'bernburg');
    });
  });
}
