// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/site/campus_site.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/loaded.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../contacts/data/contact_search_models.dart';
import '../data/map_asset_loader.dart';
import '../data/rooms_repository.dart';
import '../domain/map_catalog.dart';
import '../domain/room.dart';
import '../domain/room_mention.dart';
import 'room_search.dart';

/// The room catalogue from the Campus API, cached for offline use.
final FutureProvider<Loaded<List<Room>>> roomsProvider =
    FutureProvider<Loaded<List<Room>>>((Ref ref) async {
      final String locale = ref.watch(localeCodeProvider);
      return ref.watch(roomsRepositoryProvider).fetchRooms(locale: locale);
    });

/// The one place that turns a room *mentioned somewhere* into a room on the
/// map — see [RoomResolver] for why it refuses everything it is not sure about.
///
/// Empty until the catalogue is there, so a screen that asks early gets "no
/// link" rather than an exception or a wrong one.
final Provider<RoomResolver> roomResolverProvider = Provider<RoomResolver>((
  Ref ref,
) {
  final List<Room>? rooms = ref.watch(roomsProvider).value?.value;
  return rooms == null
      ? const RoomResolver.empty()
      : RoomResolver.fromRooms(rooms);
});

/// Which rooms the public contact points and their people occupy.
///
/// Derived from the contact search index the contacts feature already loads, so
/// looking up "who sits in which room" costs no extra request and no second
/// matching rule. Deliberately never throws: the room search is only *widened*
/// by this, and a contact index that failed to load must not take the plain
/// room search down with it.
final Provider<ContactRoomIndex> contactRoomIndexProvider =
    Provider<ContactRoomIndex>((Ref ref) {
      final List<ContactSearchArea>? areas = ref
          .watch(contactSearchIndexProvider)
          .value
          ?.value;
      return areas == null
          ? const ContactRoomIndex.empty()
          : ContactRoomIndex.fromAreas(areas);
    });

/// Overridable so tests can supply a bundle without touching the asset system.
final Provider<MapAssetLoader> mapAssetLoaderProvider =
    Provider<MapAssetLoader>((Ref ref) => const MapAssetLoader());

/// The bundled geometry. Local, locale independent and read exactly once.
///
/// Retrying is switched off on purpose. This is a file inside the app bundle:
/// it is either there or it is not, and a second read a moment later cannot
/// change that. Left on the default, a failed load turns into an endless
/// back-off loop behind every screen that asks whether a room is on the map —
/// which is now the agenda as well as the contacts.
final FutureProvider<MapCatalog> mapCatalogProvider =
    FutureProvider<MapCatalog>(
      (Ref ref) => ref.watch(mapAssetLoaderProvider).load(),
      retry: (int retryCount, Object error) => null,
    );

/// The room the map should focus, set by search or by a contact deep link.
final NotifierProvider<SelectedRoomController, String?> selectedRoomProvider =
    NotifierProvider<SelectedRoomController, String?>(
      SelectedRoomController.new,
    );

class SelectedRoomController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Selects a room and brings the map to it.
  ///
  /// Search, the contact deep link and the room list all end up here, so
  /// "the map follows the room" is stated once instead of at every call site.
  /// The geometry may be missing — an app older than the catalogue that served
  /// the room — and that is a normal state: the selection still happens, the
  /// detail sheet explains it, and the view simply stays where it was.
  void select(String roomKey) {
    state = roomKey;
    final MapRoomGeometry? geometry = ref
        .read(mapCatalogProvider)
        .value
        ?.geometryFor(roomKey);
    if (geometry == null) return;
    // Building first: switching it picks that building's first floor, which the
    // floor below then corrects to the room's actual one.
    ref.read(visibleBuildingProvider.notifier).show(geometry.buildingKey);
    ref.read(visibleFloorProvider.notifier).show(geometry.floorKey);
  }

  /// Back to the overview. Reachable from a clearly visible action.
  void clear() => state = null;
}

/// The building currently shown.
///
/// Split from [visibleFloorProvider] on purpose: a floor is only meaningful
/// inside its building, and keeping the two consistent is this controller's
/// job rather than something every screen has to remember.
final NotifierProvider<VisibleBuildingController, String?>
visibleBuildingProvider = NotifierProvider<VisibleBuildingController, String?>(
  VisibleBuildingController.new,
);

class VisibleBuildingController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Forgets the explicit building and floor, so the map falls back to what
  /// the shown site and the settings say.
  void reset() {
    state = null;
    ref.read(visibleFloorProvider.notifier).show(null);
  }

  /// Switches the building and leaves the rest of the map consistent with it.
  ///
  /// A floor of the previous building must not stay active, and neither must a
  /// room that is not in the new one — the map would otherwise show a plan that
  /// contradicts its own selection.
  void show(String buildingKey) {
    if (state == buildingKey) return;
    state = buildingKey;

    final MapCatalog? map = ref.read(mapCatalogProvider).value;
    final List<MapFloor> floors =
        map?.floorsOf(buildingKey) ?? const <MapFloor>[];
    ref
        .read(visibleFloorProvider.notifier)
        .show(floors.isEmpty ? null : floors.first.floorKey);

    final String? selected = ref.read(selectedRoomProvider);
    if (selected == null) return;
    // A building with no rooms at all is a normal state, so an unknown geometry
    // clears the selection just as a foreign one does.
    if (map?.geometryFor(selected)?.buildingKey != buildingKey) {
      ref.read(selectedRoomProvider.notifier).clear();
    }
  }
}

/// The campus site the reader picked on the map, or `null` while they have
/// not. Without a pick the map follows the preferred site of the settings.
final NotifierProvider<VisibleSiteController, CampusSite?> visibleSiteProvider =
    NotifierProvider<VisibleSiteController, CampusSite?>(
      VisibleSiteController.new,
    );

class VisibleSiteController extends Notifier<CampusSite?> {
  @override
  CampusSite? build() => null;

  /// Switches to [site] and drops what belonged to the previous one: the
  /// building, the floor and a selected room would otherwise keep the old
  /// site's plan on screen.
  void show(CampusSite site) {
    state = site;
    ref.read(selectedRoomProvider.notifier).clear();
    ref.read(visibleBuildingProvider.notifier).reset();
  }
}

/// The floor currently shown. Follows the selection but can be changed freely.
final NotifierProvider<VisibleFloorController, String?> visibleFloorProvider =
    NotifierProvider<VisibleFloorController, String?>(
      VisibleFloorController.new,
    );

class VisibleFloorController extends Notifier<String?> {
  @override
  String? build() => null;

  /// `null` means "no explicit choice" — the screen then falls back to the
  /// first floor of the visible building.
  void show(String? floorKey) => state = floorKey;
}
