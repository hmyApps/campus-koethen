// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:ui' show Offset, Rect;

import '../../../core/network/json.dart';
import '../../../core/site/campus_site.dart';

/// The bundled, generated map catalogue.
///
/// It is produced by `packages/campus-map` and ships as an asset, so the app
/// never parses the canonical drawing at runtime to discover its structure.
///
/// It carries geometry, stable keys and the names of the map's own navigation
/// in both languages. ROOM prose still comes from the Campus API per locale —
/// but a building without rooms has no room DTO to carry its name, so building
/// and floor names travel with the bundle and work offline.

/// What kind of drawing a building's plan is.
///
/// The app states this to the user, so a wrong value would be a false claim
/// rather than a cosmetic detail. The bundled catalogue is validated before
/// generation, so only the supported schematic value can reach production.
enum PlanKind {
  /// A simplified, not-to-scale overview of a real site. Explicitly **not** a
  /// fire, escape or rescue plan.
  schematic;

  static PlanKind fromName(String? value) => PlanKind.schematic;
}

/// A name that exists in both supported languages.
///
/// Kept as one small type so every localised catalogue name is resolved the
/// same way, and adding a locale later touches one place.
class LocalisedName {
  const LocalisedName({required this.de, required this.en});

  final String de;
  final String en;

  /// German is canonical; anything that is not English falls back to it.
  String resolve(String localeCode) => localeCode == 'en' ? en : de;

  static LocalisedName fromJson(
    Map<String, dynamic>? map, {
    required String fallback,
  }) {
    final String de = asString(map?['nameDe']) ?? fallback;
    return LocalisedName(de: de, en: asString(map?['nameEn']) ?? de);
  }
}

class MapBuilding {
  const MapBuilding({
    required this.buildingKey,
    required this.buildingNumber,
    required this.name,
    required this.planKind,
    required this.sourceAttribution,
    required this.sortOrder,
    this.site = CampusSite.koethen,
  });

  final String buildingKey;
  final String? buildingNumber;
  final LocalisedName name;
  final PlanKind planKind;
  final LocalisedName? sourceAttribution;
  final int sortOrder;

  /// The campus site the building stands on. A catalogue that predates sites
  /// (or names one this app does not know) means Köthen: every plan the
  /// project has ever shipped is a Köthen one.
  final CampusSite site;

  String? resolvedSourceAttribution(String localeCode) =>
      sourceAttribution?.resolve(localeCode);

  static MapBuilding? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    final String? key = asString(map?['buildingKey']);
    if (key == null) return null;
    final String? sourceDe = asString(map?['sourceAttributionDe']);
    return MapBuilding(
      buildingKey: key,
      buildingNumber: asString(map?['buildingNumber']),
      name: LocalisedName.fromJson(map, fallback: key),
      planKind: PlanKind.fromName(asString(map?['planKind'])),
      sourceAttribution: sourceDe == null
          ? null
          : LocalisedName(
              de: sourceDe,
              en: asString(map?['sourceAttributionEn']) ?? sourceDe,
            ),
      sortOrder: asInt(map?['sortOrder']) ?? 0,
      site:
          CampusSite.fromStorage(asString(map?['siteKey'])) ??
          CampusSite.koethen,
    );
  }
}

class MapFloor {
  const MapFloor({
    required this.floorKey,
    required this.buildingKey,
    required this.level,
    required this.name,
    required this.svgAsset,
    required this.viewBox,
    required this.sortOrder,
  });

  final String floorKey;
  final String buildingKey;
  final int level;
  final LocalisedName name;
  final String svgAsset;
  final Rect viewBox;
  final int sortOrder;

  static MapFloor? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? floorKey = asString(map['floorKey']);
    final String? buildingKey = asString(map['buildingKey']);
    final String? svgAsset = asString(map['svgAsset']);
    final Rect? viewBox = _rectFromJson(map['viewBox']);
    if (floorKey == null ||
        buildingKey == null ||
        svgAsset == null ||
        viewBox == null) {
      return null;
    }
    return MapFloor(
      floorKey: floorKey,
      buildingKey: buildingKey,
      level: asInt(map['level']) ?? 0,
      name: LocalisedName.fromJson(map, fallback: floorKey),
      svgAsset: svgAsset,
      viewBox: viewBox,
      sortOrder: asInt(map['sortOrder']) ?? 0,
    );
  }
}

class MapRoomGeometry {
  const MapRoomGeometry({
    required this.roomKey,
    required this.buildingKey,
    required this.floorKey,
    required this.svgElementId,
    required this.focus,
    required this.bounds,
  });

  final String roomKey;
  final String buildingKey;
  final String floorKey;
  final String svgElementId;

  /// The point the view centres on when this room is selected.
  final Offset focus;

  /// The room outline, used to draw the highlight and to frame the view.
  final Rect bounds;

  static MapRoomGeometry? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? roomKey = asString(map['roomKey']);
    final String? floorKey = asString(map['floorKey']);
    final String? svgElementId = asString(map['svgElementId']);
    final Rect? bounds = _boundsFromJson(map['bounds']);
    final Offset? focus = _offsetFromJson(map['focus']);
    if (roomKey == null ||
        floorKey == null ||
        svgElementId == null ||
        bounds == null ||
        focus == null) {
      return null;
    }
    return MapRoomGeometry(
      roomKey: roomKey,
      buildingKey: asString(map['buildingKey']) ?? '',
      floorKey: floorKey,
      svgElementId: svgElementId,
      focus: focus,
      bounds: bounds,
    );
  }
}

class MapCatalog {
  MapCatalog({
    required this.schemaVersion,
    required this.mapVersion,
    required this.buildings,
    required this.floors,
    required List<MapRoomGeometry> rooms,
  }) : rooms = List<MapRoomGeometry>.unmodifiable(rooms),
       _roomsByKey = <String, MapRoomGeometry>{
         for (final MapRoomGeometry room in rooms) room.roomKey: room,
       },
       _floorsByKey = <String, MapFloor>{
         for (final MapFloor floor in floors) floor.floorKey: floor,
       },
       _buildingsByKey = <String, MapBuilding>{
         for (final MapBuilding building in buildings)
           building.buildingKey: building,
       },
       _floorsByBuilding = _groupFloorsByBuilding(floors),
       _roomsByFloor = _groupRoomsByFloor(rooms);

  static const int supportedSchemaVersion = 1;

  final int schemaVersion;
  final String mapVersion;
  final List<MapBuilding> buildings;
  final List<MapFloor> floors;
  final List<MapRoomGeometry> rooms;

  final Map<String, MapRoomGeometry> _roomsByKey;
  final Map<String, MapFloor> _floorsByKey;

  // The catalogue is a bundled, immutable asset, so everything derived from it
  // is derived once here rather than on every rebuild of the map screen —
  // which used to re-filter and re-sort these lists on every keystroke in the
  // room search.
  final Map<String, MapBuilding> _buildingsByKey;
  final Map<String, List<MapFloor>> _floorsByBuilding;
  final Map<String, List<MapRoomGeometry>> _roomsByFloor;

  static Map<String, List<MapFloor>> _groupFloorsByBuilding(
    List<MapFloor> floors,
  ) {
    final Map<String, List<MapFloor>> byBuilding = <String, List<MapFloor>>{};
    for (final MapFloor floor in floors) {
      (byBuilding[floor.buildingKey] ??= <MapFloor>[]).add(floor);
    }
    return <String, List<MapFloor>>{
      for (final MapEntry<String, List<MapFloor>> entry in byBuilding.entries)
        entry.key: List<MapFloor>.unmodifiable(
          entry.value..sort((MapFloor a, MapFloor b) {
            final int order = a.sortOrder.compareTo(b.sortOrder);
            return order != 0 ? order : a.level.compareTo(b.level);
          }),
        ),
    };
  }

  static Map<String, List<MapRoomGeometry>> _groupRoomsByFloor(
    List<MapRoomGeometry> rooms,
  ) {
    final Map<String, List<MapRoomGeometry>> byFloor =
        <String, List<MapRoomGeometry>>{};
    for (final MapRoomGeometry room in rooms) {
      (byFloor[room.floorKey] ??= <MapRoomGeometry>[]).add(room);
    }
    return <String, List<MapRoomGeometry>>{
      for (final MapEntry<String, List<MapRoomGeometry>> entry
          in byFloor.entries)
        entry.key: List<MapRoomGeometry>.unmodifiable(entry.value),
    };
  }

  /// Geometry for a room, or `null` when the bundled map does not know it.
  ///
  /// A `null` here is a normal, expected state: the API may serve a room the
  /// bundled map predates. The UI then shows the text and disables the map
  /// action rather than failing.
  MapRoomGeometry? geometryFor(String roomKey) => _roomsByKey[roomKey];

  MapFloor? floor(String floorKey) => _floorsByKey[floorKey];

  MapBuilding? building(String? buildingKey) =>
      buildingKey == null ? null : _buildingsByKey[buildingKey];

  /// Whether the map offers anything to choose between.
  ///
  /// The building picker only appears once this is true, so a single-building
  /// bundle looks exactly as it did before.
  bool get hasSeveralBuildings => buildings.length > 1;

  /// The buildings of one campus site, in display order.
  List<MapBuilding> buildingsOf(CampusSite site) => <MapBuilding>[
    for (final MapBuilding building in buildings)
      if (building.site == site) building,
  ];

  /// The building a floor belongs to, or `null` for an unknown floor.
  String? buildingOfFloor(String? floorKey) =>
      floorKey == null ? null : _floorsByKey[floorKey]?.buildingKey;

  /// Floors of one building, in display order.
  List<MapFloor> floorsOf(String buildingKey) =>
      _floorsByBuilding[buildingKey] ?? const <MapFloor>[];

  /// The room geometry of one floor.
  ///
  /// The map screen hands exactly this to the plan, so a room one storey up
  /// can never answer a tap. Precomputed because the screen asked for it on
  /// every rebuild — including every keystroke in the room search.
  List<MapRoomGeometry> roomsOnFloor(String floorKey) =>
      _roomsByFloor[floorKey] ?? const <MapRoomGeometry>[];

  /// Whether the bundled map matches what the server describes.
  ///
  /// An absent or empty server version is treated as compatible: the per-room
  /// geometry lookup is the real safety net, and refusing to draw the map
  /// because a version string is missing would be worse than showing it.
  bool supportsMapVersion(String? serverMapVersion) {
    if (serverMapVersion == null || serverMapVersion.isEmpty) return true;
    return serverMapVersion == mapVersion;
  }

  static MapCatalog? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;

    final List<MapRoomGeometry> rooms = asList(
      map['rooms'],
    ).map(MapRoomGeometry.fromJson).whereType<MapRoomGeometry>().toList();
    if (rooms.isEmpty) return null;

    final List<MapFloor> floors = asList(
      map['floors'],
    ).map(MapFloor.fromJson).whereType<MapFloor>().toList();
    if (floors.isEmpty) return null;

    return MapCatalog(
      schemaVersion: asInt(map['schemaVersion']) ?? supportedSchemaVersion,
      mapVersion: asString(map['mapVersion']) ?? '',
      buildings:
          asList(
            map['buildings'],
          ).map(MapBuilding.fromJson).whereType<MapBuilding>().toList()..sort(
            (MapBuilding a, MapBuilding b) =>
                a.sortOrder.compareTo(b.sortOrder),
          ),
      floors: floors
        ..sort((MapFloor a, MapFloor b) => a.sortOrder.compareTo(b.sortOrder)),
      rooms: rooms,
    );
  }
}

Rect? _rectFromJson(Object? json) {
  final Map<String, dynamic>? map = asJsonMap(json);
  if (map == null) return null;
  final double? minX = asDouble(map['minX']);
  final double? minY = asDouble(map['minY']);
  final double? width = asDouble(map['width']);
  final double? height = asDouble(map['height']);
  if (minX == null || minY == null || width == null || height == null) {
    return null;
  }
  if (width <= 0 || height <= 0) return null;
  return Rect.fromLTWH(minX, minY, width, height);
}

Rect? _boundsFromJson(Object? json) {
  final Map<String, dynamic>? map = asJsonMap(json);
  if (map == null) return null;
  final double? x = asDouble(map['x']);
  final double? y = asDouble(map['y']);
  final double? width = asDouble(map['width']);
  final double? height = asDouble(map['height']);
  if (x == null || y == null || width == null || height == null) return null;
  if (width <= 0 || height <= 0) return null;
  return Rect.fromLTWH(x, y, width, height);
}

Offset? _offsetFromJson(Object? json) {
  final Map<String, dynamic>? map = asJsonMap(json);
  if (map == null) return null;
  final double? x = asDouble(map['x']);
  final double? y = asDouble(map['y']);
  if (x == null || y == null) return null;
  return Offset(x, y);
}
