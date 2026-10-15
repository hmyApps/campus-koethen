// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:ui' show Rect;

import 'package:campus_koethen/core/site/campus_site.dart';
import 'package:campus_koethen/features/campusmap/domain/map_catalog.dart';
import 'package:campus_koethen/features/campusmap/domain/visible_building.dart';
import 'package:flutter_test/flutter_test.dart';

MapBuilding _building(String key, CampusSite site, int order) => MapBuilding(
  buildingKey: key,
  buildingNumber: null,
  name: LocalisedName(de: key, en: key),
  planKind: PlanKind.schematic,
  sourceAttribution: null,
  sortOrder: order,
  site: site,
);

MapFloor _floor(String building) => MapFloor(
  floorKey: '$building-0',
  buildingKey: building,
  level: 0,
  name: const LocalisedName(de: 'EG', en: 'GF'),
  svgAsset: 'x.svg',
  viewBox: const Rect.fromLTWH(0, 0, 10, 10),
  sortOrder: 0,
);

void main() {
  final MapCatalog map = MapCatalog(
    schemaVersion: 1,
    mapVersion: 'demo',
    buildings: <MapBuilding>[
      _building('k1', CampusSite.koethen, 1),
      _building('k2', CampusSite.koethen, 2),
      _building('d1', CampusSite.dessau, 3),
    ],
    floors: <MapFloor>[_floor('k1'), _floor('k2'), _floor('d1')],
    rooms: const <MapRoomGeometry>[],
  );

  VisibleBuilding resolve({
    String? explicitBuilding,
    String? explicitFloor,
    String? defaultBuildingKey,
    CampusSite? explicitSite,
    CampusSite? preferredSite,
  }) => resolveVisibleBuilding(
    map: map,
    explicitBuilding: explicitBuilding,
    explicitFloor: explicitFloor,
    roomBuilding: null,
    defaultBuildingKey: defaultBuildingKey,
    explicitSite: explicitSite,
    preferredSite: preferredSite,
  );

  test('without any choice the map opens on Köthen', () {
    final VisibleBuilding v = resolve();

    expect(v.site, CampusSite.koethen);
    expect(v.buildingKey, 'k1');
  });

  test('the preferred site decides where the map opens', () {
    final VisibleBuilding v = resolve(preferredSite: CampusSite.dessau);

    expect(v.site, CampusSite.dessau);
    expect(v.buildingKey, 'd1');
  });

  test('the default building counts only inside the site shown', () {
    expect(
      resolve(defaultBuildingKey: 'k2').buildingKey,
      'k2',
      reason: 'the default building of the shown site',
    );
    expect(
      resolve(
        defaultBuildingKey: 'k2',
        preferredSite: CampusSite.dessau,
      ).buildingKey,
      'd1',
      reason: 'a Köthen default does not drag a Dessau reader back',
    );
  });

  test('a site chosen on the map beats the preference', () {
    final VisibleBuilding v = resolve(
      explicitSite: CampusSite.koethen,
      preferredSite: CampusSite.dessau,
    );

    expect(v.site, CampusSite.koethen);
    expect(v.buildingKey, 'k1');
  });

  test('a site without plans shows no building, and says which site', () {
    final VisibleBuilding v = resolve(explicitSite: CampusSite.bernburg);

    expect(v.site, CampusSite.bernburg);
    expect(v.buildingKey, isNull);
  });

  test('an explicit building decides the site, whatever else is chosen', () {
    final VisibleBuilding v = resolve(
      explicitBuilding: 'd1',
      explicitSite: CampusSite.koethen,
      preferredSite: CampusSite.koethen,
    );

    expect(v.site, CampusSite.dessau);
    expect(v.buildingKey, 'd1');
  });

  test('a floor decides the building and so the site', () {
    final VisibleBuilding v = resolve(explicitFloor: 'd1-0');

    expect(v.buildingKey, 'd1');
    expect(v.site, CampusSite.dessau);
  });

  test('a room link lands on its building', () {
    final VisibleBuilding v = resolveVisibleBuilding(
      map: map,
      explicitBuilding: null,
      explicitFloor: null,
      roomBuilding: 'k2',
      defaultBuildingKey: null,
      explicitSite: CampusSite.dessau,
      preferredSite: null,
    );

    expect(v.buildingKey, 'k2');
    expect(v.site, CampusSite.koethen);
  });

  test('before the catalogue is loaded nothing is shown', () {
    final VisibleBuilding v = resolveVisibleBuilding(
      map: null,
      explicitBuilding: null,
      explicitFloor: null,
      roomBuilding: null,
      defaultBuildingKey: null,
      explicitSite: null,
      preferredSite: CampusSite.dessau,
    );

    expect(v.buildingKey, isNull);
    expect(v.site, CampusSite.dessau);
  });
}
