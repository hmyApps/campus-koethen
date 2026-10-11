// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The default building has to actually do something.
///
/// It was stored, offered in the onboarding and offered in the settings — and
/// never read by the map. A setting that changes nothing is worse than no
/// setting: the user picks it, nothing happens, and they stop trusting the
/// rest of the preferences too.
library;

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/api_client.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/campusmap/data/map_asset_loader.dart';
import 'package:campus_koethen/features/campusmap/domain/map_catalog.dart';
import 'package:campus_koethen/features/campusmap/application/campus_map_providers.dart';
import 'package:campus_koethen/features/campusmap/presentation/campus_map_screen.dart';
import 'package:campus_koethen/features/campusmap/presentation/default_building_picker.dart';
import 'package:campus_koethen/features/campusmap/presentation/floor_map_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/pump_app.dart';

late final MapCatalog _catalog;

ApiClient _api() => fakeApiClient(
  FakeHttpAdapter((RequestOptions _) => FakeHttpResponse(envelope(<Object>[]))),
);

Future<void> pumpMap(WidgetTester tester, {String? defaultBuilding}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final InMemoryKeyValueStore store = InMemoryKeyValueStore();
  if (defaultBuilding != null) {
    await store.setString(PreferenceKeys.defaultBuilding, defaultBuilding);
  }

  await pumpScreen(
    tester,
    const CampusMapScreen(),
    locale: AppLocales.german,
    keyValueStore: store,
    overrides: <Override>[
      apiClientProvider.overrideWithValue(_api()),
      mapCatalogProvider.overrideWith((Ref ref) => _catalog),
    ],
  );
  await tester.pumpAndSettle();
}

String _shownFloorKey(WidgetTester tester) =>
    tester.widget<FloorMapView>(find.byType(FloorMapView)).floor.floorKey;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _catalog = await const MapAssetLoader().load();
  });

  testWidgets('without a preference the map opens on the first building', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);
    // Its lowest storey, not whichever floor happens to come first in the file.
    expect(_shownFloorKey(tester), 'ratke-gebaeude-ground-floor');
  });

  testWidgets('the chosen default building is the one that opens', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, defaultBuilding: 'koethen-03');
    expect(_shownFloorKey(tester), 'koethen-03-ground-floor');
  });

  testWidgets('a stale building key falls back instead of breaking', (
    WidgetTester tester,
  ) async {
    // A building removed from the catalogue in a later version must not leave
    // the map blank.
    await pumpMap(tester, defaultBuilding: 'a-building-that-was-removed');
    expect(_shownFloorKey(tester), 'ratke-gebaeude-ground-floor');
    expect(tester.takeException(), isNull);
  });

  group('settings tile', () {
    Future<ProviderContainer> pumpTile(
      WidgetTester tester, {
      String? defaultBuilding,
    }) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      if (defaultBuilding != null) {
        await store.setString(PreferenceKeys.defaultBuilding, defaultBuilding);
      }
      final ProviderContainer container = await pumpScreen(
        tester,
        const Scaffold(body: DefaultBuildingTile()),
        locale: AppLocales.german,
        keyValueStore: store,
        overrides: <Override>[
          mapCatalogProvider.overrideWith((Ref ref) => _catalog),
        ],
      );
      await tester.pumpAndSettle();
      return container;
    }

    String name(String key) => _catalog.building(key)!.name.resolve('de');

    testWidgets('names the stored building, or says that none is set', (
      WidgetTester tester,
    ) async {
      await pumpTile(tester);
      expect(find.text('Standardgebäude'), findsOneWidget);
      expect(find.text('Nicht festgelegt'), findsOneWidget);
    });

    testWidgets('a building picked in the sheet is stored and shown', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpTile(tester);

      await tester.tap(find.text('Standardgebäude'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name('koethen-03')));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).defaultBuildingKey, 'koethen-03');
      expect(find.text(name('koethen-03')), findsOneWidget);
      expect(find.text('Nicht festgelegt'), findsNothing);
    });

    testWidgets('the choice can be cleared again', (WidgetTester tester) async {
      final ProviderContainer container = await pumpTile(
        tester,
        defaultBuilding: 'koethen-03',
      );

      await tester.tap(find.text('Standardgebäude'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nicht festgelegt').last);
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).defaultBuildingKey, isNull);
    });
  });
}
