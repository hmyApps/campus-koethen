// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/core/documents/document_share_service.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/locale/formatters.dart';
import 'package:campus_koethen/core/network/api_client.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/calendar/application/calendar_providers.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry_details.dart';
import 'package:campus_koethen/features/calendar/presentation/calendar_entry_sheet.dart';
import 'package:campus_koethen/features/calendar/presentation/calendar_screen.dart';
import 'package:campus_koethen/features/calendar/presentation/calendar_source_sheets.dart';
import 'package:campus_koethen/features/calendar/presentation/week_grid_view.dart';
import 'package:campus_koethen/core/widgets/screen_scaffold.dart';
import 'package:campus_koethen/core/widgets/time_rail.dart';
import 'package:campus_koethen/features/calendar/presentation/week_strip.dart';
import 'package:campus_koethen/features/timetable/application/timetable_week.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/fake_http_adapter.dart';
import '../../support/pump_app.dart';

ApiClient _emptyApi() => fakeApiClient(
  FakeHttpAdapter((RequestOptions options) {
    if (options.path.endsWith('/timetable/status')) {
      // Enabled with a non-empty catalogue, matching this file's existing
      // "course not yet chosen" tests; "distinguishes a disabled backend"
      // overrides calendarDataProvider directly instead of going through
      // this fake HTTP layer, so it is unaffected by this default.
      return FakeHttpResponse(
        envelope(<String, Object?>{'featureEnabled': true, 'groupCount': 1}),
      );
    }
    final RegExpMatch? groupId = RegExp(
      r'/timetable/groups/([^/]+)$',
    ).firstMatch(options.path);
    if (groupId != null) {
      return FakeHttpResponse(
        envelope(<String, Object?>{
          'id': groupId.group(1),
          'shortName': 'Fixture',
        }),
      );
    }
    return FakeHttpResponse(envelope(<Object>[]));
  }),
);

/// Records what the export action hands off instead of opening the real OS
/// share sheet.
class _FakeShareService extends DocumentShareService {
  _FakeShareService(this.shared);

  final List<AppDocument> shared;

  @override
  Future<void> share(AppDocument document) async {
    shared.add(document);
  }
}

Future<ProviderContainer> pumpCalendar(
  WidgetTester tester, {
  KeyValueStore? store,
  Locale locale = AppLocales.german,
  Size size = const Size(390, 1200),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final ProviderContainer container = await pumpScreen(
    tester,
    const CalendarScreen(),
    locale: locale,
    textScaler: textScaler,
    keyValueStore: store,
    overrides: <Override>[apiClientProvider.overrideWithValue(_emptyApi())],
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('timetable source status', () {
    Future<void> pumpStatus(
      WidgetTester tester,
      CalendarTimetableState state,
    ) async {
      await pumpScreen(
        tester,
        const CalendarScreen(),
        overrides: <Override>[
          apiClientProvider.overrideWithValue(_emptyApi()),
          calendarDataProvider.overrideWith(
            (Ref ref, DateTime day) => CalendarData(
              entries: const <CalendarEntry>[],
              enabledSources: state == CalendarTimetableState.hidden
                  ? const <CalendarSource>{}
                  : const <CalendarSource>{CalendarSource.timetable},
              timetableState: state,
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('distinguishes a disabled backend', (
      WidgetTester tester,
    ) async {
      await pumpStatus(tester, CalendarTimetableState.disabled);
      expect(
        find.text('Stundenplan noch nicht freigeschaltet'),
        findsOneWidget,
      );
    });

    testWidgets('distinguishes a missing group', (WidgetTester tester) async {
      await pumpStatus(tester, CalendarTimetableState.needsGroup);
      expect(
        find.text('Wähle im Stundenplan eine Gruppe, um Termine zu sehen.'),
        findsOneWidget,
      );
    });

    testWidgets('distinguishes a pending import', (WidgetTester tester) async {
      await pumpStatus(tester, CalendarTimetableState.pending);
      expect(find.text('Stundenplan wird vorbereitet'), findsOneWidget);
    });

    testWidgets('distinguishes a hidden source', (WidgetTester tester) async {
      await pumpStatus(tester, CalendarTimetableState.hidden);
      expect(
        find.text('Stundenplan ist als Kalenderquelle ausgeblendet.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('layout matrix keeps the calendar controls usable', (
    WidgetTester tester,
  ) async {
    for (final (Size size, TextScaler scaler) in <(Size, TextScaler)>[
      (const Size(320, 800), TextScaler.noScaling),
      (const Size(360, 800), const TextScaler.linear(1.3)),
      (const Size(800, 360), TextScaler.noScaling),
      (const Size(320, 1200), const TextScaler.linear(2)),
    ]) {
      await pumpCalendar(tester, size: size, textScaler: scaler);

      expect(find.text('Kalender'), findsOneWidget);
      expect(find.byTooltip('Quellen'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size at $scaler');
    }
  });

  testWidgets('opens with the masthead and the three views, no app bar', (
    WidgetTester tester,
  ) async {
    await pumpCalendar(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ScreenHeader), findsOneWidget);
    expect(find.text('Kalender'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Woche'), findsOneWidget);
    expect(find.text('Liste'), findsOneWidget);
  });

  testWidgets('spends one band of the screen on controls, not two', (
    WidgetTester tester,
  ) async {
    // Which calendars you are looking at is answered once and lives in the
    // masthead; which day you are looking at is asked all day and gets the
    // room. Only the view switcher stands between the rule and the calendar.
    await pumpCalendar(tester);

    expect(find.byTooltip('Quellen'), findsOneWidget);
    // The source names are in the sheet behind that action, not on the screen.
    expect(find.text('Stundenplan'), findsNothing);
    expect(find.text('Events'), findsNothing);

    final double views = tester
        .getTopLeft(find.byType(SegmentedButton<CalendarViewMode>))
        .dy;
    expect(
      tester.getTopLeft(find.byType(WeekStrip)).dy,
      greaterThan(views),
      reason: 'the view switcher is the only band above the day picker',
    );
  });

  testWidgets('opens on the day agenda, not on a month grid', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpCalendar(tester);

    expect(container.read(calendarViewModeProvider), CalendarViewMode.day);
    expect(
      find.byType(WeekStrip),
      findsOneWidget,
      reason: 'the week strip replaces the month grid as the day picker',
    );
  });

  testWidgets('the week strip offers seven days', (WidgetTester tester) async {
    await pumpCalendar(tester);

    final WeekStrip strip = tester.widget<WeekStrip>(find.byType(WeekStrip));
    expect(strip.entryCounts, isNotNull);
    // Seven tappable cells, each at least a 48dp target — the day picker keeps
    // the weekend reachable even when the week VIEW is Monday to Friday.
    // `selected` is only ever set on a day cell (never on the week arrows),
    // so it singles the cells out from the rest of the strip's buttons.
    final Iterable<Semantics> cells = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(WeekStrip),
            matching: find.byType(Semantics),
          ),
        )
        .where(
          (Semantics s) =>
              (s.properties.button ?? false) && s.properties.selected != null,
        );
    expect(cells.length, 7);
  });

  testWidgets('counts an entry just after midnight under its own day', (
    WidgetTester tester,
  ) async {
    // The strip's dots and counts once read the UTC date fields off the start
    // instant while the day list converted to local first: an entry at 00:30
    // in Köthen hung under the previous day. The runner zone decides whether
    // the two readings differ at all — CI pins `TZ=Europe/Berlin`.
    final DateTime today = TimetableWeek.dayOf(DateTime.now());
    final CalendarEntry night = CalendarEntry(
      id: 'publicCalendar:demo:night',
      source: CalendarSource.publicCalendar,
      title: 'Nachtschicht',
      start: DateTime(today.year, today.month, today.day, 0, 30).toUtc(),
      end: DateTime(today.year, today.month, today.day, 1, 30).toUtc(),
      sourceLabel: 'Demokalender (fiktiv)',
    );

    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpScreen(
      tester,
      const CalendarScreen(),
      overrides: <Override>[
        apiClientProvider.overrideWithValue(_emptyApi()),
        calendarDataProvider.overrideWith(
          (Ref ref, DateTime day) => CalendarData(
            entries: <CalendarEntry>[night],
            enabledSources: const <CalendarSource>{
              CalendarSource.publicCalendar,
            },
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    // The day list opens on today and shows it there.
    expect(find.text('Nachtschicht'), findsOneWidget);

    // Monday first, so the cell for today is at its weekday index.
    final List<Semantics> cells = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(WeekStrip),
            matching: find.byType(Semantics),
          ),
        )
        .where(
          (Semantics s) =>
              (s.properties.button ?? false) && s.properties.selected != null,
        )
        .toList();
    expect(cells, hasLength(7));

    final List<String?> values = cells
        .map((Semantics s) => s.properties.value)
        .toList();
    expect(
      values[today.weekday - 1],
      '1 Termin',
      reason: 'the day the entry is listed on is the day it is counted on',
    );
    expect(
      values.where((String? value) => value != null),
      hasLength(1),
      reason: 'no other day may announce an entry that is not on it',
    );
  });

  testWidgets('tapping a day in the strip moves the agenda', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpCalendar(tester);
    final DateTime before = container.read(calendarFocusedDayProvider);

    final WeekStrip strip = tester.widget<WeekStrip>(find.byType(WeekStrip));
    // Pick a day that is definitely not the current one.
    final DateTime target = before.add(
      Duration(days: before.weekday == DateTime.monday ? 2 : -1),
    );
    strip.onSelect(target);
    await tester.pumpAndSettle();

    final DateTime after = container.read(calendarFocusedDayProvider);
    expect(after.day, target.day);
    expect(after, isNot(before));
  });

  group('moving through the weeks', () {
    testWidgets('swiping the strip moves one week and keeps the weekday', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpCalendar(tester);
      final DateTime before = container.read(calendarFocusedDayProvider);

      await tester.fling(
        find.byKey(const Key('weekStripMonthLabel')),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();

      final DateTime after = container.read(calendarFocusedDayProvider);
      expect(after.difference(before).inDays, 7);
      expect(after.weekday, before.weekday);
    });

    testWidgets('and back the other way, arbitrarily far', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpCalendar(tester);
      final DateTime before = container.read(calendarFocusedDayProvider);

      for (int i = 0; i < 6; i++) {
        await tester.fling(
          find.byKey(const Key('weekStripMonthLabel')),
          const Offset(200, 0),
          1000,
        );
        await tester.pumpAndSettle();
      }

      final DateTime after = container.read(calendarFocusedDayProvider);
      expect(after.difference(before).inDays, -42);
      expect(after.weekday, before.weekday);
    });

    testWidgets('the day content still swipes a day at a time', (
      WidgetTester tester,
    ) async {
      // Two gestures, two areas: neither may swallow the other.
      final ProviderContainer container = await pumpCalendar(tester);
      final DateTime before = container.read(calendarFocusedDayProvider);

      await tester.fling(
        find.text('Keine Einträge an diesem Tag.'),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(
        container.read(calendarFocusedDayProvider).difference(before).inDays,
        1,
      );
    });

    testWidgets('Today comes back from wherever the swiping ended up', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpCalendar(tester);
      container
          .read(calendarFocusedDayProvider.notifier)
          .select(DateTime(2026, 1, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Heute'));
      await tester.pumpAndSettle();

      final DateTime now = DateTime.now();
      final DateTime focused = container.read(calendarFocusedDayProvider);
      expect(focused.year, now.year);
      expect(focused.month, now.month);
      expect(focused.day, now.day);
    });

    testWidgets(
      'Today is available and returns to today when another day in the current week is selected',
      (WidgetTester tester) async {
        final ProviderContainer container = await pumpCalendar(tester);
        final DateTime now = DateTime.now();
        final DateTime anotherDayInWeek = now.weekday == DateTime.monday
            ? now.add(const Duration(days: 2))
            : now.subtract(const Duration(days: 1));
        container
            .read(calendarFocusedDayProvider.notifier)
            .select(anotherDayInWeek);
        await tester.pumpAndSettle();

        expect(find.text('Heute'), findsOneWidget);
        await tester.tap(find.text('Heute'));
        await tester.pumpAndSettle();

        final DateTime focused = container.read(calendarFocusedDayProvider);
        expect(focused.year, now.year);
        expect(focused.month, now.month);
        expect(focused.day, now.day);
      },
    );
  });

  group('the sources action', () {
    /// Opens the masthead's "Quellen" action.
    Future<void> openSources(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Quellen'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers the lesson information filter for a chosen course', (
      WidgetTester tester,
    ) async {
      await pumpCalendar(
        tester,
        store: InMemoryKeyValueStore(<String, Object>{
          PreferenceKeys.preferredTimetableGroup:
              '11111111-1111-4111-8111-111111111111',
        }),
      );
      await openSources(tester);
      await tester.tap(find.text('Stundenplan'));
      await tester.pumpAndSettle();

      expect(find.text('Stunden nach Information filtern'), findsOneWidget);
    });

    testWidgets('lists all three sources and spells out their state', (
      WidgetTester tester,
    ) async {
      // The sheet has room the old button row did not, so the state is a line
      // of text rather than something to infer from a glyph.
      await pumpCalendar(tester);
      await openSources(tester);

      expect(find.text('Stundenplan'), findsOneWidget);
      expect(find.text('Moodle'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Sichtbar'), findsNWidgets(2));
      expect(find.text('Nicht verbunden'), findsOneWidget);
    });

    testWidgets('ignores a legacy global public-calendar hide setting', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await store.setStringList(
        PreferenceKeys.calendarDisabledSources,
        <String>[CalendarSource.publicCalendar.storageValue],
      );
      await pumpCalendar(tester, store: store);
      await openSources(tester);

      // Public calendars are now controlled individually, so a persisted
      // all-calendars-off value must no longer hide them.
      Finder inSheet(IconData icon) => find.descendant(
        of: find.byType(ListTile),
        matching: find.byIcon(icon),
      );

      expect(inSheet(AppIcons.visibility_off_outlined), findsNothing);
      expect(inSheet(AppIcons.link_off), findsOneWidget);
      expect(
        inSheet(calendarSourceIcon(CalendarSource.timetable)),
        findsOneWidget,
      );
      expect(
        inSheet(calendarSourceIcon(CalendarSource.publicCalendar)),
        findsOneWidget,
        reason: 'legacy global state cannot hide every public calendar',
      );
    });

    testWidgets('uses the one sources action on the masthead', (
      WidgetTester tester,
    ) async {
      // The old global public-calendar hide value must not affect the icon.
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await store.setStringList(
        PreferenceKeys.calendarDisabledSources,
        <String>[CalendarSource.publicCalendar.storageValue],
      );
      await pumpCalendar(tester, store: store);

      expect(find.byIcon(AppIcons.tune), findsOneWidget);
      expect(find.byTooltip('Quellen'), findsOneWidget);
    });

    testWidgets('leads into the timetable sheet', (WidgetTester tester) async {
      await pumpCalendar(tester);
      await openSources(tester);

      await tester.tap(find.text('Stundenplan'));
      await tester.pumpAndSettle();

      expect(find.text('Im Kalender anzeigen'), findsOneWidget);
      expect(find.text('Noch kein Kurs gewählt'), findsOneWidget);
      // Twice: the sheet's button, and the hint on the screen behind it.
      expect(find.text('Kurs wählen'), findsNWidgets(2));
    });

    testWidgets('hiding a source from its sheet is remembered', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = await pumpCalendar(
        tester,
        store: store,
      );

      await openSources(tester);
      await tester.tap(find.text('Stundenplan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Im Kalender anzeigen'));
      await tester.pumpAndSettle();

      expect(
        container.read(calendarEnabledSourcesProvider),
        isNot(contains(CalendarSource.timetable)),
      );
      expect(
        store.getStringList(PreferenceKeys.calendarDisabledSources),
        <String>[CalendarSource.timetable.storageValue],
      );
    });

    testWidgets('Moodle explains itself when not connected', (
      WidgetTester tester,
    ) async {
      await pumpCalendar(tester);
      await openSources(tester);

      await tester.tap(find.text('Moodle'));
      await tester.pumpAndSettle();

      expect(find.text('Moodle verbinden'), findsOneWidget);
      // Nothing to switch yet — the sheet offers the way in instead.
      expect(find.text('Im Kalender anzeigen'), findsNothing);
    });

    testWidgets('events leads to the public calendars', (
      WidgetTester tester,
    ) async {
      await pumpCalendar(tester);
      await openSources(tester);

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      expect(find.text('Öffentliche Kalender'), findsOneWidget);
      expect(find.text('Ausgewählte in Google Kalender öffnen'), findsNothing);
    });
  });

  group('week view', _weekViewTests);

  group('source filters', () {
    testWidgets('every source is on for a fresh install', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpCalendar(tester);
      expect(
        container.read(calendarEnabledSourcesProvider),
        kMergeableCalendarSources.toSet(),
      );
    });

    testWidgets('switching a source off is remembered', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = await pumpCalendar(
        tester,
        store: store,
      );

      await container
          .read(calendarEnabledSourcesProvider.notifier)
          .toggle(CalendarSource.timetable);
      await tester.pumpAndSettle();

      expect(
        container.read(calendarEnabledSourcesProvider),
        isNot(contains(CalendarSource.timetable)),
      );
      // Stored as the DISABLED set, so a source added later defaults to on.
      expect(
        store.getStringList(PreferenceKeys.calendarDisabledSources),
        <String>[CalendarSource.timetable.storageValue],
      );

      // A fresh container reading the same store keeps the choice.
      final ProviderContainer restarted = ProviderContainer(
        overrides: <Override>[keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(restarted.dispose);
      expect(
        restarted.read(calendarEnabledSourcesProvider),
        isNot(contains(CalendarSource.timetable)),
      );
    });

    testWidgets('an unknown stored source is ignored, not fatal', (
      WidgetTester tester,
    ) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await store.setStringList(
        PreferenceKeys.calendarDisabledSources,
        <String>[
          'a-source-that-was-removed',
          CalendarSource.moodle.storageValue,
        ],
      );

      final ProviderContainer container = await pumpCalendar(
        tester,
        store: store,
      );

      expect(container.read(calendarEnabledSourcesProvider), <CalendarSource>{
        CalendarSource.timetable,
        CalendarSource.publicCalendar,
      });
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('renders in English', (WidgetTester tester) async {
    await pumpCalendar(tester, locale: AppLocales.english);

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);

    await tester.tap(find.byTooltip('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('Timetable'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
  });

  testWidgets('survives a narrow phone with doubled text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpScreen(
      tester,
      const CalendarScreen(),
      textScaler: const TextScaler.linear(2),
      overrides: <Override>[apiClientProvider.overrideWithValue(_emptyApi())],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('the list view builds only what is on screen', () {
    List<CalendarEntry> manyEntries(DateTime anchor) => <CalendarEntry>[
      for (int day = 0; day < 30; day++)
        for (int slot = 0; slot < 3; slot++)
          CalendarEntry(
            id: 'publicCalendar:demo:$day-$slot',
            source: CalendarSource.publicCalendar,
            title: 'Termin $day-$slot',
            start: DateTime(
              anchor.year,
              anchor.month,
              anchor.day + day,
              8 + slot * 2,
            ),
            end: DateTime(
              anchor.year,
              anchor.month,
              anchor.day + day,
              9 + slot * 2,
            ),
            sourceLabel: 'Demokalender (fiktiv)',
          ),
    ];

    Future<ProviderContainer> pumpList(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final ProviderContainer container = await pumpScreen(
        tester,
        const CalendarScreen(),
        overrides: <Override>[
          apiClientProvider.overrideWithValue(_emptyApi()),
          calendarDataProvider.overrideWith(
            (Ref ref, DateTime day) => CalendarData(
              entries: manyEntries(day),
              enabledSources: const <CalendarSource>{
                CalendarSource.publicCalendar,
              },
            ),
          ),
          calendarListDataProvider.overrideWith(
            (Ref ref, DateTime day) => CalendarData(
              entries: manyEntries(day),
              enabledSources: const <CalendarSource>{
                CalendarSource.publicCalendar,
              },
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      container
          .read(calendarViewModeProvider.notifier)
          .set(CalendarViewMode.list);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a month of entries does not all end up in the tree', (
      WidgetTester tester,
    ) async {
      await pumpList(tester);

      // 90 entries across 30 days: an eagerly built list put every one of them
      // in the tree at once. Only the visible stretch may be built.
      expect(find.byType(TimeRailTile), findsWidgets);
      expect(
        tester.widgetList<TimeRailTile>(find.byType(TimeRailTile)).length,
        lessThan(30),
      );
      expect(find.text('Termin 0-0'), findsOneWidget);
      expect(find.text('Termin 29-2'), findsNothing);
    });

    testWidgets('scrolling reaches the entries further down', (
      WidgetTester tester,
    ) async {
      await pumpList(tester);

      await tester.scrollUntilVisible(
        find.text('Termin 6-0'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Termin 6-0'), findsOneWidget);
    });
  });

  group('canteen favourite meals', () {
    testWidgets(
      'a favourited dish on the merged calendar shows the canteen as its '
      'source, both in the agenda and the detail sheet',
      (WidgetTester tester) async {
        final DateTime today = TimetableWeek.dayOf(DateTime.now());
        final CalendarEntry dish = CalendarEntry(
          id: 'canteenFavourite:mensa-koethen:$today:Bulgur-Pfanne',
          source: CalendarSource.canteenFavourite,
          title: 'Bulgur-Pfanne',
          start: today,
          allDay: true,
          sourceLabel: 'Mensa Köthen',
          details: const CanteenFavouriteMealCalendarDetails(
            canteenName: 'Mensa Köthen',
          ),
        );

        tester.view.physicalSize = const Size(390, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await pumpScreen(
          tester,
          const CalendarScreen(),
          overrides: <Override>[
            apiClientProvider.overrideWithValue(_emptyApi()),
            calendarDataProvider.overrideWith(
              (Ref ref, DateTime day) => CalendarData(
                entries: <CalendarEntry>[dish],
                enabledSources: const <CalendarSource>{},
              ),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.text('Bulgur-Pfanne'), findsOneWidget);

        await tester.tap(find.text('Bulgur-Pfanne'));
        await tester.pumpAndSettle();

        // Shown both on the agenda card behind the sheet (its subtitle) and
        // as the sheet's own "Quelle" row — at least one is the sheet's.
        expect(find.text('Mensa Köthen'), findsWidgets);
      },
    );
  });

  group('calendar export', () {
    testWidgets(
      'shares one .ics file built from the wide-horizon list source',
      (WidgetTester tester) async {
        final DateTime today = TimetableWeek.dayOf(DateTime.now());
        final CalendarEntry lecture = CalendarEntry(
          id: 'timetable:e1',
          source: CalendarSource.timetable,
          title: 'Mathematik 2',
          start: today.add(const Duration(hours: 9)),
          end: today.add(const Duration(hours: 10, minutes: 30)),
        );
        final List<AppDocument> shared = <AppDocument>[];

        tester.view.physicalSize = const Size(390, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await pumpScreen(
          tester,
          CalendarScreen(exportShareService: _FakeShareService(shared)),
          overrides: <Override>[
            apiClientProvider.overrideWithValue(_emptyApi()),
            calendarListDataProvider.overrideWith(
              (Ref ref, DateTime day) => CalendarData(
                entries: <CalendarEntry>[lecture],
                enabledSources: const <CalendarSource>{},
              ),
            ),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Kalender exportieren'));
        await tester.pumpAndSettle();

        expect(shared, hasLength(1));
        expect(shared.single.filename, 'campus-koethen-kalender.ics');
        expect(shared.single.mediaType, 'text/calendar');
        final String ics = utf8.decode(shared.single.bytes);
        expect(ics, contains('BEGIN:VCALENDAR'));
        expect(ics, contains('SUMMARY:Mathematik 2'));
      },
    );

    testWidgets('an empty calendar explains itself instead of sharing '
        'nothing', (WidgetTester tester) async {
      final List<AppDocument> shared = <AppDocument>[];

      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpScreen(
        tester,
        CalendarScreen(exportShareService: _FakeShareService(shared)),
        overrides: <Override>[
          apiClientProvider.overrideWithValue(_emptyApi()),
          calendarListDataProvider.overrideWith(
            (Ref ref, DateTime day) => CalendarData(
              entries: const <CalendarEntry>[],
              enabledSources: const <CalendarSource>{},
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Kalender exportieren'));
      await tester.pumpAndSettle();

      expect(shared, isEmpty);
      expect(find.text('Es gibt noch nichts zu exportieren.'), findsOneWidget);
    });
  });
}

/// The optional graphical week view.
void _weekViewTests() {
  testWidgets('the week view is offered as a third mode', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpCalendar(tester);
    expect(container.read(calendarViewModeProvider), CalendarViewMode.day);

    container
        .read(calendarViewModeProvider.notifier)
        .set(CalendarViewMode.week);
    await tester.pumpAndSettle();

    expect(find.byType(WeekGridView), findsOneWidget);
    expect(find.byType(WeekStrip), findsNothing);
  });

  testWidgets('starts on the teaching week and can take the weekend', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    final ProviderContainer container = await pumpCalendar(
      tester,
      store: store,
    );
    container
        .read(calendarViewModeProvider.notifier)
        .set(CalendarViewMode.week);
    await tester.pumpAndSettle();

    expect(
      tester.widget<WeekGridView>(find.byType(WeekGridView)).dayCount,
      5,
      reason: 'Monday to Friday by default',
    );

    // Both ranges are on screen and the active one is picked, so the control
    // says what it will do — "Wochenende" alone left open whether the weekend
    // was being shown or hidden.
    expect(find.text('Mo–Fr'), findsOneWidget);
    expect(find.text('Mo–So'), findsOneWidget);

    await tester.tap(find.text('Mo–So'));
    await tester.pumpAndSettle();

    expect(tester.widget<WeekGridView>(find.byType(WeekGridView)).dayCount, 7);
    expect(store.getInt(PreferenceKeys.calendarShowWeekend), 1);

    await tester.tap(find.text('Mo–Fr'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<WeekGridView>(find.byType(WeekGridView)).dayCount,
      5,
      reason: 'and back again — the control works in both directions',
    );
    expect(store.getInt(PreferenceKeys.calendarShowWeekend), 0);
  });

  testWidgets('the week range spells itself out for a screen reader', (
    WidgetTester tester,
  ) async {
    // "Mo–Fr" is short enough to read at a glance and too short to hear.
    final ProviderContainer container = await pumpCalendar(tester);
    container
        .read(calendarViewModeProvider.notifier)
        .set(CalendarViewMode.week);
    await tester.pumpAndSettle();

    final List<String> labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((Semantics s) => s.properties.label ?? '')
        .where((String l) => l.isNotEmpty)
        .toList(growable: false);

    expect(labels, contains('Montag bis Freitag'));
    expect(labels, contains('Montag bis Sonntag'));
  });

  testWidgets(
    'month, today action and week arrows stay in one row on a narrow phone',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final ProviderContainer container = await pumpScreen(
        tester,
        const CalendarScreen(),
        textScaler: const TextScaler.linear(2),
        overrides: <Override>[apiClientProvider.overrideWithValue(_emptyApi())],
      );
      await tester.pumpAndSettle();
      container
          .read(calendarViewModeProvider.notifier)
          .set(CalendarViewMode.week);
      await tester.pumpAndSettle();

      final String month = AppDateFormats.monthAndYear(
        container.read(calendarFocusedDayProvider),
        'de',
      );
      final Finder monthFinder = find.text(month);
      final Finder today = find.byTooltip('Heute');
      final Finder previous = find.byTooltip('Vorherige Woche');
      final Finder next = find.byTooltip('Nächste Woche');

      expect(monthFinder, findsOneWidget);
      expect(today, findsOneWidget);
      expect(previous, findsOneWidget);
      expect(next, findsOneWidget);
      expect(find.text('Heute'), findsNothing);

      final double rowCenter = tester.getCenter(monthFinder).dy;
      expect(tester.getCenter(today).dy, closeTo(rowCenter, 1));
      expect(tester.getCenter(previous).dy, closeTo(rowCenter, 1));
      expect(tester.getCenter(next).dy, closeTo(rowCenter, 1));
      expect(tester.takeException(), isNull);
    },
  );

  group('opening an entry from the agenda', () {
    CalendarEntry demoEntry(DateTime day) => CalendarEntry(
      id: 'publicCalendar:demo:1',
      source: CalendarSource.publicCalendar,
      title: 'Demotermin (fiktiv)',
      start: DateTime(day.year, day.month, day.day, 10),
      end: DateTime(day.year, day.month, day.day, 12),
      sourceLabel: 'Demokalender (fiktiv)',
      details: const PublicCalendarDetails(
        calendarName: 'Demokalender (fiktiv)',
      ),
    );

    Future<void> pumpWithEntry(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpScreen(
        tester,
        const CalendarScreen(),
        overrides: <Override>[
          apiClientProvider.overrideWithValue(_emptyApi()),
          // The day is whatever the screen focuses on first, so the entry is
          // built from it rather than from a fixed date.
          calendarDataProvider.overrideWith(
            (Ref ref, DateTime day) => CalendarData(
              entries: <CalendarEntry>[demoEntry(day)],
              enabledSources: const <CalendarSource>{
                CalendarSource.publicCalendar,
              },
              timetableLoading: false,
              hasTimetableError: false,
              needsGroup: false,
              moodleConnected: false,
              hasMoodleError: false,
              publicCalendarsLoading: false,
              hasPublicCalendarError: false,
            ),
          ),
          calendarListDataProvider.overrideWith(
            (Ref ref, DateTime day) => CalendarData(
              entries: <CalendarEntry>[demoEntry(day)],
              enabledSources: const <CalendarSource>{
                CalendarSource.publicCalendar,
              },
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the day agenda opens the details', (
      WidgetTester tester,
    ) async {
      await pumpWithEntry(tester);

      await tester.tap(find.text('Demotermin (fiktiv)'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarEntrySheet), findsOneWidget);
    });

    testWidgets('and so does the list view', (WidgetTester tester) async {
      await pumpWithEntry(tester);
      await tester.tap(find.text('Liste'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Demotermin (fiktiv)').first);
      await tester.pumpAndSettle();

      expect(find.byType(CalendarEntrySheet), findsOneWidget);
    });
  });

  group('swiping the week view', () {
    testWidgets('a swipe moves one week forward and keeps the weekday', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpCalendar(tester);
      container
          .read(calendarViewModeProvider.notifier)
          .set(CalendarViewMode.week);
      await tester.pumpAndSettle();
      final DateTime before = container.read(calendarFocusedDayProvider);

      await tester.fling(
        find.byType(WeekGridView),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();

      final DateTime after = container.read(calendarFocusedDayProvider);
      expect(after.difference(before).inDays, 7);
      expect(after.weekday, before.weekday);
    });

    testWidgets('and back the other way', (WidgetTester tester) async {
      final ProviderContainer container = await pumpCalendar(tester);
      container
          .read(calendarViewModeProvider.notifier)
          .set(CalendarViewMode.week);
      await tester.pumpAndSettle();
      final DateTime before = container.read(calendarFocusedDayProvider);

      await tester.fling(find.byType(WeekGridView), const Offset(200, 0), 1000);
      await tester.pumpAndSettle();

      final DateTime after = container.read(calendarFocusedDayProvider);
      expect(after.difference(before).inDays, -7);
      expect(after.weekday, before.weekday);
    });

    testWidgets('a vertical swipe scrolls the hours, not the weeks', (
      WidgetTester tester,
    ) async {
      // The grid spans the whole day and is scrolled through vertically. That
      // gesture lives inside the same widget as the week swipe, and moving
      // through the afternoon must not skip the reader into the next week.
      final ProviderContainer container = await pumpCalendar(tester);
      container
          .read(calendarViewModeProvider.notifier)
          .set(CalendarViewMode.week);
      await tester.pumpAndSettle();
      final DateTime before = container.read(calendarFocusedDayProvider);
      final ScrollableState hours = tester.state(
        find
            .byWidgetPredicate(
              (Widget widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      final double scrolledTo = hours.position.pixels;

      await tester.fling(find.byType(WeekGridView), const Offset(0, -300), 800);
      await tester.pumpAndSettle();

      expect(container.read(calendarFocusedDayProvider), before);
      expect(hours.position.pixels, greaterThan(scrolledTo));
    });

    testWidgets('what the swipe picks is what the grid then shows', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpCalendar(tester);
      container
          .read(calendarViewModeProvider.notifier)
          .set(CalendarViewMode.week);
      await tester.pumpAndSettle();
      final DateTime beforeStart = tester
          .widget<WeekGridView>(find.byType(WeekGridView))
          .weekStart;

      await tester.fling(
        find.byType(WeekGridView),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();

      final DateTime afterStart = tester
          .widget<WeekGridView>(find.byType(WeekGridView))
          .weekStart;
      expect(afterStart.difference(beforeStart).inDays, 7);
    });
  });

  testWidgets('the grid starts on a Monday', (WidgetTester tester) async {
    final ProviderContainer container = await pumpCalendar(tester);
    container
        .read(calendarViewModeProvider.notifier)
        .set(CalendarViewMode.week);
    await tester.pumpAndSettle();

    final WeekGridView grid = tester.widget<WeekGridView>(
      find.byType(WeekGridView),
    );
    expect(grid.weekStart.weekday, DateTime.monday);
  });

  testWidgets('picking a day in the grid opens that day', (
    WidgetTester tester,
  ) async {
    // The week answers "how is my week shaped"; the day answers "what is on".
    final ProviderContainer container = await pumpCalendar(tester);
    container
        .read(calendarViewModeProvider.notifier)
        .set(CalendarViewMode.week);
    await tester.pumpAndSettle();

    final WeekGridView grid = tester.widget<WeekGridView>(
      find.byType(WeekGridView),
    );
    final DateTime target = grid.weekStart.add(const Duration(days: 3));
    grid.onSelectDay(target);
    await tester.pumpAndSettle();

    expect(container.read(calendarViewModeProvider), CalendarViewMode.day);
    expect(container.read(calendarFocusedDayProvider).day, target.day);
  });

  testWidgets('the week survives a narrow phone with doubled text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final ProviderContainer container = await pumpScreen(
      tester,
      const CalendarScreen(),
      textScaler: const TextScaler.linear(2),
      overrides: <Override>[apiClientProvider.overrideWithValue(_emptyApi())],
    );
    await tester.pumpAndSettle();
    container
        .read(calendarViewModeProvider.notifier)
        .set(CalendarViewMode.week);
    await tester.pumpAndSettle();

    // The columns share whatever width is left rather than overflowing.
    expect(tester.takeException(), isNull);
  });
}
