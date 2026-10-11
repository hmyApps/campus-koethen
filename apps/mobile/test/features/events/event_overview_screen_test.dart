// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/time/clock.dart';
import 'package:campus_koethen/core/widgets/offline_notice.dart';
import 'package:campus_koethen/core/widgets/state_views.dart';
import 'package:campus_koethen/features/calendar/domain/public_calendar.dart';
import 'package:campus_koethen/features/events/application/event_providers.dart';
import 'package:campus_koethen/features/events/application/event_source_filter.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/data/event_posts_repository.dart';
import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:campus_koethen/features/events/presentation/event_overview_screen.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

/// A fixed "now": every visibility boundary in these tests is expressed
/// relative to it, so nothing depends on the wall clock.
final DateTime _now = DateTime.utc(2026, 9, 1, 12);

class _FixedClock implements Clock {
  const _FixedClock();
  @override
  DateTime now() => _now;
}

/// Pins the overview's "now" without arming the real boundary timer. The
/// scheduler itself has its own test (`event_visibility_scheduler_test.dart`);
/// letting it run here would only leave a 26-hour timer pending at teardown.
class _StaticOverviewClock extends EventOverviewClockController {
  @override
  DateTime build() => _now;
}

const List<EventSourceOption> _options = <EventSourceOption>[
  EventSourceOption(key: 'campus-events', label: 'Campus Events'),
  EventSourceOption(key: 'kultur', label: 'Kultur'),
];

UnifiedEvent _event({
  String ref = 'calendar:a',
  String title = 'Sommerfest',
  String channel = 'campus-events',
  DateTime? start,
  DateTime? end,
  String? description,
  String? location,
  bool isCancelled = false,
}) => UnifiedEvent(
  eventRef: ref,
  kind: UnifiedEventKind.calendarEvent,
  title: title,
  start: start ?? _now.add(const Duration(days: 1)),
  end: end ?? _now.add(const Duration(days: 1, hours: 2)),
  channelSlug: channel,
  calendarSlug: 'stura-termine',
  sourceLabel: 'Campus Events',
  description: description,
  location: location,
  isCancelled: isCancelled,
);

EventPostsResult _postsResult({
  bool fromCache = false,
  bool isTruncated = false,
}) => EventPostsResult(
  articles: const <NewsArticle>[],
  isTruncated: isTruncated,
  from: '2026-09-01',
  to: '2026-10-01',
  fromCache: fromCache,
  cachedAt: fromCache ? _now.subtract(const Duration(hours: 3)) : null,
);

Loaded<List<PublicCalendarEvent>> _calendarsResult({
  bool fromCache = false,
  bool truncated = false,
}) => Loaded<List<PublicCalendarEvent>>(
  value: const <PublicCalendarEvent>[],
  meta: ApiMeta(from: '2026-09-01', to: '2026-10-01', truncated: truncated),
  fromCache: fromCache,
);

/// Never-completing future — the honest way to hold a provider in `loading`.
Future<T> _pending<T>() => Completer<T>().future;

Future<ProviderContainer> _pumpOverview(
  WidgetTester tester, {
  List<UnifiedEvent> events = const <UnifiedEvent>[],
  List<SavedEventSnapshot> saved = const <SavedEventSnapshot>[],
  AsyncValue<EventPostsResult>? posts,
  AsyncValue<Loaded<List<PublicCalendarEvent>>>? calendars,
  Set<String> selected = const <String>{'campus-events', 'kultur'},
  List<EventSourceOption> options = _options,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  Size? surfaceSize,
  Locale locale = const Locale('de'),
}) async {
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  final MemorySavedEventsStore store = MemorySavedEventsStore();
  await store.writeAll(saved);

  final AsyncValue<EventPostsResult> postsValue =
      posts ?? AsyncData<EventPostsResult>(_postsResult());
  final AsyncValue<Loaded<List<PublicCalendarEvent>>> calendarsValue =
      calendars ??
      AsyncData<Loaded<List<PublicCalendarEvent>>>(_calendarsResult());

  Future<T> resolve<T>(AsyncValue<T> value) => switch (value) {
    AsyncData<T>(:final T value) => Future<T>.value(value),
    AsyncError<T>(:final Object error) => Future<T>.error(error),
    _ => _pending<T>(),
  };

  return pumpScreen(
    tester,
    const EventOverviewScreen(),
    locale: locale,
    themeMode: themeMode,
    textScaler: textScaler,
    keyValueStore: InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.eventSourceStoreVersion:
          PreferenceKeys.eventSourceStoreCurrentVersion,
      PreferenceKeys.eventSourceSeenKeys: options
          .map((EventSourceOption o) => o.key)
          .toList(),
      PreferenceKeys.eventSourceSelectedKeys: selected.toList(),
    }),
    overrides: <Override>[
      eventsClockProvider.overrideWithValue(const _FixedClock()),
      eventOverviewClockProvider.overrideWith(_StaticOverviewClock.new),
      savedEventsClockProvider.overrideWithValue(() => _now),
      savedEventsStoreProvider.overrideWithValue(store),
      eventSourceOptionsProvider.overrideWith((Ref ref) async => options),
      eventPostsOverviewProvider.overrideWith((Ref ref) => resolve(postsValue)),
      eventCalendarsOverviewProvider.overrideWith(
        (Ref ref) => resolve(calendarsValue),
      ),
      rawUnifiedEventsProvider.overrideWithValue(events),
    ],
  );
}

void main() {
  group('overview states', () {
    testWidgets('renders a linked calendar event without an @ source marker', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(tester, events: <UnifiedEvent>[_event()]);
      await tester.pumpAndSettle();

      expect(find.text('Events'), findsWidgets);
      expect(find.text('Sommerfest'), findsOneWidget);
      expect(find.text('Campus Events'), findsWidgets);
      expect(find.text('@Campus Events'), findsNothing);
      expect(find.byType(EmptyView), findsNothing);
    });

    testWidgets('renders a post event with an @ channel source marker', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[
          UnifiedEvent(
            eventRef: 'post:summer-party',
            kind: UnifiedEventKind.postEvent,
            title: 'Sommerfest als Post',
            start: _now.add(const Duration(days: 1)),
            channelSlug: 'campus-events',
            sourceLabel: 'Campus Events',
            postSlug: 'summer-party',
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Campus Events'), findsOneWidget);
    });

    testWidgets('shows the loading view while both sources are still pending', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        posts: const AsyncLoading<EventPostsResult>(),
        calendars: const AsyncLoading<Loaded<List<PublicCalendarEvent>>>(),
      );
      await tester.pump();

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing);
    });

    testWidgets('an empty result explains itself instead of showing nothing', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(tester);
      await tester.pumpAndSettle();

      expect(find.text('Keine anstehenden Events'), findsOneWidget);
    });

    testWidgets('deselecting every source is its own empty state with a way '
        'back to the filter', (WidgetTester tester) async {
      await _pumpOverview(tester, selected: const <String>{});
      await tester.pumpAndSettle();

      expect(find.text('Keine Quellen ausgewählt'), findsOneWidget);
      expect(find.text('Quellen auswählen'), findsOneWidget);
      expect(find.text('Keine anstehenden Events'), findsNothing);
    });

    testWidgets('one failing source keeps the other visible and offers a '
        'source-specific retry', (WidgetTester tester) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        posts: AsyncError<EventPostsResult>(
          Exception('boom'),
          StackTrace.empty,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sommerfest'), findsOneWidget);
      expect(
        find.text('Event-Beiträge sind derzeit nicht verfügbar.'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing);
    });

    testWidgets('a refresh that fails again raises no unhandled error', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        posts: AsyncError<EventPostsResult>(
          Exception('boom'),
          StackTrace.empty,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Aktualisieren'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Event-Beiträge sind derzeit nicht verfügbar.'),
        findsOneWidget,
      );
    });

    testWidgets('the calendar source failing names the calendar source', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        calendars: AsyncError<Loaded<List<PublicCalendarEvent>>>(
          Exception('boom'),
          StackTrace.empty,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Kalender-Events sind derzeit nicht verfügbar.'),
        findsOneWidget,
      );
    });

    testWidgets('only both sources failing with no data is a total failure', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        posts: AsyncError<EventPostsResult>(
          Exception('boom'),
          StackTrace.empty,
        ),
        calendars: AsyncError<Loaded<List<PublicCalendarEvent>>>(
          Exception('boom'),
          StackTrace.empty,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
    });

    testWidgets('cached posts are labelled as offline content', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        posts: AsyncData<EventPostsResult>(_postsResult(fromCache: true)),
      );
      await tester.pumpAndSettle();

      // Cached content is always labelled; the notice's own timestamp
      // formatting is covered by its dedicated test.
      expect(find.byType(OfflineNotice), findsOneWidget);
    });

    testWidgets('a truncated posts load is reported, not silently cut', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        posts: AsyncData<EventPostsResult>(_postsResult(isTruncated: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nicht alle Events werden angezeigt'), findsOneWidget);
    });

    testWidgets('a server-truncated calendar load raises the same banner', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        calendars: AsyncData<Loaded<List<PublicCalendarEvent>>>(
          _calendarsResult(truncated: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nicht alle Events werden angezeigt'), findsOneWidget);
    });

    testWidgets('an event whose end has passed is no longer visible', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[
          _event(
            ref: 'calendar:over',
            title: 'Schon vorbei',
            start: _now.subtract(const Duration(hours: 4)),
            end: _now.subtract(const Duration(hours: 1)),
          ),
          _event(ref: 'calendar:next', title: 'Kommt noch'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Schon vorbei'), findsNothing);
      expect(find.text('Kommt noch'), findsOneWidget);
    });

    testWidgets('an unselected source is filtered out of the list', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        selected: const <String>{'campus-events'},
        events: <UnifiedEvent>[
          _event(ref: 'calendar:a', title: 'Campus-Event'),
          _event(ref: 'calendar:b', title: 'Kultur-Event', channel: 'kultur'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Campus-Event'), findsOneWidget);
      expect(find.text('Kultur-Event'), findsNothing);
    });
  });

  group('saved list', () {
    SavedEventSnapshot snapshot({
      String ref = 'calendar:a',
      String title = 'Gemerkt',
      DateTime? start,
      DateTime? end,
      bool isOrphaned = false,
      String? location,
      String? description,
    }) => SavedEventSnapshot(
      eventRef: ref,
      kind: UnifiedEventKind.calendarEvent,
      title: title,
      start: start ?? _now.add(const Duration(days: 2)),
      end: end ?? _now.add(const Duration(days: 2, hours: 1)),
      sourceLabel: 'Campus Events',
      location: location,
      description: description,
      isOrphaned: isOrphaned,
      savedAt: _now,
    );

    Future<void> openSaved(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Gemerkte Events anzeigen'));
      await tester.pumpAndSettle();
    }

    testWidgets('an empty saved list explains itself and offers a way back', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(tester);
      await openSaved(tester);

      expect(find.text('Keine gemerkten Events'), findsWidgets);
      expect(find.text('Alle Events anzeigen'), findsWidgets);
    });

    testWidgets('past saved events get their own section and a Vergangen '
        'label, upcoming ones do not', (WidgetTester tester) async {
      await _pumpOverview(
        tester,
        saved: <SavedEventSnapshot>[
          snapshot(ref: 'calendar:next', title: 'Kommt noch'),
          snapshot(
            ref: 'calendar:old',
            title: 'War mal',
            start: _now.subtract(const Duration(days: 3)),
            end: _now.subtract(const Duration(days: 3)),
          ),
        ],
      );
      await openSaved(tester);

      expect(find.text('Vergangene Events'), findsOneWidget);
      expect(find.text('Kommt noch'), findsOneWidget);
      expect(find.text('War mal'), findsOneWidget);
      expect(find.text('Vergangen'), findsOneWidget);
    });

    testWidgets('orphaned is shown independently of vergangen', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        saved: <SavedEventSnapshot>[
          snapshot(
            ref: 'calendar:gone',
            title: 'Verschwunden',
            isOrphaned: true,
          ),
        ],
      );
      await openSaved(tester);

      expect(find.text('Nicht mehr verfügbar'), findsOneWidget);
      expect(find.text('Vergangen'), findsNothing);
      expect(find.text('Vergangene Events'), findsNothing);
    });

    testWidgets('a saved snapshot keeps its location and description offline', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        saved: <SavedEventSnapshot>[
          snapshot(location: 'Raum 1.02', description: 'Tagesordnung folgt'),
        ],
      );
      await openSaved(tester);

      // Regression for LEVIORA-115 F2: these were dropped at save time, so the
      // saved card showed neither the place nor an expandable description.
      expect(find.text('Raum 1.02'), findsOneWidget);
      expect(find.text('Mehr anzeigen'), findsOneWidget);
    });
  });

  group('presentation', () {
    testWidgets('renders under large text scaling without overflowing', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[
          _event(description: 'Eine ausführliche Beschreibung.'),
        ],
        textScaler: const TextScaler.linear(2),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sommerfest'), findsOneWidget);
    });

    testWidgets('renders on a narrow phone surface', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        surfaceSize: const Size(320, 640),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sommerfest'), findsOneWidget);
    });

    testWidgets('renders on a wide tablet surface', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        surfaceSize: const Size(1024, 1366),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sommerfest'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (WidgetTester tester) async {
      await _pumpOverview(
        tester,
        events: <UnifiedEvent>[_event()],
        themeMode: ThemeMode.dark,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sommerfest'), findsOneWidget);
    });

    testWidgets('renders English localisation', (WidgetTester tester) async {
      await _pumpOverview(tester, locale: const Locale('en'));
      await tester.pumpAndSettle();

      expect(find.text('No upcoming events'), findsOneWidget);
    });

    testWidgets('the header actions carry tooltips and 48dp touch targets', (
      WidgetTester tester,
    ) async {
      await _pumpOverview(tester, events: <UnifiedEvent>[_event()]);
      await tester.pumpAndSettle();

      for (final String tooltip in <String>[
        'Gemerkte Events anzeigen',
        'Quellen filtern',
      ]) {
        final Finder button = find.byTooltip(tooltip);
        expect(button, findsOneWidget);
        final Size size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });
  });
}
