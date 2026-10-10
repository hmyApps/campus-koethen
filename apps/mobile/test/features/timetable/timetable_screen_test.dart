// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/locale/formatters.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/features/calendar/presentation/calendar_entry_sheet.dart';
import 'package:campus_koethen/features/campusmap/application/campus_map_providers.dart';
import 'package:campus_koethen/features/campusmap/data/map_asset_loader.dart';
import 'package:campus_koethen/features/campusmap/domain/map_catalog.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:campus_koethen/features/timetable/application/timetable_week.dart';
import 'package:campus_koethen/features/timetable/presentation/timetable_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/fake_http_adapter.dart';
import '../../support/fixtures.dart';
import '../../support/pump_app.dart';

/// The Monday of the week the screen shows by default.
final DateTime monday = TimetableWeek.startOf(DateTime.now());
late final MapCatalog testCatalog;

InMemoryKeyValueStore storeWithGroup() =>
    InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.preferredTimetableGroup: timetableGroupIdFixture,
    });

/// Every timetable fake adapter in this file must answer `/timetable/status`
/// and resolve-by-id (`/timetable/groups/<id>`) — the screen now calls both
/// on every load to show availability and to resolve the selected group,
/// even for tests only interested in the week's content. Each test still
/// supplies its own week/groups-list/error behaviour as [fallback].
///
/// The room catalogue an entry card resolves its rooms against is answered
/// here too, as the JSON array the contract promises ([rooms], empty by
/// default): a catch-all week object in its place is a structurally broken
/// list response, which is an error rather than "no rooms" (G-03).
FakeHttpResponse Function(RequestOptions) _withTimetableScaffolding(
  FakeHttpResponse Function(RequestOptions) fallback, {
  List<Map<String, dynamic>> rooms = const <Map<String, dynamic>>[],
}) {
  return (RequestOptions options) {
    if (options.path.endsWith('/rooms')) {
      return FakeHttpResponse(envelope(rooms));
    }
    if (options.path.endsWith('/timetable/status')) {
      return FakeHttpResponse(
        envelope(<String, dynamic>{
          'featureEnabled': true,
          'groupCount': timetableGroupsFixture.length,
        }),
      );
    }
    final RegExpMatch? groupId = RegExp(
      r'/timetable/groups/([^/]+)$',
    ).firstMatch(options.path);
    if (groupId != null) {
      final String id = groupId.group(1)!;
      final Map<String, dynamic> group = timetableGroupsFixture.firstWhere(
        (Map<String, dynamic> g) => g['id'] == id,
        orElse: () => timetableGroupsFixture.first,
      );
      return FakeHttpResponse(envelope(group));
    }
    return fallback(options);
  };
}

FakeHttpAdapter workingApi({Map<String, dynamic>? meta}) {
  return FakeHttpAdapter(
    _withTimetableScaffolding((RequestOptions options) {
      if (options.path.endsWith('/timetable/groups')) {
        return FakeHttpResponse(
          envelope(matchingTimetableGroups(options.queryParameters['query'])),
        );
      }
      return FakeHttpResponse(
        envelope(timetableWeekFixture(monday), meta: meta ?? timetableMeta()),
      );
    }),
  );
}

/// Pumps the screen with a preselected group and jumps to the Monday that
/// carries the fixture's appointments.
Future<ProviderContainer> pumpTimetable(
  WidgetTester tester, {
  FakeHttpAdapter? adapter,
  KeyValueStore? store,
  Locale locale = AppLocales.german,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  bool selectMonday = true,
  List<Override> overrides = const <Override>[],
}) async {
  final ProviderContainer container = await pumpScreen(
    tester,
    const TimetableScreen(),
    keyValueStore: store ?? storeWithGroup(),
    locale: locale,
    textScaler: textScaler,
    themeMode: themeMode,
    overrides: <Override>[
      apiClientProvider.overrideWithValue(
        fakeApiClient(adapter ?? workingApi()),
      ),
      ...overrides,
    ],
  );
  if (selectMonday) {
    container.read(selectedTimetableDayProvider.notifier).select(monday);
  }
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    testCatalog = await const MapAssetLoader().load();
  });

  group('onboarding', () {
    testWidgets('asks for a course when none is chosen', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(tester, store: InMemoryKeyValueStore());

      expect(find.text('Noch kein Kurs gewählt'), findsOneWidget);
      expect(find.text('Kurs auswählen'), findsOneWidget);
      expect(
        find.text('Etwas ist schiefgelaufen'),
        findsNothing,
        reason: 'an unchosen course is not an error',
      );
    });

    testWidgets('opens the picker and stores the chosen course', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await pumpTimetable(tester, store: store, selectMonday: false);

      await tester.tap(find.text('Kurs auswählen'));
      await tester.pumpAndSettle();

      expect(find.text('AIN2 - BT'), findsOneWidget);
      expect(find.text('MB1'), findsOneWidget);
      expect(find.text('FB5'), findsOneWidget, reason: 'department is visible');

      await tester.tap(find.text('MB1'));
      await tester.pumpAndSettle();

      expect(
        store.getString(PreferenceKeys.preferredTimetableGroup),
        '22222222-2222-4222-8222-222222222222',
        reason: 'only the Campus UUID is persisted',
      );
    });

    testWidgets('searches courses by short name, long name and department', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(
        tester,
        store: InMemoryKeyValueStore(),
        selectMonday: false,
      );
      await tester.tap(find.text('Kurs auswählen'));
      await tester.pumpAndSettle();

      // The search field debounces via a bare Timer, which pumpAndSettle()
      // does not reliably wait out on its own (it stops as soon as no new
      // frame is scheduled, and a Timer alone does not schedule one) — pump
      // past the 300ms debounce explicitly before letting the fetch settle.
      await tester.enterText(find.byType(TextField), 'maschinenbau');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('MB1'), findsOneWidget);
      expect(find.text('AIN2 - BT'), findsNothing);

      await tester.enterText(find.byType(TextField), 'fb5');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('AIN2 - BT'), findsOneWidget);
      expect(find.text('MB1'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Kein passender Kurs'), findsOneWidget);
    });
  });

  group('agenda', () {
    testWidgets('links only a mapped WebUntis room on the card', (
      WidgetTester tester,
    ) async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        _withTimetableScaffolding(
          rooms: <Map<String, dynamic>>[
            <String, dynamic>{
              'roomKey': 'ratke-gebaeude-first-floor-216',
              'roomNumber': '216',
              'buildingKey': 'ratke-gebaeude',
              'buildingNumber': '23',
              'buildingName': 'Ratke-Gebäude',
              'floorKey': 'ratke-gebaeude-first-floor',
              'floorName': '1. Obergeschoss',
              'roomType': 'lecture',
              'mapVersion': testCatalog.mapVersion,
              'sortOrder': 0,
            },
          ],
          (RequestOptions options) {
            if (options.path.endsWith('/timetable/groups')) {
              return FakeHttpResponse(envelope(timetableGroupsFixture));
            }
            final Map<String, dynamic> week = timetableWeekFixture(monday);
            final List<dynamic> days = week['days'] as List<dynamic>;
            final List<dynamic> entries =
                (days.first as Map<String, dynamic>)['entries']
                    as List<dynamic>;
            (entries.first
                as Map<String, dynamic>)['rooms'] = <Map<String, dynamic>>[
              <String, dynamic>{'shortName': 'K023-216'},
              <String, dynamic>{'shortName': 'D-04/201'},
            ];
            return FakeHttpResponse(envelope(week, meta: timetableMeta()));
          },
        ),
      );

      await pumpTimetable(
        tester,
        adapter: adapter,
        overrides: <Override>[
          mapCatalogProvider.overrideWith((Ref ref) => testCatalog),
        ],
      );

      expect(find.widgetWithText(TextButton, 'K023-216'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'D-04/201'), findsNothing);
      expect(find.text('D-04/201'), findsWidgets);
      final Finder missingRoom = find.text('D-04/201').first;
      final Finder searchButton = find
          .widgetWithText(OutlinedButton, 'Raum suchen')
          .first;
      expect(searchButton, findsOneWidget);
      expect(
        tester.getTopLeft(searchButton).dx,
        greaterThan(tester.getTopRight(missingRoom).dx),
      );
      expect(
        (tester.getCenter(searchButton).dy - tester.getCenter(missingRoom).dy)
            .abs(),
        lessThan(25),
      );
    });

    testWidgets('filters only the deselected exact lesson information text', (
      WidgetTester tester,
    ) async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        _withTimetableScaffolding((RequestOptions options) {
          if (options.path.endsWith('/timetable/groups')) {
            return FakeHttpResponse(envelope(timetableGroupsFixture));
          }
          if (options.path.endsWith('/timetable/lesson-info')) {
            return FakeHttpResponse(
              envelope(<String, dynamic>{
                'values': <String>['P1', 'Gruppe1'],
                'hasWithoutInfo': true,
              }),
            );
          }
          final Map<String, dynamic> week = timetableWeekFixture(monday);
          final List<dynamic> days = week['days'] as List<dynamic>;
          final Map<String, dynamic> firstDay =
              days.first as Map<String, dynamic>;
          final List<dynamic> entries = firstDay['entries'] as List<dynamic>;
          (entries[0] as Map<String, dynamic>)['lessonInfo'] = 'P1';
          (entries[1] as Map<String, dynamic>)['lessonInfo'] = 'Gruppe1';
          return FakeHttpResponse(envelope(week, meta: timetableMeta()));
        }),
      );

      await pumpTimetable(tester, adapter: adapter);
      expect(find.text('Mathematik 2'), findsOneWidget);
      expect(find.text('Technische Mechanik'), findsOneWidget);
      expect(find.text('Projektseminar'), findsOneWidget);

      await tester.tap(find.byTooltip('Stunden nach Information filtern'));
      await tester.pumpAndSettle();
      final CheckboxListTile p1 = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'P1'),
      );
      expect(p1.value, isTrue);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'P1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();

      expect(find.text('Mathematik 2'), findsNothing);
      expect(find.text('Technische Mechanik'), findsOneWidget);
      expect(find.text('Projektseminar'), findsOneWidget);
    });

    testWidgets('shows lesson information on the card and in its details', (
      WidgetTester tester,
    ) async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        _withTimetableScaffolding((RequestOptions options) {
          if (options.path.endsWith('/timetable/groups')) {
            return FakeHttpResponse(envelope(timetableGroupsFixture));
          }
          final Map<String, dynamic> week = timetableWeekFixture(monday);
          final List<dynamic> days = week['days'] as List<dynamic>;
          final Map<String, dynamic> firstDay =
              days.first as Map<String, dynamic>;
          final List<dynamic> entries = firstDay['entries'] as List<dynamic>;
          (entries.first as Map<String, dynamic>)['lessonInfo'] =
              'Fiktive Information zur Stunde';
          return FakeHttpResponse(envelope(week, meta: timetableMeta()));
        }),
      );

      await pumpTimetable(tester, adapter: adapter);
      expect(find.text('Fiktive Information zur Stunde'), findsOneWidget);
      await tester.tap(find.text('Mathematik 2'));
      await tester.pumpAndSettle();
      expect(find.text('Fiktive Information zur Stunde'), findsNWidgets(2));
    });

    testWidgets('an appointment opens its details', (
      WidgetTester tester,
    ) async {
      // The card is a summary; everything else about the slot — groups, the
      // note, the way to the room — lives in the same sheet the calendar uses.
      await pumpTimetable(tester);

      await tester.tap(find.text('Mathematik 2'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarEntrySheet), findsOneWidget);
      expect(find.text('D-04/201'), findsWidgets);
    });

    testWidgets('shows the appointments of the selected day', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(tester);

      expect(find.text('Mathematik 2'), findsOneWidget);
      expect(find.text('Projektseminar'), findsOneWidget);
      expect(find.text('Demo Demoperson01'), findsWidgets);
      expect(find.text('D-04/201'), findsWidgets);
      expect(find.text('Lehrveranstaltung'), findsWidgets);

      final DateTime start = DateTime.utc(
        monday.year,
        monday.month,
        monday.day,
        6,
      );
      expect(
        find.textContaining(AppDateFormats.time(start, 'de')),
        findsWidgets,
        reason: 'the start time is rendered locale aware',
      );
    });

    testWidgets('marks cancelled, changed and unknown states with text', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(tester);

      expect(find.text('Fällt aus'), findsOneWidget);
      expect(find.text('Geändert'), findsOneWidget);
      expect(find.text('Status unklar'), findsOneWidget);
      expect(
        find.text('Sonstiger Termin'),
        findsOneWidget,
        reason: 'an unknown type falls back to a neutral label',
      );
    });

    testWidgets('gives every state an icon and a screen reader label', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpTimetable(tester);

      expect(find.byIcon(AppIcons.event_busy_outlined), findsOneWidget);
      expect(find.byIcon(AppIcons.edit_calendar_outlined), findsOneWidget);
      expect(find.byIcon(AppIcons.help_outline), findsOneWidget);

      expect(
        find.bySemanticsLabel(RegExp('Technische Mechanik.*Fällt aus')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('shows an empty day instead of an error', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpTimetable(tester);

      container
          .read(selectedTimetableDayProvider.notifier)
          .select(TimetableWeek.shift(monday, 1));
      await tester.pumpAndSettle();

      expect(find.text('Keine Termine'), findsOneWidget);
      expect(find.text('Etwas ist schiefgelaufen'), findsNothing);
      expect(find.text('Mathematik 2'), findsNothing);
    });

    testWidgets('week navigation moves to the next week', (
      WidgetTester tester,
    ) async {
      final FakeHttpAdapter adapter = workingApi();
      final ProviderContainer container = await pumpTimetable(
        tester,
        adapter: adapter,
      );

      await tester.tap(find.byTooltip('Nächste Woche'));
      await tester.pumpAndSettle();

      expect(
        container.read(selectedTimetableDayProvider),
        TimetableWeek.shift(monday, 7),
      );
      final String expected = AppDateFormats.isoDate(
        TimetableWeek.shift(monday, 7),
      );
      expect(
        adapter.queries.any((String query) => query.contains('from=$expected')),
        isTrue,
        reason: 'the next week is requested from the API',
      );
    });

    testWidgets('shows the factual source notice', (WidgetTester tester) async {
      await pumpTimetable(tester);

      final Finder notice = find.textContaining('Quelle:');
      await tester.scrollUntilVisible(
        notice,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(notice, findsOneWidget);
      final String text = tester.widget<Text>(notice).data!;
      expect(text, contains('keine Zusammenarbeit'));
      expect(text, isNot(contains('offiziell')));
    });
  });

  group('course hiding', () {
    testWidgets(
      'hiding a course from its card removes it from the agenda and offers '
      'undo',
      (WidgetTester tester) async {
        await pumpTimetable(tester);
        expect(find.text('Mathematik 2'), findsOneWidget);

        await tester.tap(find.byTooltip('Mathematik 2 ausblenden'));
        await tester.pump();

        expect(find.text('Mathematik 2'), findsNothing);
        expect(find.text('„Mathematik 2“ ausgeblendet'), findsOneWidget);
        expect(
          find.text('Technische Mechanik'),
          findsOneWidget,
          reason: 'only the hidden course is affected',
        );

        // The snackbar's enter animation must finish before its action sits
        // at the position a tap targets.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Rückgängig'));
        await tester.pumpAndSettle();

        expect(find.text('Mathematik 2'), findsOneWidget);
      },
    );

    testWidgets('a hidden course can be restored from the filter sheet', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(tester);
      await tester.tap(find.byTooltip('Mathematik 2 ausblenden'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byTooltip('Stunden nach Information filtern'));
      await tester.pumpAndSettle();

      expect(find.text('Ausgeblendete Kurse'), findsOneWidget);
      expect(find.text('Mathematik 2'), findsOneWidget);

      await tester.tap(find.text('Mathematik 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();

      expect(find.text('Mathematik 2'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('shows an error with a retry when nothing can be served', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(
        tester,
        adapter: FakeHttpAdapter((RequestOptions _) => throw Exception('down')),
      );

      expect(
        find.text(
          'Keine Verbindung zum Server. Bitte prüfe deine Internetverbindung.',
        ),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('labels cached content as offline', (
      WidgetTester tester,
    ) async {
      bool offline = false;
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        if (offline) throw Exception('offline');
        return _withTimetableScaffolding((RequestOptions options) {
          if (options.path.endsWith('/timetable/groups')) {
            return FakeHttpResponse(envelope(timetableGroupsFixture));
          }
          return FakeHttpResponse(
            envelope(timetableWeekFixture(monday), meta: timetableMeta()),
          );
        })(options);
      });

      final ProviderContainer container = await pumpTimetable(
        tester,
        adapter: adapter,
      );
      expect(find.text('Offline gespeicherte Inhalte'), findsNothing);

      offline = true;
      container.invalidate(timetableWeekProvider);
      await tester.pumpAndSettle();

      expect(find.text('Offline gespeicherte Inhalte'), findsOneWidget);
      expect(find.text('Mathematik 2'), findsOneWidget);
    });

    testWidgets('warns about stale server data', (WidgetTester tester) async {
      await pumpTimetable(
        tester,
        adapter: workingApi(meta: timetableMeta(dataStale: true)),
      );

      expect(find.text('Daten möglicherweise veraltet'), findsOneWidget);
      expect(find.text('Mathematik 2'), findsOneWidget);
    });

    testWidgets('explains a pending data set without looking broken', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(
        tester,
        adapter: workingApi(meta: timetableMeta(dataState: 'pending')),
      );

      expect(find.text('Stundenplan wird vorbereitet'), findsOneWidget);
      expect(find.text('Etwas ist schiefgelaufen'), findsNothing);
    });

    testWidgets('explains a disabled feature without looking broken', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(
        tester,
        adapter: workingApi(
          meta: timetableMeta(
            featureEnabled: false,
            dataState: 'unavailable',
            lastSuccessfulSyncAt: null,
          ),
        ),
      );

      expect(
        find.text('Stundenplan noch nicht freigeschaltet'),
        findsOneWidget,
      );
      expect(find.text('Etwas ist schiefgelaufen'), findsNothing);
      expect(find.text('Erneut versuchen'), findsNothing);
    });

    testWidgets('reports a permanently unavailable range', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(
        tester,
        adapter: workingApi(meta: timetableMeta(dataState: 'unavailable')),
      );

      expect(find.text('Kein Datenstand verfügbar'), findsOneWidget);
      expect(find.text('Etwas ist schiefgelaufen'), findsNothing);
    });

    testWidgets('never leaves a poll timer behind when disposed', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(
        tester,
        adapter: workingApi(meta: timetableMeta(dataState: 'pending')),
      );
      expect(find.text('Stundenplan wird vorbereitet'), findsOneWidget);

      // Replacing the screen disposes it; a surviving timer would make the
      // test framework fail with a pending timer error.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility and i18n', () {
    testWidgets('renders English when the locale is en', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(
        tester,
        store: InMemoryKeyValueStore(),
        locale: AppLocales.english,
      );

      expect(find.text('No course selected yet'), findsOneWidget);
      expect(find.text('Choose course'), findsWidgets);
      expect(find.text('Noch kein Kurs gewählt'), findsNothing);
    });

    testWidgets('keeps foreign names untranslated in English', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(tester, locale: AppLocales.english);

      expect(find.text('Mathematik 2'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Class'), findsWidgets);
    });

    testWidgets('survives doubled text size without overflow', (
      WidgetTester tester,
    ) async {
      // Doubled text needs doubled room. The question this test asks is
      // whether the layout survives the scale, not whether a day's teaching
      // fits on one screen at it — that is what scrolling is for.
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpTimetable(tester, textScaler: const TextScaler.linear(2));

      expect(tester.takeException(), isNull);
      expect(find.text('Mathematik 2'), findsOneWidget);
      expect(find.text('Fällt aus'), findsOneWidget);
    });

    testWidgets('renders in the dark theme', (WidgetTester tester) async {
      await pumpTimetable(tester, themeMode: ThemeMode.dark);

      expect(tester.takeException(), isNull);
      expect(find.text('Mathematik 2'), findsOneWidget);
      expect(find.text('Fällt aus'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('Mathematik 2'))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('keeps navigation targets at least 48dp tall', (
      WidgetTester tester,
    ) async {
      await pumpTimetable(tester);

      final Iterable<Element> targets = find
          .byWidgetPredicate(
            (Widget widget) =>
                widget is IconButton ||
                widget.runtimeType.toString() == '_TimetableDayChip',
          )
          .evaluate();
      expect(targets, isNotEmpty);
      for (final Element element in targets) {
        expect(
          element.size!.height,
          greaterThanOrEqualTo(48.0),
          reason: '${element.widget.runtimeType} is too small to hit',
        );
      }
    });
  });
}
