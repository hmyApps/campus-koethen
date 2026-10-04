// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:math' as math;

import 'package:campus_koethen/app/app_router.dart';
import 'package:campus_koethen/app/app_routes.dart';
import 'package:campus_koethen/core/cache/cache_providers.dart';
import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/api_client.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/theme/app_dimensions.dart';
import 'package:campus_koethen/core/theme/app_theme.dart';
import 'package:campus_koethen/features/campusmap/application/campus_map_providers.dart';
import 'package:campus_koethen/features/campusmap/domain/map_catalog.dart';
import 'package:campus_koethen/features/campusmap/data/map_asset_loader.dart';
import 'package:campus_koethen/features/campusmap/presentation/campus_map_screen.dart';
import 'package:campus_koethen/features/campusmap/presentation/floor_map_view.dart';
import 'package:campus_koethen/features/campusmap/presentation/room_link.dart';
import 'package:campus_koethen/features/contacts/data/contact_models.dart';
import 'package:campus_koethen/features/more/presentation/more_screen.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/fake_http_adapter.dart';
import '../../support/pump_app.dart';

/// Ratke rooms shaped exactly like `/v1/rooms`.
Map<String, dynamic> roomJson(
  String roomNumber, {
  String? displayName,
  String? mapVersion,
  String roomType = 'office',
  int sortOrder = 0,
  int level = 1,
}) => <String, dynamic>{
  'roomKey': level == 0
      ? 'ratke-gebaeude-ground-floor-$roomNumber'
      : 'ratke-gebaeude-first-floor-$roomNumber',
  'roomNumber': roomNumber,
  'buildingKey': 'ratke-gebaeude',
  'buildingNumber': '23',
  'buildingName': 'Ratke-Gebäude',
  'floorKey': level == 0
      ? 'ratke-gebaeude-ground-floor'
      : 'ratke-gebaeude-first-floor',
  'floorName': level == 0 ? 'Erdgeschoss' : '1. Obergeschoss',
  'roomType': roomType,
  'displayName': displayName,
  'description': null,
  // Taken from the bundled catalogue so a regenerated map cannot silently
  // turn every map assertion into a version-mismatch banner.
  'mapVersion': mapVersion ?? testCatalog.mapVersion,
  'sortOrder': sortOrder,
};

List<Map<String, dynamic>> get roomsFixture => <Map<String, dynamic>>[
  // The lower storey, which the map opens on…
  roomJson(
    '101',
    displayName: 'Raum 101',
    roomType: 'room',
    sortOrder: 10,
    level: 0,
  ),
  roomJson('102', sortOrder: 20, level: 0),
  // …and the upper one, reachable through the floor picker or a deep link.
  roomJson('216', displayName: 'Hörsaal', roomType: 'lecture', sortOrder: 110),
  roomJson('217', sortOrder: 120),
  roomJson('210', sortOrder: 200),
];

/// The real generated catalogue, loaded once.
///
/// `pumpAndSettle` advances a fake clock and does NOT wait for real asset I/O,
/// so leaving the load to the provider made these tests depend on timing. The
/// asset itself is still exercised end to end in map_catalog_test.dart.
late final MapCatalog testCatalog;

/// A test contact point whose staff sit in the rooms above.
///
/// Shaped like `/v1/contact-areas/search-index`, because the room search now
/// reads that index to answer "which room does this person sit in".
List<Map<String, dynamic>> get contactIndexFixture => <Map<String, dynamic>>[
  <String, dynamic>{
    'slug': 'ratke-pruefungsamt',
    'name': 'Beispiel-Prüfungsamt',
    'shortDescription': 'Beispielbereich',
    'descriptionText': 'Testinhalt für die Raumsuche.',
    'rooms': <Map<String, dynamic>>[],
    'persons': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Björn Beispielperson',
        'role': 'Beispielrolle',
        'rooms': <Map<String, dynamic>>[
          <String, dynamic>{
            'roomKey': 'ratke-gebaeude-first-floor-210',
            'roomNumber': '210',
            'buildingNumber': '23',
            'buildingName': 'Ratke-Gebäude',
            'floorName': '1. Obergeschoss',
          },
        ],
      },
    ],
  },
];

List<Override> mapOverrides(
  List<Map<String, dynamic>> rooms, {
  List<Map<String, dynamic>>? contacts,
}) => <Override>[
  apiClientProvider.overrideWithValue(_api(rooms, contacts)),
  mapCatalogProvider.overrideWith((Ref ref) => testCatalog),
];

ApiClient _api(
  List<Map<String, dynamic>> rooms,
  List<Map<String, dynamic>>? contacts,
) => fakeApiClient(
  FakeHttpAdapter((RequestOptions options) {
    if (options.path.contains('/contact-areas/search-index')) {
      // Answered even when a test passes none: an index that errors would
      // leave Riverpod retrying in the background of every map test.
      return FakeHttpResponse(
        envelope(contacts ?? const <Map<String, dynamic>>[]),
      );
    }
    if (options.path.contains('/rooms')) {
      // The adapter encodes the body itself — pass the object, not a string.
      return FakeHttpResponse(envelope(rooms));
    }
    return FakeHttpResponse(envelope(<Object>[]), statusCode: 404);
  }),
);

/// Gives the test a tall surface.
///
/// The screen stacks a notice, the search field, a 320 px map and the result
/// list. On the default 800 px test viewport the list falls below the fold,
/// and `ListView` does not build off-screen children — so assertions would
/// fail for a layout reason rather than a behavioural one.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Gives the test a surface of exactly [size].
///
/// The tall default surface is what most tests want, but anything about the
/// map's own geometry — how much of the plan is on screen, whether the control
/// bar fits — only means something at a width a real device actually has.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> pumpMap(
  WidgetTester tester, {
  List<Map<String, dynamic>>? rooms,
  List<Map<String, dynamic>>? contacts,
  String? initialRoomKey,
  Locale locale = AppLocales.german,
  Size? size,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  if (size == null) {
    useTallSurface(tester);
  } else {
    useSurface(tester, size);
  }
  final InMemoryKeyValueStore store = InMemoryKeyValueStore();
  await pumpScreen(
    tester,
    CampusMapScreen(initialRoomKey: initialRoomKey),
    locale: locale,
    textScaler: textScaler,
    keyValueStore: store,
    overrides: mapOverrides(rooms ?? roomsFixture, contacts: contacts),
  );
  await tester.pumpAndSettle();
}

/// Where the floor plan actually sits on screen, in viewport coordinates.
///
/// Selecting a room may move the plan, and "the whole floor stays visible" is
/// a statement about this rectangle — not about the zoom factor, which is why
/// asserting `scale == 1.0` alone would not have caught anything.
Rect planOnScreen(WidgetTester tester) {
  final FloorMapViewState state = tester.state<FloorMapViewState>(
    find.byType(FloorMapView),
  );
  final Rect box = tester.getRect(find.byType(FloorMapView));
  final Rect viewBox = state.widget.floor.viewBox;
  final Size planSize = Size(
    viewBox.width * state.planScale,
    viewBox.height * state.planScale,
  );
  // The plan sits inside a Center, so it is offset whenever it does not fill
  // the viewport — the same origin FloorMapView focuses against.
  final Offset origin = Offset(
    math.max(0, (box.width - planSize.width) / 2),
    math.max(0, (box.height - planSize.height) / 2),
  );
  return MatrixUtils.transformRect(state.currentTransform, origin & planSize);
}

/// The bar carrying the building and floor pickers.
Rect controlBarRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(PositionedDirectional).first,
        matching: find.byType(Row),
      )
      .first,
);

void main() {
  testWidgets('layout matrix keeps search and map actions on screen', (
    WidgetTester tester,
  ) async {
    for (final (Size size, TextScaler scaler) in <(Size, TextScaler)>[
      (const Size(320, 800), TextScaler.noScaling),
      (const Size(360, 800), const TextScaler.linear(1.3)),
      (const Size(800, 360), TextScaler.noScaling),
      (const Size(320, 1000), const TextScaler.linear(2)),
    ]) {
      await pumpMap(tester, size: size, textScaler: scaler);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Ansicht zurücksetzen'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size at $scaler');
    }
  });

  testWidgets('room search fallback opens the map without a room selection', (
    WidgetTester tester,
  ) async {
    Uri? openedUri;
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: RoomSearchButton()),
        ),
        GoRoute(
          path: AppRoutes.campusMap,
          builder: (BuildContext context, GoRouterState state) {
            openedUri = state.uri;
            return const Scaffold(body: Text('Map search opened'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: AppLocales.german,
        supportedLocales: AppLocales.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    );
    await tester.tap(find.text('Raum suchen'));
    await tester.pumpAndSettle();

    expect(find.text('Map search opened'), findsOneWidget);
    expect(openedUri?.path, AppRoutes.campusMap);
    expect(openedUri?.queryParameters, isEmpty);
  });

  group('map controls', _controlPositionTests);
  group('map viewport', _viewportTests);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    testCatalog = await const MapAssetLoader().load();
  });

  testWidgets('the More section opens the campus map', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const MoreScreen(),
      overrides: mapOverrides(roomsFixture),
    );
    await tester.pumpAndSettle();

    // The hub uses the module's full title; "Lageplan" alone is the short one.
    await tester.scrollUntilVisible(
      find.text('Lageplan & Räume'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Lageplan & Räume'), findsOneWidget);
    expect(
      find.text('Gebäudepläne mit interaktiver Raumsuche'),
      findsOneWidget,
    );
  });

  testWidgets('the route under More renders the map screen', (
    WidgetTester tester,
  ) async {
    useTallSurface(tester);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        contentCacheProvider.overrideWithValue(
          SafeContentCache(MemoryContentCache()),
        ),
        ...mapOverrides(roomsFixture),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: AppLocales.german,
          supportedLocales: AppLocales.supported,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: createAppRouter(initialLocation: AppRoutes.campusMap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CampusMapScreen), findsOneWidget);
  });

  testWidgets('does not overlay a schematic-plan badge', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);
    expect(find.text('Schematischer Plan'), findsNothing);
  });

  testWidgets('searching 216 selects and marks 216', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    await tester.enterText(find.byType(TextField), '216');
    await tester.pumpAndSettle();

    // Only the matching room is offered…
    expect(find.text('216 · Gebäude 23 · Ratke-Gebäude'), findsOneWidget);
    expect(find.textContaining('Hörsaal'), findsOneWidget);
    expect(find.text('217'), findsNothing);

    await tester.tap(find.text('216 · Gebäude 23 · Ratke-Gebäude'));
    await tester.pumpAndSettle();

    // …and the selection is stated in words, not by colour alone.
    expect(find.textContaining('Ausgewählt: Hörsaal'), findsOneWidget);
    expect(find.byIcon(AppIcons.place), findsWidgets);
  });

  testWidgets('216 and a spaced 216 lead to the same room', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    await tester.enterText(find.byType(TextField), ' 216 ');
    await tester.pumpAndSettle();
    final bool dotted = find
        .text('216 · Gebäude 23 · Ratke-Gebäude')
        .evaluate()
        .isNotEmpty;

    await tester.enterText(find.byType(TextField), '216');
    await tester.pumpAndSettle();
    final bool plain = find
        .text('216 · Gebäude 23 · Ratke-Gebäude')
        .evaluate()
        .isNotEmpty;

    expect(dotted, isTrue);
    expect(plain, isTrue);
  });

  testWidgets('a Ratke search result opens its building and floor', (
    WidgetTester tester,
  ) async {
    await pumpMap(
      tester,
      rooms: <Map<String, dynamic>>[
        roomJson(
          '216',
          level: 1,
          roomType: 'lecture',
          displayName: 'Hörsaal 216',
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), '216');
    await tester.pumpAndSettle();
    await tester.tap(find.text('216 · Gebäude 23 · Ratke-Gebäude'));
    await tester.pumpAndSettle();

    final FloorMapView view = tester.widget<FloorMapView>(
      find.byType(FloorMapView),
    );
    expect(view.floor.floorKey, 'ratke-gebaeude-first-floor');
    expect(view.selected?.roomKey, 'ratke-gebaeude-first-floor-216');
    expect(find.text('Ratke-Gebäude'), findsOneWidget);
    expect(find.textContaining('Ausgewählt: Hörsaal 216'), findsOneWidget);
  });

  testWidgets('room number and building can be searched together', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    for (final String query in <String>[
      'Ratke 216',
      '216 Ratke',
      '216 23',
      '23 216',
      '23 Ratke 216',
    ]) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();

      expect(
        find.text('216 · Gebäude 23 · Ratke-Gebäude'),
        findsOneWidget,
        reason: 'query "$query"',
      );
      expect(find.text('217 · Gebäude 23 · Ratke-Gebäude'), findsNothing);
    }
  });

  testWidgets('the bare number finds the room without its building letter', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    await tester.enterText(find.byType(TextField), '217');
    await tester.pumpAndSettle();

    expect(find.text('217'), findsWidgets);
    expect(find.text('Hörsaal'), findsNothing);
  });

  testWidgets('a person leads to their room, and says so', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, contacts: contactIndexFixture);

    await tester.enterText(find.byType(TextField), 'Beispielperson');
    await tester.pumpAndSettle();

    // The room is offered even though the typed name is nowhere in it — so the
    // row has to explain itself.
    expect(find.text('210 · Gebäude 23 · Ratke-Gebäude'), findsOneWidget);
    expect(
      find.textContaining('Gefunden über Björn Beispielperson'),
      findsOneWidget,
    );

    await tester.tap(find.text('210 · Gebäude 23 · Ratke-Gebäude'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ausgewählt: 210'), findsOneWidget);
  });

  testWidgets('the room search still works without a contact index', (
    WidgetTester tester,
  ) async {
    // What an offline start looks like: no index, so no person search — but
    // the plain room search is untouched.
    await pumpMap(tester);

    await tester.enterText(find.byType(TextField), 'Beispielperson');
    await tester.pumpAndSettle();
    expect(find.text('Kein Raum gefunden'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '217');
    await tester.pumpAndSettle();
    expect(find.text('217'), findsWidgets);
  });

  testWidgets('a deep link preselects the room', (WidgetTester tester) async {
    await pumpMap(tester, initialRoomKey: 'ratke-gebaeude-first-floor-210');
    expect(find.textContaining('Ausgewählt: 210'), findsOneWidget);
  });

  testWidgets('the selection can be cleared again', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, initialRoomKey: 'ratke-gebaeude-first-floor-210');
    expect(find.textContaining('Ausgewählt: 210'), findsOneWidget);

    await tester.tap(find.text('Gesamte Etage anzeigen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ausgewählt:'), findsNothing);
  });

  testWidgets('a room the bundled map does not know stays text only', (
    WidgetTester tester,
  ) async {
    await pumpMap(
      tester,
      rooms: <Map<String, dynamic>>[roomJson('xxx')],
      initialRoomKey: 'ratke-gebaeude-first-floor-xxx',
    );

    expect(find.textContaining('nicht enthalten'), findsOneWidget);
    // No crash, and the room is still readable.
    expect(find.textContaining('Ausgewählt:'), findsOneWidget);
  });

  testWidgets('a map version mismatch is explained instead of failing', (
    WidgetTester tester,
  ) async {
    await pumpMap(
      tester,
      rooms: <Map<String, dynamic>>[
        roomJson('216', mapVersion: 'from-the-future'),
      ],
    );

    expect(
      find.textContaining('passt nicht zur aktuellen Raumliste'),
      findsOneWidget,
    );
    // The plan is withheld, but the rooms stay reachable through the search.
    await tester.enterText(find.byType(TextField), '216');
    await tester.pumpAndSettle();
    expect(find.text('216'), findsWidgets);
  });

  testWidgets('an empty catalogue shows an empty state, not an error', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, rooms: <Map<String, dynamic>>[]);
    expect(find.textContaining('noch keine Räume'), findsOneWidget);
  });

  testWidgets('a query without matches explains itself', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('Kein Raum gefunden'), findsOneWidget);
  });

  testWidgets('renders English when the locale is en', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, locale: AppLocales.english);
    expect(find.text('Schematic plan'), findsNothing);
    expect(find.text('Search rooms'), findsOneWidget);
  });

  testWidgets('the map exposes a screen reader label', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);
    expect(
      find.bySemanticsLabel('Etagenplan, zoombar und verschiebbar'),
      findsOneWidget,
    );
  });

  testWidgets('room rows keep a large enough touch target', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    // The map is the resting state, so the rows live in the search results.
    await tester.enterText(find.byType(TextField), '2');
    await tester.pumpAndSettle();

    final Iterable<ListTile> tiles = tester.widgetList<ListTile>(
      find.byType(ListTile),
    );
    expect(tiles, isNotEmpty);
    for (final ListTile tile in tiles) {
      expect(tile.minTileHeight, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('no room count and no "show all" bar at the bottom', (
    WidgetTester tester,
  ) async {
    // The bar took a strip of the map to say something the map already shows.
    await pumpMap(tester);

    expect(find.text('3 Räume'), findsNothing);
    expect(find.text('Alle anzeigen'), findsNothing);
  });

  testWidgets('a room is selected through the search', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    await tester.enterText(find.byType(TextField), 'Hörsaal');
    await tester.pumpAndSettle();
    await tester.tap(find.text('216 · Gebäude 23 · Ratke-Gebäude'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ausgewählt: Hörsaal'), findsOneWidget);
  });

  group('tapping a room on the plan', () {
    /// Where a point of the PLAN currently sits on screen.
    Offset planPointOnScreen(WidgetTester tester, Offset planPoint) {
      final FloorMapViewState state = tester.state<FloorMapViewState>(
        find.byType(FloorMapView),
      );
      final FloorMapView view = tester.widget<FloorMapView>(
        find.byType(FloorMapView),
      );
      final Rect box = tester.getRect(find.byType(FloorMapView));
      final double scale = state.planScale;
      final Size planSize = Size(
        view.floor.viewBox.width * scale,
        view.floor.viewBox.height * scale,
      );
      // The plan is centred inside the view before the transform applies.
      final Offset inChild =
          Offset(
            (box.width - planSize.width) / 2,
            (box.height - planSize.height) / 2,
          ) +
          planPoint * scale;
      return box.topLeft +
          MatrixUtils.transformPoint(state.currentTransform, inChild);
    }

    testWidgets('selects it exactly as the search would', (
      WidgetTester tester,
    ) async {
      await pumpMap(tester);

      await tester.tapAt(
        _roomCentre(tester, 'ratke-gebaeude-ground-floor-101'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Ausgewählt: Raum 101'), findsOneWidget);
      expect(find.textContaining('Hörsaal'), findsNothing);
      expect(find.byIcon(AppIcons.place), findsWidgets);
    });

    testWidgets('a tap on empty floor changes nothing', (
      WidgetTester tester,
    ) async {
      await pumpMap(tester);

      // The far corner of the plan: no room is anywhere near it.
      await tester.tapAt(planPointOnScreen(tester, Offset.zero));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ausgewählt:'), findsNothing);
    });

    testWidgets('a room the API does not serve is not selectable', (
      WidgetTester tester,
    ) async {
      // The bundled map knows room 103; the fixture does not. Without a room
      // record there is no name and no detail to show, so the tap does
      // nothing rather than opening an empty sheet.
      await pumpMap(tester);

      await tester.tapAt(
        _roomCentre(tester, 'ratke-gebaeude-ground-floor-103'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Ausgewählt:'), findsNothing);
    });

    testWidgets('still hits the right room after the plan has moved', (
      WidgetTester tester,
    ) async {
      // Selecting zooms and pans; a second tap has to keep working.
      await pumpMap(tester);
      await tester.tapAt(
        _roomCentre(tester, 'ratke-gebaeude-ground-floor-101'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ausgewählt: Raum 101'), findsOneWidget);

      // Room 102 sits next door. Zoomed in, its centre may be off screen, so the
      // target is the part of it that is actually visible — which is exactly
      // the situation this has to survive.
      await tester.tapAt(
        _roomCentre(tester, 'ratke-gebaeude-ground-floor-102'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Ausgewählt: 102'), findsOneWidget);
    });
  });

  testWidgets('survives doubled text size without overflow', (
    WidgetTester tester,
  ) async {
    useTallSurface(tester);
    await pumpScreen(
      tester,
      const CampusMapScreen(),
      textScaler: const TextScaler.linear(2),
      overrides: mapOverrides(roomsFixture),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('building and floor selection', _selectionTests);

  group('contact room rows', () {
    const RoomReference known = RoomReference(
      roomKey: 'ratke-gebaeude-first-floor-216',
      roomNumber: '216',
      buildingNumber: '23',
      buildingName: 'Ratke-Gebäude',
      floorName: '1. Obergeschoss',
      displayName: 'Hörsaal',
    );

    testWidgets('an empty room list renders nothing at all', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(body: RoomLinkSection(rooms: <RoomReference>[])),
        overrides: mapOverrides(roomsFixture),
      );
      await tester.pumpAndSettle();

      expect(find.text('Räume'), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('a room row shows building, floor and number', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(body: RoomLinkSection(rooms: <RoomReference>[known])),
        overrides: mapOverrides(roomsFixture),
      );
      await tester.pumpAndSettle();

      expect(find.text('Räume'), findsOneWidget);
      expect(find.text('Hörsaal'), findsOneWidget);
      expect(
        find.text('216 · Gebäude 23 · Ratke-Gebäude, 1. Obergeschoss'),
        findsOneWidget,
      );
    });

    test('the deep link carries the roomKey as a query parameter', () {
      expect(
        AppRoutes.campusMapForRoom('ratke-gebaeude-first-floor-216'),
        '/more/campus-map?room=ratke-gebaeude-first-floor-216',
      );
    });

    testWidgets('tapping a room row opens the campus map on that room', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          contentCacheProvider.overrideWithValue(
            SafeContentCache(MemoryContentCache()),
          ),
          ...mapOverrides(roomsFixture),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: AppLocales.german,
            supportedLocales: AppLocales.supported,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: createAppRouter(initialLocation: AppRoutes.more),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reaching the map through the real route table, exactly as the contact
      // row does, rather than asserting on a string.
      await tester.tap(find.text('Lageplan & Räume'));
      await tester.pumpAndSettle();
      expect(find.byType(CampusMapScreen), findsOneWidget);
    });

    testWidgets('a room outside the bundled map is not tappable', (
      WidgetTester tester,
    ) async {
      const RoomReference unknown = RoomReference(
        roomKey: 'not-in-the-bundled-map',
        roomNumber: 'Z.999',
        buildingName: 'Irgendwo',
        floorName: 'Irgendwann',
      );

      await pumpScreen(
        tester,
        const Scaffold(body: RoomLinkSection(rooms: <RoomReference>[unknown])),
        overrides: mapOverrides(roomsFixture),
      );
      await tester.pumpAndSettle();

      final ListTile tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(
        tile.onTap,
        isNull,
        reason: 'a room without geometry must not navigate',
      );
      expect(find.textContaining('nicht enthalten'), findsOneWidget);
    });
  });
}

/// Building and floor selection.
///
/// Every real floor plan shares one bundled catalogue, so switching between
/// buildings has to keep the plan, the floor and any room selection describing
/// the same place.
void _selectionTests() {
  String buildingName(String key, {String locale = 'de'}) =>
      testCatalog.building(key)!.name.resolve(locale);
  String floorName(String key, {String locale = 'de'}) =>
      testCatalog.floor(key)!.name.resolve(locale);

  const String ratke = 'ratke-gebaeude';
  const String ratkeGroundFloor = 'ratke-gebaeude-ground-floor';
  const String ratkeFirstFloor = 'ratke-gebaeude-first-floor';

  Future<void> switchTo(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).hitTestable().first);
    await tester.pumpAndSettle();
  }

  testWidgets('the building picker offers all buildings', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    // The current building is on the chip…
    expect(find.text(buildingName(ratke)), findsOneWidget);
    await tester.tap(find.text(buildingName(ratke)));
    await tester.pumpAndSettle();
    // …and the menu offers every other catalogue building too.
    expect(find.text(buildingName('koethen-01')), findsOneWidget);
    expect(find.text(buildingName('koethen-02')), findsOneWidget);
    expect(find.text(buildingName('koethen-03')), findsOneWidget);
  });

  testWidgets('the new buildings open on their lowest approved floor', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    await tester.tap(find.text(buildingName(ratke)));
    await tester.pumpAndSettle();
    await switchTo(tester, buildingName('koethen-01'));
    FloorMapView view = tester.widget<FloorMapView>(find.byType(FloorMapView));
    expect(view.floor.floorKey, 'koethen-01-basement');
    expect(view.floor.svgAsset, 'assets/maps/koethen-01/basement.svg');

    await tester.tap(find.text(buildingName('koethen-01')));
    await tester.pumpAndSettle();
    await switchTo(tester, buildingName('koethen-02'));
    view = tester.widget<FloorMapView>(find.byType(FloorMapView));
    expect(view.floor.floorKey, 'koethen-02-basement');
    expect(view.floor.svgAsset, 'assets/maps/koethen-02/basement.svg');

    await tester.tap(find.text(buildingName('koethen-02')));
    await tester.pumpAndSettle();
    await switchTo(tester, buildingName('koethen-03'));
    view = tester.widget<FloorMapView>(find.byType(FloorMapView));
    expect(view.floor.floorKey, 'koethen-03-ground-floor');
    expect(view.floor.svgAsset, 'assets/maps/koethen-03/ground-floor.svg');
  });

  testWidgets('picking a search result switches building and floor', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);
    // Start in another building so the result has to switch both controls.
    await tester.tap(find.text(buildingName(ratke)));
    await tester.pumpAndSettle();
    await switchTo(tester, buildingName('koethen-03'));
    expect(
      tester.widget<FloorMapView>(find.byType(FloorMapView)).floor.floorKey,
      'koethen-03-ground-floor',
    );

    // Search stays global, so the room is still findable from here.
    await tester.enterText(find.byType(TextField), '216');
    await tester.pumpAndSettle();
    await tester.tap(find.text('216 · Gebäude 23 · Ratke-Gebäude'));
    await tester.pumpAndSettle();

    final FloorMapView view = tester.widget<FloorMapView>(
      find.byType(FloorMapView),
    );
    expect(view.floor.floorKey, ratkeFirstFloor);
    expect(view.selected?.roomKey, 'ratke-gebaeude-first-floor-216');
    expect(find.text(buildingName(ratke)), findsOneWidget);
  });

  testWidgets('a deep link sets building and floor', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, initialRoomKey: 'ratke-gebaeude-first-floor-210');

    final FloorMapView view = tester.widget<FloorMapView>(
      find.byType(FloorMapView),
    );
    expect(view.floor.floorKey, ratkeFirstFloor);
    expect(view.selected?.roomKey, 'ratke-gebaeude-first-floor-210');
    expect(find.text(buildingName(ratke)), findsOneWidget);
  });

  testWidgets('both selectors carry a screen reader label', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    expect(
      find.bySemanticsLabel(
        'Gebäude auswählen, aktuell ${buildingName(ratke)}',
      ),
      findsOneWidget,
    );
    // Two storeys: a real choice, announced as one.
    expect(
      find.bySemanticsLabel(
        'Etage auswählen, aktuell ${floorName(ratkeGroundFloor)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the floor picker switches storeys inside the building', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);
    expect(
      tester.widget<FloorMapView>(find.byType(FloorMapView)).floor.floorKey,
      ratkeGroundFloor,
    );

    await tester.tap(find.text(floorName(ratkeGroundFloor)));
    await tester.pumpAndSettle();
    await switchTo(tester, floorName(ratkeFirstFloor));

    final FloorMapView view = tester.widget<FloorMapView>(
      find.byType(FloorMapView),
    );
    expect(view.floor.floorKey, ratkeFirstFloor);
    expect(view.floor.svgAsset, 'assets/maps/ratke-gebaeude/first-floor.svg');
    // The building did not change with it.
    expect(find.text(buildingName(ratke)), findsOneWidget);
  });

  testWidgets('a room selection carries the map to its own storey', (
    WidgetTester tester,
  ) async {
    // The two plans are the same drawing, so landing on the right SHAPE proves
    // nothing — only the floor key does.
    await pumpMap(tester, initialRoomKey: 'ratke-gebaeude-first-floor-210');

    expect(
      tester.widget<FloorMapView>(find.byType(FloorMapView)).floor.floorKey,
      ratkeFirstFloor,
    );
    expect(find.text(floorName(ratkeFirstFloor)), findsOneWidget);
  });

  testWidgets('the selectors render in English', (WidgetTester tester) async {
    await pumpMap(tester, locale: AppLocales.english);

    expect(find.text(buildingName(ratke, locale: 'en')), findsOneWidget);
    expect(
      find.text(floorName(ratkeGroundFloor, locale: 'en')),
      findsOneWidget,
    );
  });

  testWidgets('long names do not overflow a narrow screen', (
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
      const CampusMapScreen(),
      overrides: mapOverrides(roomsFixture),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the selectors survive a wide screen too', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpScreen(
      tester,
      const CampusMapScreen(),
      overrides: mapOverrides(roomsFixture),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(FloorMapView), findsOneWidget);
  });
}

/// The building and floor controls sit on the left and stay inside the screen.
void _controlPositionTests() {
  testWidgets('the controls are left-aligned', (WidgetTester tester) async {
    // Both edges are positioned so the bar cannot outgrow the screen, so where
    // it sits is a question for the laid-out rectangle, not for the widget.
    await pumpMap(tester);

    final Rect bar = controlBarRect(tester);
    expect(bar.left, AppSpacing.lg);
    expect(
      bar.right,
      lessThanOrEqualTo(
        tester.getSize(find.byType(CampusMapScreen)).width - AppSpacing.lg,
      ),
      reason: 'the bar states what is drawn below it and stays out of the way',
    );
  });

  testWidgets('the compact control has a height of exactly 48 dp', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    // The combined building and floor control pill is laid out as a single row
    // with a fixed 48 dp height, saving 56 dp compared to stacked chips.
    final Finder controlBox = find
        .ancestor(
          of: find.text('Ratke-Gebäude'),
          matching: find.byType(SizedBox),
        )
        .first;
    final SizedBox box = tester.widget<SizedBox>(controlBox);
    expect(box.height, 48.0);
  });

  testWidgets('the label ellipsises instead of growing', (
    WidgetTester tester,
  ) async {
    // The preferred label width is wider than a narrow phone can spare, so a
    // long building name must be cut rather than push the control across the
    // map. The width itself is clamped to what the screen actually offers.
    await pumpMap(tester);

    final Text label = tester.widget<Text>(find.text('Erdgeschoss').first);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(label.maxLines, 1);
  });

  testWidgets(
    'room detail sheet uses surface color, top hairline, and zero elevation',
    (WidgetTester tester) async {
      await pumpMap(tester, initialRoomKey: 'ratke-gebaeude-first-floor-216');

      expect(find.textContaining('Ausgewählt: Hörsaal'), findsOneWidget);

      final DecoratedBox decoratedBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(CampusMapScreen),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border != null,
          ),
        ),
      );
      final BoxDecoration decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.border?.top, isNotNull);
      expect(decoration.border!.top.width, 1.0);

      final Material sheetMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byWidget(decoratedBox),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheetMaterial.elevation, 0.0);
    },
  );

  testWidgets('external room selection via deep link retains scale 1.0', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, initialRoomKey: 'ratke-gebaeude-first-floor-216');

    final FloorMapViewState state = tester.state<FloorMapViewState>(
      find.byType(FloorMapView),
    );
    final double scale = state.currentTransform.getMaxScaleOnAxis();
    expect(
      scale,
      closeTo(1.0, 0.001),
      reason: 'external room selection must not auto-zoom',
    );
  });

  testWidgets('direct room tap opens detail sheet without increasing zoom', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester);

    final FloorMapViewState state = tester.state<FloorMapViewState>(
      find.byType(FloorMapView),
    );
    final double initialScale = state.currentTransform.getMaxScaleOnAxis();

    await tester.tapAt(_roomCentre(tester, 'ratke-gebaeude-ground-floor-101'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ausgewählt: Raum 101'), findsOneWidget);
    final double finalScale = state.currentTransform.getMaxScaleOnAxis();
    expect(
      finalScale,
      closeTo(initialScale, 0.001),
      reason: 'direct room tap must not increase zoom level',
    );
  });
}

/// What the user actually sees after picking a room, and whether the compact
/// control fits the screen it is drawn on.
void _viewportTests() {
  // A phone in portrait: the size at which the map is used most.
  const Size phone = Size(390, 844);

  testWidgets('a deep link leaves the whole floor on screen', (
    WidgetTester tester,
  ) async {
    // LEVIORA-46: an external call shows the complete map. Switching the
    // automatic zoom off is only half of that — panning the plan out of the
    // viewport hides just as much of it as zooming in did.
    await pumpMap(
      tester,
      size: phone,
      initialRoomKey: 'ratke-gebaeude-first-floor-216',
    );

    final Rect plan = planOnScreen(tester);
    final Size viewport = tester.getSize(find.byType(FloorMapView));
    expect(plan.left, greaterThanOrEqualTo(-0.01), reason: 'plan $plan');
    expect(plan.top, greaterThanOrEqualTo(-0.01), reason: 'plan $plan');
    expect(
      plan.right,
      lessThanOrEqualTo(viewport.width + 0.01),
      reason: 'the floor plan $plan runs past the right edge of $viewport',
    );
    expect(
      plan.bottom,
      lessThanOrEqualTo(viewport.height + 0.01),
      reason: 'the floor plan $plan runs past the bottom edge of $viewport',
    );
  });

  testWidgets('a direct tap does not shift the plan at overview zoom', (
    WidgetTester tester,
  ) async {
    // At overview zoom the whole floor is visible by construction, so there is
    // nothing to centre — and the InteractiveViewer would refuse to hold the
    // pan anyway, snapping it back on the first gesture.
    await pumpMap(tester, size: phone);
    final FloorMapViewState state = tester.state<FloorMapViewState>(
      find.byType(FloorMapView),
    );
    final Rect before = planOnScreen(tester);

    await tester.tapAt(_roomCentre(tester, 'ratke-gebaeude-ground-floor-101'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ausgewählt: Raum 101'), findsOneWidget);
    expect(planOnScreen(tester), before);
    expect(state.currentTransform, Matrix4.identity());
  });

  testWidgets('the transform never leaves what the viewer allows', (
    WidgetTester tester,
  ) async {
    // The InteractiveViewer's child fills the viewport, so at scale 1 no pan
    // is legal at all. Writing one anyway produces a state the user cannot
    // keep: the first drag throws it away with a visible jump.
    await pumpMap(
      tester,
      size: phone,
      initialRoomKey: 'ratke-gebaeude-first-floor-216',
    );
    final FloorMapViewState state = tester.state<FloorMapViewState>(
      find.byType(FloorMapView),
    );
    final Matrix4 afterSelect = state.currentTransform.clone();

    await tester.drag(find.byType(FloorMapView), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(
      state.currentTransform,
      afterSelect,
      reason: 'a pan gesture must not undo the selection transform',
    );
  });

  testWidgets('the control bar stays inside every supported width', (
    WidgetTester tester,
  ) async {
    // Only `start` is positioned, so the row is laid out against an unbounded
    // width: an overflow here is silent and only a measurement finds it.
    for (final double width in <double>[320, 360, 390, 412, 600, 768, 1024]) {
      await pumpMap(tester, size: Size(width, 900));
      final Rect bar = controlBarRect(tester);
      expect(
        bar.right,
        lessThanOrEqualTo(width - AppSpacing.lg + 0.01),
        reason: 'at ${width}dp the control bar $bar runs past the screen edge',
      );
      expect(bar.height, AppSizes.minTouchTarget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'a narrow screen takes the width from the building, not the floor',
    (WidgetTester tester) async {
      // Something has to give on a 320dp phone — that is the price of the row
      // the map got back. It must not be the floor: that is the value which
      // changes constantly, while the building is one of very few and its full
      // name stays in the semantics either way.
      await pumpMap(tester, size: const Size(320, 640));

      expect(
        find.text('Erdgeschoss'),
        findsOneWidget,
        reason: 'the current floor is never the thing that is dropped',
      );
      expect(
        find.text('Ratke-Gebäude'),
        findsNothing,
        reason: 'the building label yields before the active floor label',
      );
      // Still a full picker, not a decoration.
      expect(find.byIcon(AppIcons.apartment_outlined), findsOneWidget);
      expect(
        controlBarRect(tester).right,
        lessThanOrEqualTo(320 - AppSpacing.lg + 0.01),
      );
    },
  );

  testWidgets('a phone with room for both keeps both names', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, size: const Size(412, 892));

    expect(find.text('Erdgeschoss'), findsOneWidget);
    expect(find.text('Ratke-Gebäude'), findsOneWidget);
  });

  testWidgets('a focused segment is marked by more than a tint', (
    WidgetTester tester,
  ) async {
    await pumpMap(tester, size: phone);
    expect(find.byType(FocusRing), findsNWidgets(2));
    expect(
      tester
          .widgetList<FocusRing>(find.byType(FocusRing))
          .every((FocusRing ring) => !ring.focused),
      isTrue,
    );

    // Tab until the keyboard reaches the bar; the search field and its clear
    // button come first in traversal order.
    bool reached = false;
    for (int i = 0; i < 12 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      reached = tester
          .widgetList<FocusRing>(find.byType(FocusRing))
          .any((FocusRing ring) => ring.focused);
    }

    expect(
      reached,
      isTrue,
      reason: 'a keyboard user must be able to see which segment they are on',
    );
    expect(
      tester
          .widgetList<FocusRing>(find.byType(FocusRing))
          .where((FocusRing ring) => ring.focused),
      hasLength(1),
      reason: 'exactly one segment carries the focus at a time',
    );
  });
}

/// The centre of [roomKey] as it currently sits on screen.
Offset _roomCentre(WidgetTester tester, String roomKey) {
  final FloorMapViewState state = tester.state<FloorMapViewState>(
    find.byType(FloorMapView),
  );
  final Rect box = tester.getRect(find.byType(FloorMapView));
  final Rect viewBox = state.widget.floor.viewBox;
  final Size planSize = Size(
    viewBox.width * state.planScale,
    viewBox.height * state.planScale,
  );
  final Offset origin = Offset(
    math.max(0, (box.width - planSize.width) / 2),
    math.max(0, (box.height - planSize.height) / 2),
  );
  final Offset focus = testCatalog.geometryFor(roomKey)!.focus;
  return box.topLeft +
      MatrixUtils.transformPoint(
        state.currentTransform,
        origin + Offset(focus.dx * state.planScale, focus.dy * state.planScale),
      );
}
