// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The detail view of one calendar entry — and which of its text may become a
/// link to a room.
///
/// The room rules are the point of most of these: a timetable's room field is a
/// room, a public calendar's description is prose, and a link that leads to the
/// wrong door is worse than no link at all.
library;

import 'package:campus_koethen/core/content/content_block.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/api_client.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/theme/app_dimensions.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry_details.dart';
import 'package:campus_koethen/features/calendar/presentation/calendar_entry_sheet.dart';
import 'package:campus_koethen/features/campusmap/application/campus_map_providers.dart';
import 'package:campus_koethen/features/campusmap/data/map_asset_loader.dart';
import 'package:campus_koethen/features/campusmap/domain/map_catalog.dart';
import 'package:campus_koethen/features/events/application/event_providers.dart';
import 'package:campus_koethen/features/events/data/event_posts_repository.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/fake_http_adapter.dart';
import '../../support/news_harness.dart';
import '../../support/pump_app.dart';

/// The real bundled catalogue, so "is this room on the map" is answered by the
/// same asset the app ships.
late final MapCatalog testCatalog;

/// A room that exists in the bundled plan, and the number people write for it.
late final String mappedRoomNumber;
late final String mappedRoomKey;

Map<String, dynamic> roomJson(String roomKey, String roomNumber) =>
    <String, dynamic>{
      'roomKey': roomKey,
      'roomNumber': roomNumber,
      'buildingKey': 'test-building',
      'buildingName': 'Testgebäude',
      'floorKey': 'test-building-level2',
      'floorName': '2. Obergeschoss',
      'roomType': 'office',
      'mapVersion': 'demo-1',
      'sortOrder': 0,
    };

ApiClient _api(List<Map<String, dynamic>> rooms) => fakeApiClient(
  FakeHttpAdapter((RequestOptions options) {
    if (options.path.contains('/rooms')) {
      return FakeHttpResponse(envelope(rooms));
    }
    return FakeHttpResponse(envelope(<Object>[]));
  }),
);

Future<void> pumpSheet(
  WidgetTester tester,
  CalendarEntry entry, {
  List<Map<String, dynamic>>? rooms,
  Locale locale = AppLocales.german,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await pumpScreen(
    tester,
    Scaffold(body: CalendarEntrySheet(entry: entry)),
    locale: locale,
    textScaler: textScaler,
    overrides: <Override>[
      apiClientProvider.overrideWithValue(
        _api(
          rooms ??
              <Map<String, dynamic>>[roomJson(mappedRoomKey, mappedRoomNumber)],
        ),
      ),
      mapCatalogProvider.overrideWith((Ref ref) => testCatalog),
    ],
  );
  await tester.pumpAndSettle();
}

CalendarEntry timetableEntry({
  List<String> rooms = const <String>[],
  String? note,
  String? lessonInfo,
  TimetableEntryStatus status = TimetableEntryStatus.regular,
}) => CalendarEntry(
  id: 'timetable:1',
  source: CalendarSource.timetable,
  title: 'Demo-Vorlesung (fiktiv)',
  start: DateTime(2026, 5, 11, 10),
  end: DateTime(2026, 5, 11, 11, 30),
  isCancelled: status == TimetableEntryStatus.cancelled,
  details: TimetableCalendarDetails(
    type: TimetableEntryType.regularTeaching,
    status: status,
    teachers: const <String>['Demoperson'],
    rooms: rooms,
    groups: const <String>['DEMO-1'],
    note: note,
    lessonInfo: lessonInfo,
  ),
);

CalendarEntry publicEntry({String? location, String? description}) =>
    CalendarEntry(
      id: 'publicCalendar:demo:1',
      source: CalendarSource.publicCalendar,
      title: 'Demo-Veranstaltung (fiktiv)',
      start: DateTime(2026, 5, 11, 18),
      end: DateTime(2026, 5, 11, 20),
      sourceLabel: 'Demokalender (fiktiv)',
      location: location,
      subtitle: description,
      details: PublicCalendarDetails(
        calendarName: 'Demokalender (fiktiv)',
        location: location,
        description: description,
      ),
    );

NewsArticle eventPost() => NewsArticle(
  slug: 'sommerfest',
  title: 'Sommerfest',
  tag: const NewsTagRef(slug: 'event', name: 'Event'),
  primaryChannel: const NewsChannelRef(slug: 'stura', name: 'StuRa'),
  channels: const <NewsChannelRef>[
    NewsChannelRef(slug: 'stura', name: 'StuRa'),
  ],
  content: <ContentBlock>[
    ParagraphBlock(<InlineNode>[
      const InlineText(text: 'Der vollständige Beitrag.'),
    ]),
  ],
  eventStart: DateTime(2026, 5, 11, 18),
);

Future<void> pumpPopup(
  WidgetTester tester,
  CalendarEntry entry, {
  List<NewsArticle> eventPosts = const <NewsArticle>[],
}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await pumpScreen(
    tester,
    Scaffold(
      body: Builder(
        builder: (BuildContext context) => FilledButton(
          onPressed: () => showCalendarEntrySheet(context, entry),
          child: const Text('Öffnen'),
        ),
      ),
    ),
    overrides: <Override>[
      frozenNewsClock(),
      eventPostsOverviewProvider.overrideWith(
        (Ref ref) async => EventPostsResult(
          articles: eventPosts,
          isTruncated: false,
          from: '2026-05-01',
          to: '2026-05-31',
        ),
      ),
      apiClientProvider.overrideWithValue(_api(const <Map<String, dynamic>>[])),
      mapCatalogProvider.overrideWith((Ref ref) => testCatalog),
    ],
  );
  await tester.tap(find.text('Öffnen'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    testCatalog = await const MapAssetLoader().load();
    final MapRoomGeometry sample = testCatalog.rooms.first;
    mappedRoomKey = sample.roomKey;
    // The catalogue keys are `<building>-<floor>-<number>`; the number as
    // written on the door is the last segment.
    mappedRoomNumber = mappedRoomKey.split('-').last.toUpperCase();
  });

  group('a timetable slot', () {
    testWidgets('shows what the agenda line left out', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        timetableEntry(
          rooms: <String>['X.999'],
          note: 'Bitte Laptop mitbringen',
          lessonInfo: 'Fiktive Information zur Stunde',
        ),
      );

      expect(find.text('Demo-Vorlesung (fiktiv)'), findsOneWidget);
      expect(find.text('Demoperson'), findsOneWidget);
      expect(find.text('DEMO-1'), findsOneWidget);
      expect(find.text('Bitte Laptop mitbringen'), findsOneWidget);
      expect(find.text('Information zur Stunde'), findsOneWidget);
      expect(find.text('Fiktive Information zur Stunde'), findsOneWidget);
      expect(find.text('Stundenplan'), findsOneWidget);
    });

    testWidgets('offers the room when the plan knows it', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        timetableEntry(rooms: <String>[mappedRoomNumber]),
      );

      expect(
        find.textContaining('auf dem Plan'),
        findsOneWidget,
        reason: 'the room field of a timetable slot is a room',
      );
      expect(find.widgetWithText(OutlinedButton, 'Raum suchen'), findsNothing);
    });

    testWidgets('offers room search for a room the catalogue does not have', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, timetableEntry(rooms: <String>['X.999']));

      expect(find.textContaining('auf dem Plan'), findsNothing);
      expect(find.text('X.999'), findsOneWidget);
      final Finder searchButton = find.widgetWithText(
        OutlinedButton,
        'Raum suchen',
      );
      expect(searchButton, findsOneWidget);
      expect(
        tester.getTopLeft(searchButton).dx,
        greaterThan(tester.getTopRight(find.text('X.999')).dx),
      );
      expect(
        (tester.getCenter(searchButton).dy -
                tester.getCenter(find.text('X.999')).dy)
            .abs(),
        lessThan(25),
      );
    });

    testWidgets('states a cancellation in words, not by strikethrough alone', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        timetableEntry(status: TimetableEntryStatus.cancelled),
      );

      expect(find.text('Fällt aus'), findsOneWidget);
      expect(find.byIcon(AppIcons.event_busy_outlined), findsOneWidget);
    });
  });

  group('an event from a public calendar', () {
    testWidgets('shows its calendar, place and description', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        publicEntry(
          location: 'Innenhof',
          description: 'Offen für alle Studierenden.',
        ),
      );

      expect(find.text('Demokalender (fiktiv)'), findsOneWidget);
      expect(find.text('Innenhof'), findsOneWidget);
      expect(find.text('Offen für alle Studierenden.'), findsOneWidget);
    });

    testWidgets('keeps a numeric Ratke room in prose unlinked', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        publicEntry(description: 'Treffpunkt ist Raum $mappedRoomNumber.'),
      );

      // More buildings will follow. A numeric room in prose therefore stays
      // plain text because the same number may later exist elsewhere too.
      expect(find.textContaining('auf dem Plan'), findsNothing);
      expect(find.textContaining('Raum $mappedRoomNumber'), findsOneWidget);
    });

    testWidgets('never turns a bare number in prose into a room', (
      WidgetTester tester,
    ) async {
      // "202" in a sentence is a year, a price, a course number — anything.
      // Linking it would walk somebody to a door chosen by coincidence.
      final String bare = mappedRoomNumber.replaceAll(
        RegExp(r'^[A-Za-z]+\.?'),
        '',
      );
      await pumpSheet(
        tester,
        publicEntry(description: 'Wir treffen uns um $bare Uhr am Eingang.'),
      );

      expect(find.textContaining('auf dem Plan'), findsNothing);
    });
  });

  group('a saved event in the calendar', () {
    testWidgets('opens the full post when the saved source is a post', (
      WidgetTester tester,
    ) async {
      await pumpPopup(
        tester,
        CalendarEntry(
          id: 'savedEvent:post:sommerfest',
          source: CalendarSource.savedEvents,
          title: 'Sommerfest',
          start: DateTime(2026, 5, 11, 18),
          sourceLabel: '@StuRa',
        ),
        eventPosts: <NewsArticle>[eventPost()],
      );

      expect(find.text('Der vollständige Beitrag.'), findsOneWidget);
      expect(find.byType(CalendarEntrySheet), findsNothing);
    });

    testWidgets('keeps the event details for a saved calendar event', (
      WidgetTester tester,
    ) async {
      await pumpPopup(
        tester,
        CalendarEntry(
          id: 'savedEvent:calendar:termin-1',
          source: CalendarSource.savedEvents,
          title: 'Kalendertermin',
          start: DateTime(2026, 5, 11, 18),
          sourceLabel: 'StuRa-Termine',
        ),
      );

      expect(find.byType(CalendarEntrySheet), findsOneWidget);
      expect(find.text('Kalendertermin'), findsOneWidget);
    });

    testWidgets('falls back to saved details when the post is unavailable', (
      WidgetTester tester,
    ) async {
      await pumpPopup(
        tester,
        CalendarEntry(
          id: 'savedEvent:post:nicht-mehr-verfuegbar',
          source: CalendarSource.savedEvents,
          title: 'Gespeicherter Beitrag',
          start: DateTime(2026, 5, 11, 18),
          sourceLabel: '@StuRa',
        ),
      );

      expect(find.byType(CalendarEntrySheet), findsOneWidget);
      expect(find.text('Gespeicherter Beitrag'), findsOneWidget);
    });
  });

  testWidgets('an Exchange appointment shows a place that is not a room', (
    WidgetTester tester,
  ) async {
    await pumpSheet(
      tester,
      CalendarEntry(
        id: 'exchange:1',
        source: CalendarSource.exchangeCalendar,
        title: 'Sprechstunde (fiktiv)',
        start: DateTime(2026, 5, 11, 14),
        end: DateTime(2026, 5, 11, 15),
        location: 'Online',
        details: const ExchangeCalendarDetails(location: 'Online'),
      ),
    );

    expect(find.text('Ort'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('an entry without details still shows everything it has', (
    WidgetTester tester,
  ) async {
    // The shape an entry has before a source fills in its details.
    await pumpSheet(
      tester,
      CalendarEntry(
        id: 'x',
        source: CalendarSource.moodle,
        title: 'Abgabe',
        start: DateTime(2026, 5, 11, 23, 59),
        subtitle: 'Demokurs (fiktiv)',
      ),
    );

    expect(find.text('Abgabe'), findsOneWidget);
    expect(find.text('Demokurs (fiktiv)'), findsOneWidget);
    expect(find.text('Moodle'), findsOneWidget);
  });

  group('accessibility and i18n', () {
    testWidgets('survives doubled text without overflowing', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        timetableEntry(
          rooms: <String>[mappedRoomNumber],
          note: 'Ein längerer Hinweis, der über mehrere Zeilen läuft.',
        ),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders its own labels in English', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        timetableEntry(rooms: <String>[mappedRoomNumber]),
        locale: AppLocales.english,
      );

      expect(find.text('When'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      // The entry's own words stay as the source wrote them.
      expect(find.text('Demo-Vorlesung (fiktiv)'), findsOneWidget);
      expect(find.text('Demoperson'), findsOneWidget);
    });

    testWidgets('the room link is a real, labelled target', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        timetableEntry(rooms: <String>[mappedRoomNumber]),
      );

      final Finder button = find.byType(OutlinedButton);
      expect(button, findsOneWidget);
      expect(
        tester.getSize(button).height,
        greaterThanOrEqualTo(AppSizes.minTouchTarget),
      );
    });
  });
}
