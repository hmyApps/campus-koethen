// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/network/loaded.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/offline_notice.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../core/widgets/translation_fallback_notice.dart';
import '../../../l10n/l10n.dart';
import '../application/campus_map_providers.dart';
import '../application/room_search.dart';
import '../domain/map_catalog.dart';
import '../domain/room.dart';
import 'campus_map_search_controller.dart';
import 'floor_map_view.dart';
import 'room_labels.dart';

/// The campus map: zoomable schematic plans with room search.
///
/// The plan is FULL-BLEED and everything else floats above it, the way a map
/// application behaves — the map is the content, not a thumbnail wedged between
/// form fields. Search, results and room details appear when they are needed
/// and get out of the way when they are not.
///
/// Room names and editorial texts come from the Campus API and are cached for
/// offline use; the geometry is a bundled, generated asset. Selecting a room —
/// by search or through a contact deep link — opens the matching floor and
/// highlights it.
class CampusMapScreen extends ConsumerStatefulWidget {
  const CampusMapScreen({this.initialRoomKey, super.key});

  /// Set by the in-app deep link from a contact.
  final String? initialRoomKey;

  @override
  ConsumerState<CampusMapScreen> createState() => _CampusMapScreenState();
}

/// Heights of the floating panels.
///
/// The map lies behind them, so these values also decide where a selected room
/// is centred — see [FloorMapView.visiblePadding].
const double kSearchBarHeight = 56;
const double kDetailSheetHeight = 236;

class _CampusMapScreenState extends ConsumerState<CampusMapScreen> {
  late final CampusMapSearchController _searchState;
  final GlobalKey<FloorMapViewState> _mapKey = GlobalKey<FloorMapViewState>();

  @override
  void initState() {
    super.initState();
    _searchState = CampusMapSearchController()..addListener(_onSearchChanged);
    final String? initial = widget.initialRoomKey;
    if (initial != null && initial.isNotEmpty) {
      // Providers must not be written during initState.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(selectedRoomProvider.notifier).select(initial);
      });
    }
  }

  @override
  void dispose() {
    _searchState
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _select(Room room) {
    ref.read(selectedRoomProvider.notifier).select(room.roomKey);
    ref.read(visibleFloorProvider.notifier).show(room.floorKey);
    // Picking a result closes the search, the way a map app hands the screen
    // back to the map once you have chosen a destination.
    _searchState.clearAfterSelection();
  }

  void _clearSelection() {
    ref.read(selectedRoomProvider.notifier).clear();
    _mapKey.currentState?.resetView();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Loaded<List<Room>>> rooms = ref.watch(roomsProvider);

    return Scaffold(
      body: switch (rooms) {
        AsyncLoading<Loaded<List<Room>>>() when !rooms.hasValue =>
          const LoadingView(),
        AsyncError<Loaded<List<Room>>>(:final Object error) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ErrorView(
            failure: error,
            onRetry: () => ref.invalidate(roomsProvider),
          ),
        ),
        _ => _MapSurface(
          loaded: rooms.requireValue,
          query: _searchState.query,
          search: _searchState.textController,
          searchFocus: _searchState.focusNode,
          mapKey: _mapKey,
          onQueryChanged: _searchState.updateQuery,
          onSelect: _select,
          onClearSelection: _clearSelection,
        ),
      },
    );
  }
}

class _MapSurface extends ConsumerWidget {
  const _MapSurface({
    required this.loaded,
    required this.query,
    required this.search,
    required this.searchFocus,
    required this.mapKey,
    required this.onQueryChanged,
    required this.onSelect,
    required this.onClearSelection,
  });

  final Loaded<List<Room>> loaded;
  final String query;
  final TextEditingController search;
  final FocusNode searchFocus;
  final GlobalKey<FloorMapViewState> mapKey;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Room> onSelect;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Room> allRooms = loaded.value;
    final String? selectedKey = ref.watch(selectedRoomProvider);
    final String? explicitBuilding = ref.watch(visibleBuildingProvider);
    final String? explicitFloor = ref.watch(visibleFloorProvider);
    final MapCatalog? map = ref.watch(mapCatalogProvider).value;

    final Room? selectedRoom = roomWithKey(allRooms, selectedKey);
    final List<RoomSearchHit> results = query.isEmpty
        ? const <RoomSearchHit>[]
        : searchRoomHits(
            allRooms,
            query,
            contacts: ref.watch(contactRoomIndexProvider),
          );

    final bool versionMismatch =
        map != null &&
        allRooms.isNotEmpty &&
        !map.supportsMapVersion(allRooms.first.mapVersion);

    // Derived rather than trusted. The controllers keep building and floor
    // consistent when they are written, but the map must also survive a state
    // that never was: a floor from another building would otherwise draw a plan
    // that contradicts the building shown above it.
    final String? buildingKey = _visibleBuildingKey(
      map: map,
      explicitBuilding: explicitBuilding,
      explicitFloor: explicitFloor,
      selectedRoom: selectedRoom,
      rooms: allRooms,
      defaultBuildingKey: ref.watch(
        settingsProvider.select((AppSettings s) => s.defaultBuildingKey),
      ),
    );
    final String? floorKey = _visibleFloorKey(
      map: map,
      buildingKey: buildingKey,
      explicitFloor: explicitFloor,
      selectedRoom: selectedRoom,
      rooms: allRooms,
    );
    final MapFloor? floor = floorKey == null ? null : map?.floor(floorKey);
    final MapRoomGeometry? geometry = selectedKey == null
        ? null
        : map?.geometryFor(selectedKey);

    final bool mapUsable = floor != null && !versionMismatch;
    final EdgeInsets safe = MediaQuery.paddingOf(context);

    // What the overlays cover, so a selected room is centred in the part of the
    // plan that is actually visible rather than behind a panel.
    final EdgeInsets covered = EdgeInsets.only(
      top: safe.top + kSearchBarHeight + AppSpacing.xl,
      // Nothing is drawn at the bottom unless a room is selected, so no space
      // is reserved for a bar that no longer exists.
      bottom: safe.bottom + (selectedRoom != null ? kDetailSheetHeight : 0),
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: mapUsable
              ? FloorMapView(
                  key: mapKey,
                  floor: floor,
                  // Only this floor's rooms, so a room one storey up can never
                  // answer a tap.
                  rooms: map == null
                      ? const <MapRoomGeometry>[]
                      : map.roomsOnFloor(floor.floorKey),
                  selected: geometry?.floorKey == floor.floorKey
                      ? geometry
                      : null,
                  onRoomTap: (String roomKey) {
                    // Exactly the flow a search result takes. A geometry the
                    // API knows nothing about is not selectable: there would be
                    // no name and no details to show.
                    final Room? room = roomWithKey(allRooms, roomKey);
                    if (room != null) onSelect(room);
                  },
                  visiblePadding: covered,
                )
              : _MapUnavailable(versionMismatch: versionMismatch),
        ),

        _TopOverlay(
          loaded: loaded,
          query: query,
          search: search,
          searchFocus: searchFocus,
          results: results,
          onSelect: onSelect,
          onQueryChanged: onQueryChanged,
        ),

        // Hidden while searching so the results overlay keeps the screen.
        if (mapUsable && map != null && buildingKey != null && query.isEmpty)
          _MapControls(
            map: map,
            buildingKey: buildingKey,
            floorKey: floor.floorKey,
            top: covered.top,
          ),

        if (mapUsable && selectedRoom == null && query.isEmpty)
          _ResetButton(
            bottom: safe.bottom + AppSpacing.lg,
            onPressed: () => mapKey.currentState?.resetView(),
          ),

        if (selectedRoom != null)
          _RoomDetailSheet(
            room: selectedRoom,
            onMap: geometry != null,
            onClose: onClearSelection,
          ),
      ],
    );
  }

  /// Which building the map is showing.
  ///
  /// An explicit choice wins; otherwise the selected room decides, so a deep
  /// link lands on the right building even before anyone has touched the
  /// picker — and even while the bundled catalogue is still loading.
  static String? _visibleBuildingKey({
    required MapCatalog? map,
    required String? explicitBuilding,
    required String? explicitFloor,
    required Room? selectedRoom,
    required List<Room> rooms,
    required String? defaultBuildingKey,
  }) {
    if (map == null) return null;
    if (map.building(explicitBuilding) != null) return explicitBuilding;
    final String? fromFloor = map.buildingOfFloor(explicitFloor);
    if (fromFloor != null) return fromFloor;
    final String? fromRoom =
        map.geometryFor(selectedRoom?.roomKey ?? '')?.buildingKey ??
        map.buildingOfFloor(selectedRoom?.floorKey);
    if (fromRoom != null) return fromRoom;
    // The user's chosen building, before falling back to the first one in the
    // catalogue. Without this the setting would be stored, offered in the
    // onboarding and the settings — and never do anything.
    if (map.building(defaultBuildingKey) != null) return defaultBuildingKey;
    return map.buildings.isNotEmpty
        ? map.buildings.first.buildingKey
        : map.buildingOfFloor(rooms.isEmpty ? null : rooms.first.floorKey);
  }

  /// Which floor of that building the map is showing.
  ///
  /// Anything that does not belong to [buildingKey] is ignored rather than
  /// drawn: the picker above the map states a building, and the plan below it
  /// has to agree.
  static String? _visibleFloorKey({
    required MapCatalog? map,
    required String? buildingKey,
    required String? explicitFloor,
    required Room? selectedRoom,
    required List<Room> rooms,
  }) {
    if (map == null || buildingKey == null) {
      return explicitFloor ?? selectedRoom?.floorKey;
    }
    final List<MapFloor> floors = map.floorsOf(buildingKey);
    bool belongs(String? key) =>
        key != null && floors.any((MapFloor f) => f.floorKey == key);

    if (belongs(explicitFloor)) return explicitFloor;
    if (belongs(selectedRoom?.floorKey)) return selectedRoom!.floorKey;
    return floors.isEmpty ? null : floors.first.floorKey;
  }
}

/// Shown instead of the plan when it cannot be drawn.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.versionMismatch});

  final bool versionMismatch;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: StatusBanner(
            title: l10n.campusMapTitle,
            message: versionMismatch
                ? l10n.campusMapVersionMismatch
                : l10n.campusMapUnavailable,
            tone: StatusTone.warning,
            icon: AppIcons.map_outlined,
          ),
        ),
      ),
    );
  }
}

/// Floating search bar and — while typing — the result list.
class _TopOverlay extends StatelessWidget {
  const _TopOverlay({
    required this.loaded,
    required this.query,
    required this.search,
    required this.searchFocus,
    required this.results,
    required this.onSelect,
    required this.onQueryChanged,
  });

  final Loaded<List<Room>> loaded;
  final String query;
  final TextEditingController search;
  final FocusNode searchFocus;
  final List<RoomSearchHit> results;
  final ValueChanged<Room> onSelect;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SearchBar(
              query: query,
              controller: search,
              focusNode: searchFocus,
              onQueryChanged: onQueryChanged,
            ),
            // Without the old bottom bar this is the only place left to say
            // that the catalogue has no rooms at all — a plan the user cannot
            // search is otherwise silent about why.
            if (loaded.value.isEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      l10n.campusMapEmpty,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ],
            if (loaded.fromCache) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              OfflineNotice(cachedAt: loaded.cachedAt),
            ],
            if (loaded.meta.translationFallback) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              const TranslationFallbackNotice(),
            ],
            if (query.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: _ResultsOverlay(
                  results: results,
                  onSelect: onSelect,
                  emptyTitle: l10n.campusMapNoResults,
                  emptyMessage: l10n.campusMapNoResultsHint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.query,
    required this.controller,
    required this.focusNode,
    required this.onQueryChanged,
  });

  final String query;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final MaterialLocalizations material = MaterialLocalizations.of(context);

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: kSearchBarHeight,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(AppIcons.arrow_back),
              tooltip: material.backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  // The bar carries no visible label, so the hint doubles as
                  // the accessible name of the field.
                  hintText: l10n.campusMapSearchLabel,
                ),
              ),
            ),
            if (query.isNotEmpty)
              IconButton(
                icon: const Icon(AppIcons.clear),
                tooltip: l10n.campusMapSearchClear,
                onPressed: () {
                  controller.clear();
                  onQueryChanged('');
                },
              )
            else
              const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// The search results, floating under the search bar.
class _ResultsOverlay extends StatelessWidget {
  const _ResultsOverlay({
    required this.results,
    required this.onSelect,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<RoomSearchHit> results;
  final ValueChanged<Room> onSelect;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      clipBehavior: Clip.antiAlias,
      child: results.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(emptyTitle, style: text.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(emptyMessage, style: text.bodySmall),
                ],
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: results.length,
              itemBuilder: (BuildContext context, int index) => _RoomTile(
                hit: results[index],
                onTap: () => onSelect(results[index].room),
              ),
            ),
    );
  }
}

class _RoomDetailSheet extends StatelessWidget {
  const _RoomDetailSheet({
    required this.room,
    required this.onMap,
    required this.onClose,
  });

  final Room room;
  final bool onMap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          border: Border(
            top: BorderSide(
              color: colors.outline.withValues(alpha: 0.36),
              width: AppSizes.hairline,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // The selection is carried by an icon as well, never by
                      // colour alone.
                      Icon(AppIcons.place, color: colors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Semantics(
                          label: l10n.campusMapSemanticSelectedRoom(
                            room.roomNumber,
                          ),
                          child: Text(
                            l10n.campusMapSelectedRoom(room.primaryLabel),
                            style: text.titleMedium?.copyWith(
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(AppIcons.close),
                        tooltip: l10n.campusMapShowWholeFloor,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    roomLocationSummary(
                      context,
                      buildingName: room.buildingName,
                      buildingNumber: room.buildingNumber,
                      floorName: room.floorName,
                      roomNumber: room.roomNumber,
                    ),
                    style: text.bodyMedium?.copyWith(color: colors.onSurface),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${l10n.campusMapRoomTypeLabel}: '
                    '${roomTypeLabel(context, room.roomType)}',
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (room.description != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      room.description!,
                      style: text.bodyMedium?.copyWith(color: colors.onSurface),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (!onMap) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.campusMapRoomNotOnMap,
                      style: text.bodySmall?.copyWith(color: colors.error),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: onClose,
                      icon: const Icon(AppIcons.fullscreen_exit),
                      label: Text(l10n.campusMapShowWholeFloor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Building and floor pickers, floating on the map as a compact 1-row control.
///
/// Combines building and floor choice into a single horizontal pill (48 dp height),
/// separated by a hairline divider. This saves 56 dp vertical space compared to
/// stacked chips, maximizing the visible map area.
///
/// Both are driven entirely by the bundled catalogue. There is deliberately no
/// key-to-label mapping in this file: another building or floor is a catalogue
/// change, never a Flutter change.
class _MapControls extends ConsumerWidget {
  const _MapControls({
    required this.map,
    required this.buildingKey,
    required this.floorKey,
    required this.top,
  });

  final MapCatalog map;
  final String buildingKey;
  final String floorKey;
  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final List<MapFloor> floors = map.floorsOf(buildingKey);
    final MapBuilding? building = map.building(buildingKey);
    final MapFloor? current = floors.isEmpty
        ? null
        : floors.firstWhere(
            (MapFloor floor) => floor.floorKey == floorKey,
            orElse: () => floors.first,
          );

    final bool showBuilding = map.hasSeveralBuildings && building != null;
    final bool showFloor = current != null;

    if (!showBuilding && !showFloor) return const SizedBox.shrink();

    final double labelMax = _maxLabelWidthFor(context);
    final ColorScheme colors = Theme.of(context).colorScheme;

    // Left-aligned: the controls describe what is drawn below them, and a
    // left-to-right reader looks there first. Both edges are positioned even
    // though the bar hugs its content: that is what bounds its width, and an
    // unbounded row would run off the screen instead of ellipsising.
    return PositionedDirectional(
      start: AppSpacing.lg,
      end: AppSpacing.lg,
      top: top,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Material(
          elevation: 3,
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: AppSizes.minTouchTarget,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Only the building name gives way when the screen is narrow.
                // The floor is the value that changes constantly and has to
                // stay readable; a building is one of very few and stays
                // recognisable from its first characters.
                if (showBuilding)
                  Flexible(
                    child: _MapSegment<String>(
                      icon: AppIcons.apartment_outlined,
                      label: building.name.resolve(locale),
                      tooltip: l10n.campusMapBuildingLabel,
                      semanticLabel: l10n.campusMapBuildingSelectorSemantic(
                        building.name.resolve(locale),
                      ),
                      value: building.buildingKey,
                      options: <({String value, String label})>[
                        for (final MapBuilding candidate in map.buildings)
                          (
                            value: candidate.buildingKey,
                            label: candidate.name.resolve(locale),
                          ),
                      ],
                      onSelected: (String key) =>
                          ref.read(visibleBuildingProvider.notifier).show(key),
                      maxLabelWidth: labelMax,
                      yieldsSpace: true,
                    ),
                  ),

                if (showBuilding && showFloor)
                  Center(
                    child: Container(
                      width: AppSizes.hairline,
                      height: 24,
                      color: colors.outline.withValues(alpha: 0.36),
                    ),
                  ),

                if (showFloor)
                  _MapSegment<String>(
                    icon: AppIcons.layers_outlined,
                    label: current.name.resolve(locale),
                    tooltip: l10n.campusMapFloorLabel,
                    semanticLabel: floors.length > 1
                        ? l10n.campusMapFloorSelectorSemantic(
                            current.name.resolve(locale),
                          )
                        : l10n.campusMapSingleFloorSemantic(
                            current.name.resolve(locale),
                          ),
                    value: current.floorKey,
                    options: <({String value, String label})>[
                      for (final MapFloor floor in floors)
                        (
                          value: floor.floorKey,
                          label: floor.name.resolve(locale),
                        ),
                    ],
                    onSelected: (String key) =>
                        ref.read(visibleFloorProvider.notifier).show(key),
                    maxLabelWidth: labelMax,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The widest a single label may get before it is cut.
  ///
  /// A cap, not a width: the row shrinks below this whenever the screen is
  /// narrower, and the value only stops a long building name from running
  /// across a tablet. The screen always wins over the preferred size.
  static double _maxLabelWidthFor(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double preferred = screenWidth >= _tabletWidth ? 240 : 140;
    final double available = screenWidth - 2 * AppSpacing.lg;
    return math.min(preferred, available);
  }

  /// Where a screen stops being a phone. The usual Material breakpoint.
  static const double _tabletWidth = 600;
}

/// One segment in the compact floating control that either opens a popup menu
/// or, with a single option, simply states the current value.
class _MapSegment<T> extends StatefulWidget {
  const _MapSegment({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.semanticLabel,
    required this.value,
    required this.options,
    required this.onSelected,
    required this.maxLabelWidth,
    this.yieldsSpace = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final String semanticLabel;
  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T> onSelected;
  final double maxLabelWidth;

  /// Whether this segment is the one that gives way when the bar is too wide
  /// for the screen. Exactly one segment may say yes, and only that one is laid
  /// out against a bounded width — the other keeps the size it asks for.
  final bool yieldsSpace;

  @override
  State<_MapSegment<T>> createState() => _MapSegmentState<T>();
}

class _MapSegmentState<T> extends State<_MapSegment<T>> {
  /// Whether the keyboard is on this segment.
  ///
  /// Read from a wrapper node rather than owned here: the focus itself belongs
  /// to the menu button's own `InkWell`, and taking it away from there would
  /// break activation by keyboard to gain a border.
  bool _focused = false;

  /// Below this a label is an abbreviation, not a word.
  ///
  /// Two or three glyphs and an ellipsis say less than the icon beside them
  /// already does, so at that point the label goes and the icon speaks alone —
  /// the screen reader still announces the full name either way.
  static const double _minLabelWidth = 56;

  Widget _label(BuildContext context) => Text(
    widget.label,
    style: Theme.of(context).textTheme.labelLarge,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  Widget _buildLabel(BuildContext context, BoxConstraints constraints) {
    if (constraints.maxWidth < _minLabelWidth) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(
            widget.maxLabelWidth,
            constraints.maxWidth - AppSpacing.sm,
          ),
        ),
        child: _label(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool interactive = widget.options.length > 1;

    final Widget body = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppSizes.minTouchTarget,
        minWidth: AppSizes.minTouchTarget,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(widget.icon, size: AppSizes.iconSmall),
            if (widget.yieldsSpace)
              Flexible(child: LayoutBuilder(builder: _buildLabel))
            else ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxLabelWidth),
                child: _label(context),
              ),
            ],
            // The affordance is a shape, not a colour: no chevron means there
            // is nothing to open.
            if (interactive) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              const Icon(AppIcons.arrow_drop_down, size: AppSizes.iconSmall),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      label: widget.semanticLabel,
      button: interactive,
      readOnly: !interactive,
      excludeSemantics: true,
      child: FocusRing(
        focused: _focused,
        child: interactive
            ? Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (bool value) => setState(() => _focused = value),
                child: PopupMenuButton<T>(
                  tooltip: widget.tooltip,
                  initialValue: widget.value,
                  onSelected: widget.onSelected,
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<T>>[
                    for (final ({T value, String label}) option
                        in widget.options)
                      PopupMenuItem<T>(
                        value: option.value,
                        child: Text(option.label),
                      ),
                  ],
                  child: body,
                ),
              )
            : body,
      ),
    );
  }
}

/// The keyboard's position, drawn as a shape rather than a tint.
///
/// An ink highlight alone states focus in colour only, which the project rules
/// do not accept — and on a surface-coloured pill it is barely there at all.
/// The weight and colour are the ones a focused text field already uses
/// (`AppTheme.focusedBorder`), so the keyboard looks the same wherever it is.
class FocusRing extends StatelessWidget {
  const FocusRing({required this.focused, required this.child, super.key});

  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!focused) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: AppSizes.rule,
        ),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: child,
    );
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.bottom, required this.onPressed});

  final double bottom;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      end: AppSpacing.lg,
      bottom: bottom,
      child: FloatingActionButton.small(
        heroTag: 'campus-map-reset',
        tooltip: context.l10n.campusMapResetZoom,
        onPressed: onPressed,
        child: const Icon(AppIcons.zoom_out_map),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.hit, required this.onTap});

  final RoomSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final Room room = hit.room;
    final String title = room.buildingNumber.isEmpty
        ? '${room.roomNumber} · ${room.buildingName}'
        : l10n.campusMapRoomResultTitle(
            room.roomNumber,
            room.buildingNumber,
            room.buildingName,
          );
    final String details = <String>[
      if (room.displayName != null) room.displayName!,
      roomTypeLabel(context, room.roomType),
      room.floorName,
    ].join(' · ');

    // A room that matched through a person is otherwise inexplicable: the
    // typed name appears nowhere on the tile. The icon carries the difference
    // as well, so it does not rest on the extra line alone.
    final String? via = hit.isContactMatch ? hit.context : null;

    return ListTile(
      leading: Icon(
        via == null
            ? AppIcons.meeting_room_outlined
            : AppIcons.person_search_outlined,
      ),
      title: Text(title),
      subtitle: Text(
        via == null ? details : '$details\n${l10n.campusMapResultVia(via)}',
      ),
      isThreeLine: via != null,
      trailing: const Icon(AppIcons.chevron_right),
      minTileHeight: AppSizes.minTouchTarget,
      onTap: onTap,
    );
  }
}
