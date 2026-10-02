// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/content/content_block.dart';
import 'package:campus_koethen/core/links/linkified_text.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:campus_koethen/features/events/presentation/event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

ParagraphBlock _p(String text) =>
    ParagraphBlock(<InlineNode>[InlineText(text: text)]);

UnifiedEvent _postEvent({
  String eventRef = 'post:a',
  String title = 'Sommerfest',
  String? location,
}) => UnifiedEvent(
  eventRef: eventRef,
  kind: UnifiedEventKind.postEvent,
  title: title,
  start: DateTime.utc(2026, 8, 10, 18),
  channelSlug: 'campus-events',
  sourceLabel: 'Campus Events',
  postSlug: eventRef.split(':').last,
  location: location,
);

UnifiedEvent _calendarEvent({
  String? description,
  String? location,
  bool isCancelled = false,
  String? channelSlug = 'campus-events',
}) => UnifiedEvent(
  eventRef: 'calendar:abc',
  kind: UnifiedEventKind.calendarEvent,
  title: 'StuRa-Sitzung',
  start: DateTime.utc(2026, 9, 1, 16),
  end: DateTime.utc(2026, 9, 1, 18),
  channelSlug: channelSlug,
  calendarSlug: 'stura-termine',
  sourceLabel: 'StuRa-Termine',
  description: description,
  location: location,
  isCancelled: isCancelled,
);

Future<void> _pumpCard(
  WidgetTester tester,
  UnifiedEvent event, {
  List<ContentBlock>? content,
  bool isPast = false,
  bool isOrphaned = false,
  SavedEventsStore? store,
  List<Override> overrides = const <Override>[],
}) async {
  await pumpScreen(
    tester,
    Scaffold(
      body: ListView(
        children: <Widget>[
          EventCard(
            event: event,
            content: content,
            isPast: isPast,
            isOrphaned: isOrphaned,
          ),
        ],
      ),
    ),
    overrides: <Override>[
      savedEventsStoreProvider.overrideWithValue(
        store ?? MemorySavedEventsStore(),
      ),
      savedEventsClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 1),
      ),
      ...overrides,
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows title and source, without an expand action by default', (
    WidgetTester tester,
  ) async {
    await _pumpCard(tester, _postEvent());

    expect(find.text('Sommerfest'), findsOneWidget);
    expect(find.text('Campus Events'), findsOneWidget);
    expect(find.text('Mehr anzeigen'), findsNothing);
  });

  testWidgets('leaves a calendar source unchanged even when it has a channel', (
    WidgetTester tester,
  ) async {
    await _pumpCard(tester, _calendarEvent());

    expect(find.text('StuRa-Termine'), findsOneWidget);
    expect(find.text('@StuRa-Termine'), findsNothing);
  });

  testWidgets('a description offers Mehr/Weniger anzeigen and toggles', (
    WidgetTester tester,
  ) async {
    await _pumpCard(
      tester,
      _postEvent(),
      content: <ContentBlock>[_p('Ein langer Beschreibungstext.')],
    );

    expect(find.text('Ein langer Beschreibungstext.'), findsNothing);
    expect(find.text('Mehr anzeigen'), findsOneWidget);

    await tester.tap(find.text('Mehr anzeigen'));
    await tester.pumpAndSettle();

    expect(find.text('Ein langer Beschreibungstext.'), findsOneWidget);
    expect(find.text('Weniger anzeigen'), findsOneWidget);
  });

  testWidgets('tapping the card body toggles the description, tapping the save '
      'button never does', (WidgetTester tester) async {
    await _pumpCard(tester, _postEvent(), content: <ContentBlock>[_p('Text.')]);

    await tester.tap(find.byType(EventCard));
    await tester.pumpAndSettle();
    expect(find.text('Text.'), findsOneWidget);

    await tester.tap(find.byTooltip('Event merken'));
    await tester.pumpAndSettle();
    // The description stays open — the save action never toggles it.
    expect(find.text('Text.'), findsOneWidget);
  });

  testWidgets('the save button toggles merken/entmerken with an immediate '
      'visual state', (WidgetTester tester) async {
    await _pumpCard(tester, _postEvent());

    expect(find.byTooltip('Event merken'), findsOneWidget);
    await tester.tap(find.byTooltip('Event merken'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Event nicht mehr merken'), findsOneWidget);

    await tester.tap(find.byTooltip('Event nicht mehr merken'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Event merken'), findsOneWidget);
  });

  testWidgets('a failed save stays unsaved and shows a storage error', (
    WidgetTester tester,
  ) async {
    await _pumpCard(
      tester,
      _postEvent(),
      store: _WriteFailingSavedEventsStore(),
    );

    await tester.tap(find.byTooltip('Event merken'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Event merken'), findsOneWidget);
    expect(
      find.text(
        'Das Event konnte nicht auf diesem Gerät gespeichert werden. '
        'Versuche es erneut.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows a location line when the event has one', (
    WidgetTester tester,
  ) async {
    await _pumpCard(tester, _postEvent(location: 'Hörsaal 1'));
    expect(find.text('Hörsaal 1'), findsOneWidget);
  });

  testWidgets('past and orphaned badges are shown as distinct labels', (
    WidgetTester tester,
  ) async {
    await _pumpCard(tester, _postEvent(), isPast: true, isOrphaned: true);
    expect(find.text('Vergangen'), findsOneWidget);
    expect(find.text('Nicht mehr verfügbar'), findsOneWidget);
  });

  testWidgets('a cancelled event is marked in words, not only by styling', (
    WidgetTester tester,
  ) async {
    // Regression for LEVIORA-115 F4: the calendar screen struck cancelled
    // entries through, the event card showed them as ordinary appointments.
    await _pumpCard(tester, _calendarEvent(isCancelled: true));

    expect(find.text('Abgesagt'), findsOneWidget);
    final Text title = tester.widget<Text>(find.text('StuRa-Sitzung'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('a confirmed event carries no cancellation marker', (
    WidgetTester tester,
  ) async {
    await _pumpCard(tester, _calendarEvent());

    expect(find.text('Abgesagt'), findsNothing);
    final Text title = tester.widget<Text>(find.text('StuRa-Sitzung'));
    expect(title.style?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('a URL in a calendar description is rendered through the safe '
      'link component', (WidgetTester tester) async {
    // Regression for LEVIORA-115 F3: the plain-text branch used a bare `Text`,
    // so a link in a Google calendar description could not even be selected.
    await _pumpCard(
      tester,
      _calendarEvent(description: 'Tagesordnung unter https://example.test/to'),
    );

    await tester.tap(find.text('Mehr anzeigen'));
    await tester.pumpAndSettle();

    expect(find.byType(LinkifiedText), findsOneWidget);
  });

  testWidgets('renders English localisation', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: ListView(children: <Widget>[EventCard(event: _postEvent())]),
      ),
      locale: AppLocales.english,
      overrides: <Override>[
        savedEventsStoreProvider.overrideWithValue(MemorySavedEventsStore()),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Save event'), findsOneWidget);
  });
}

class _WriteFailingSavedEventsStore extends MemorySavedEventsStore {
  @override
  Future<void> upsert(SavedEventSnapshot snapshot) async =>
      throw SavedEventsStoreFailure(
        SavedEventsStoreOperation.write,
        StateError('failed'),
      );
}
