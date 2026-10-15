// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/campusmap/data/map_asset_loader.dart';
import 'package:campus_koethen/features/campusmap/domain/map_catalog.dart';
import 'package:campus_koethen/core/site/campus_site.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the bundled catalogue', () {
    test('loads all generated buildings', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();

      expect(catalog.mapVersion, isNotEmpty);
      // Fourteen approved real storeys across four buildings.
      expect(catalog.rooms, hasLength(292));
      expect(catalog.floors, hasLength(14));
      expect(catalog.buildings, hasLength(4));
      expect(catalog.buildings.map((MapBuilding b) => b.buildingKey), <String>[
        'ratke-gebaeude',
        'koethen-01',
        'koethen-02',
        'koethen-03',
      ]);
      expect(catalog.hasSeveralBuildings, isTrue);
    });

    test(
      'every current plan belongs to Köthen, the other sites have none',
      () async {
        final MapCatalog catalog = await const MapAssetLoader().load();

        for (final MapBuilding building in catalog.buildings) {
          expect(
            building.site,
            CampusSite.koethen,
            reason: building.buildingKey,
          );
        }
        expect(catalog.buildingsOf(CampusSite.koethen), hasLength(4));
        expect(catalog.buildingsOf(CampusSite.bernburg), isEmpty);
        expect(catalog.buildingsOf(CampusSite.dessau), isEmpty);
      },
    );

    test('a building without a (or with an unknown) site is a Köthen one', () {
      // A catalogue generated before sites existed, or by a newer generator.
      expect(
        MapBuilding.fromJson(<String, Object?>{'buildingKey': 'a'})!.site,
        CampusSite.koethen,
      );
      expect(
        MapBuilding.fromJson(<String, Object?>{
          'buildingKey': 'a',
          'siteKey': 'atlantis',
        })!.site,
        CampusSite.koethen,
      );
      expect(
        MapBuilding.fromJson(<String, Object?>{
          'buildingKey': 'a',
          'siteKey': 'dessau',
        })!.site,
        CampusSite.dessau,
      );
    });

    test('carries building and floor names in both languages', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();

      final MapBuilding ratke = catalog.building('ratke-gebaeude')!;
      expect(ratke.buildingNumber, '23');
      expect(ratke.name.resolve('de'), 'Ratke-Gebäude');
      expect(ratke.name.resolve('en'), 'Ratke Building');
      expect(
        catalog.floor('ratke-gebaeude-ground-floor')!.name.resolve('en'),
        'Ground floor',
      );
      expect(ratke.resolvedSourceAttribution('de'), 'Hochschule Anhalt');
      expect(ratke.resolvedSourceAttribution('en'), 'Hochschule Anhalt');

      final MapBuilding redBuilding = catalog.building('koethen-01')!;
      expect(redBuilding.buildingNumber, '01');
      expect(redBuilding.name.resolve('de'), 'Rotes Gebäude');
      expect(redBuilding.name.resolve('en'), 'Red Building');
      expect(redBuilding.resolvedSourceAttribution('de'), 'Hochschule Anhalt');

      final MapBuilding greenBuilding = catalog.building('koethen-02')!;
      expect(greenBuilding.buildingNumber, '02');
      expect(greenBuilding.name.resolve('de'), 'Grünes Gebäude');
      expect(greenBuilding.name.resolve('en'), 'Green Building');
      expect(
        greenBuilding.resolvedSourceAttribution('en'),
        'Hochschule Anhalt',
      );

      final MapBuilding whiteBuilding = catalog.building('koethen-03')!;
      expect(whiteBuilding.buildingNumber, '03');
      expect(whiteBuilding.name.resolve('de'), 'Weißes Gebäude');
      expect(whiteBuilding.name.resolve('en'), 'White Building');
      expect(
        whiteBuilding.resolvedSourceAttribution('de'),
        'Hochschule Anhalt',
      );
      // An unsupported locale falls back to German rather than to a key.
      expect(ratke.name.resolve('fr'), 'Ratke-Gebäude');
    });

    test('states what kind of drawing each building is', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();

      expect(catalog.building('ratke-gebaeude')!.planKind, PlanKind.schematic);
      expect(PlanKind.fromName('schematic'), PlanKind.schematic);
    });

    test('floors are scoped to their building', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();

      // Lowest storey first — the order the picker offers them in.
      expect(
        catalog.floorsOf('ratke-gebaeude').map((MapFloor f) => f.floorKey),
        <String>['ratke-gebaeude-ground-floor', 'ratke-gebaeude-first-floor'],
      );
      expect(
        catalog.floorsOf('koethen-01').map((MapFloor f) => f.floorKey),
        <String>[
          'koethen-01-basement',
          'koethen-01-first-floor',
          'koethen-01-second-floor',
          'koethen-01-third-floor',
          'koethen-01-roof',
        ],
      );
      expect(
        catalog.floorsOf('koethen-02').map((MapFloor f) => f.floorKey),
        <String>[
          'koethen-02-basement',
          'koethen-02-ground-floor',
          'koethen-02-first-floor',
          'koethen-02-second-floor',
        ],
      );
      expect(
        catalog.floorsOf('koethen-03').map((MapFloor f) => f.floorKey),
        <String>[
          'koethen-03-ground-floor',
          'koethen-03-first-floor',
          'koethen-03-second-floor',
        ],
      );
      expect(catalog.floorsOf('does-not-exist'), isEmpty);
      expect(
        catalog.buildingOfFloor('ratke-gebaeude-first-floor'),
        'ratke-gebaeude',
      );
      expect(catalog.buildingOfFloor('nope'), isNull);
      expect(catalog.building('nope'), isNull);
    });

    test('resolves geometry for a known room', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();
      final MapRoomGeometry? geometry = catalog.geometryFor(
        'ratke-gebaeude-first-floor-216',
      );

      expect(geometry, isNotNull);
      expect(geometry!.floorKey, 'ratke-gebaeude-first-floor');
      expect(geometry.svgElementId, 'room-ratke-gebaeude-first-floor-216');
      expect(geometry.bounds.width, greaterThan(0));
      expect(geometry.focus.dx, greaterThan(0));
    });

    test('resolves Ratke room geometry and grouped room labels', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();
      final MapRoomGeometry? room101 = catalog.geometryFor(
        'ratke-gebaeude-ground-floor-101',
      );
      final MapRoomGeometry? grouped = catalog.geometryFor(
        'ratke-gebaeude-first-floor-223-225',
      );

      expect(room101, isNotNull);
      expect(room101!.floorKey, 'ratke-gebaeude-ground-floor');
      expect(room101.svgElementId, 'room-ratke-gebaeude-ground-floor-101');
      expect(grouped, isNotNull);
      expect(grouped!.floorKey, 'ratke-gebaeude-first-floor');
    });

    test('resolves geometry from all added buildings', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();

      final MapRoomGeometry? red = catalog.geometryFor(
        'koethen-01-first-floor-121-0',
      );
      final MapRoomGeometry? green = catalog.geometryFor(
        'koethen-02-basement-minus-1-01',
      );
      final MapRoomGeometry? white = catalog.geometryFor(
        'koethen-03-ground-floor-003',
      );

      expect(red, isNotNull);
      expect(red!.buildingKey, 'koethen-01');
      expect(red.floorKey, 'koethen-01-first-floor');
      expect(green, isNotNull);
      expect(green!.buildingKey, 'koethen-02');
      expect(green.floorKey, 'koethen-02-basement');
      expect(white, isNotNull);
      expect(white!.buildingKey, 'koethen-03');
      expect(white.floorKey, 'koethen-03-ground-floor');
    });

    test('returns null for an unknown room instead of throwing', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();
      expect(catalog.geometryFor('does-not-exist'), isNull);
    });

    test('exposes the floor with its SVG asset and viewBox', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();
      final MapFloor? floor = catalog.floor('ratke-gebaeude-first-floor');

      expect(floor, isNotNull);
      expect(floor!.svgAsset, 'assets/maps/ratke-gebaeude/first-floor.svg');
      expect(floor.viewBox.width, greaterThan(0));
      expect(floor.level, 1);
    });

    test('the rooms of a floor are exactly the ones on it', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();

      for (final MapFloor floor in catalog.floors) {
        expect(
          catalog
              .roomsOnFloor(floor.floorKey)
              .map((MapRoomGeometry r) => r.roomKey),
          catalog.rooms
              .where((MapRoomGeometry r) => r.floorKey == floor.floorKey)
              .map((MapRoomGeometry r) => r.roomKey),
          reason:
              '${floor.floorKey} must list its own rooms, in catalogue order',
        );
      }
      expect(catalog.roomsOnFloor('does-not-exist'), isEmpty);
      // Every room belongs to exactly one floor's list.
      expect(
        catalog.floors.fold<int>(
          0,
          (int sum, MapFloor f) =>
              sum + catalog.roomsOnFloor(f.floorKey).length,
        ),
        catalog.rooms.length,
      );
    });

    test('the precomputed lists cannot be written to', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();
      expect(
        () => catalog.floorsOf('ratke-gebaeude').clear(),
        throwsUnsupportedError,
      );
      expect(
        () => catalog.roomsOnFloor('ratke-gebaeude-first-floor').clear(),
        throwsUnsupportedError,
      );
    });

    test('every room resolves to an existing floor', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();
      for (final MapRoomGeometry room in catalog.rooms) {
        expect(
          catalog.floor(room.floorKey),
          isNotNull,
          reason: '${room.roomKey} points at an unknown floor',
        );
      }
    });
  });

  group('map version compatibility', () {
    test('accepts a matching version', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();
      expect(catalog.supportsMapVersion(catalog.mapVersion), isTrue);
    });

    test('reports a mismatch so the UI can explain it', () async {
      final MapCatalog catalog = await const MapAssetLoader().load();
      expect(catalog.supportsMapVersion('some-other-version'), isFalse);
    });

    test('treats an empty or missing server version as compatible', () async {
      // A room without mapVersion must not disable the map; the geometry lookup
      // is what really decides whether a room can be shown.
      final MapCatalog catalog = await const MapAssetLoader().load();
      expect(catalog.supportsMapVersion(''), isTrue);
      expect(catalog.supportsMapVersion(null), isTrue);
    });
  });

  group('parsing', () {
    test('rejects a payload without rooms rather than half-loading it', () {
      expect(MapCatalog.fromJson(<String, dynamic>{'mapVersion': 'x'}), isNull);
    });

    test('skips a malformed room but keeps the rest', () {
      final MapCatalog? catalog = MapCatalog.fromJson(<String, dynamic>{
        'schemaVersion': 1,
        'mapVersion': 'x',
        'buildings': <Object?>[
          <String, dynamic>{'buildingKey': 'b', 'sortOrder': 0},
        ],
        'floors': <Object?>[
          <String, dynamic>{
            'floorKey': 'f',
            'buildingKey': 'b',
            'level': 1,
            'svgAsset': 'assets/maps/x.svg',
            'viewBox': <String, dynamic>{
              'minX': 0,
              'minY': 0,
              'width': 10,
              'height': 10,
            },
            'sortOrder': 0,
          },
        ],
        'rooms': <Object?>[
          <String, dynamic>{
            'roomKey': 'ok',
            'roomNumber': 'A.1',
            'buildingKey': 'b',
            'floorKey': 'f',
            'roomType': 'office',
            'svgElementId': 'room-ok',
            'focus': <String, dynamic>{'x': 1, 'y': 2},
            'bounds': <String, dynamic>{
              'x': 0,
              'y': 0,
              'width': 4,
              'height': 4,
            },
            'sortOrder': 0,
          },
          <String, dynamic>{'roomNumber': 'no key'},
        ],
      });

      expect(catalog, isNotNull);
      expect(catalog!.rooms, hasLength(1));
      expect(catalog.geometryFor('ok'), isNotNull);
    });
  });
}
