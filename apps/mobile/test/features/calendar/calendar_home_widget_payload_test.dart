// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/home_widget/calendar_home_widget_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime(2026, 10, 4, 10);

  CalendarEntry entry(
    String id,
    DateTime start, {
    DateTime? end,
    bool allDay = false,
    String title = 'Diskrete Mathematik',
    String? location = 'Raum 101',
    bool isCancelled = false,
    CalendarSource source = CalendarSource.timetable,
  }) => CalendarEntry(
    id: id,
    source: source,
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    location: location,
    isCancelled: isCancelled,
  );

  test(
    'keeps ongoing and upcoming entries but drops finished and cancelled',
    () {
      final CalendarHomeWidgetPayload payload = buildCalendarHomeWidgetPayload(
        entries: <CalendarEntry>[
          entry(
            'finished',
            DateTime(2026, 10, 4, 8),
            end: DateTime(2026, 10, 4, 9),
          ),
          entry(
            'ongoing',
            DateTime(2026, 10, 4, 9),
            end: DateTime(2026, 10, 4, 11),
          ),
          entry('next', DateTime(2026, 10, 4, 12)),
          entry('cancelled', DateTime(2026, 10, 4, 13), isCancelled: true),
        ],
        now: now,
        locale: 'de',
        showDetails: true,
      );

      expect(
        payload.events.map((CalendarHomeWidgetEvent event) => event.id),
        <String>['ongoing', 'next'],
      );
    },
  );

  test('privacy mode omits titles and locations from persisted JSON', () {
    final CalendarHomeWidgetPayload payload = buildCalendarHomeWidgetPayload(
      entries: <CalendarEntry>[
        entry(
          'secret',
          DateTime(2026, 10, 4, 12),
          title: 'Vertraulicher Prüfungstermin',
          location: 'Geheimer Raum',
        ),
      ],
      now: now,
      locale: 'de',
      showDetails: false,
    );

    final String encoded = jsonEncode(payload.toJson());
    expect(encoded, isNot(contains('Vertraulicher')));
    expect(encoded, isNot(contains('Geheimer')));
    expect(payload.events.single.title, isNull);
    expect(payload.events.single.location, isNull);
  });

  test('never persists personal Exchange appointments in the OS widget', () {
    final CalendarHomeWidgetPayload payload = buildCalendarHomeWidgetPayload(
      entries: <CalendarEntry>[
        entry(
          'exchange:private',
          DateTime(2026, 10, 4, 12),
          title: 'Persönlicher Termin',
          source: CalendarSource.exchangeCalendar,
        ),
        entry('public', DateTime(2026, 10, 4, 13)),
      ],
      now: now,
      locale: 'de',
      showDetails: true,
    );

    expect(
      payload.events.map((CalendarHomeWidgetEvent event) => event.id),
      <String>['public'],
    );
    expect(jsonEncode(payload.toJson()), isNot(contains('Persönlicher')));
  });

  test('all-day dates use calendar arithmetic across DST', () {
    final CalendarHomeWidgetPayload payload = buildCalendarHomeWidgetPayload(
      entries: <CalendarEntry>[
        entry('all-day', DateTime(2026, 10, 25), allDay: true, end: null),
      ],
      now: DateTime(2026, 10, 25, 12),
      locale: 'de',
      showDetails: true,
    );

    final CalendarHomeWidgetEvent event = payload.events.single;
    final DateTime end = DateTime.fromMillisecondsSinceEpoch(event.endMillis);
    expect(end, DateTime(2026, 10, 26));
  });

  test('bounds and sanitises native widget strings and list size', () {
    final List<CalendarEntry> entries = List<CalendarEntry>.generate(
      20,
      (int index) => entry(
        '$index',
        now.add(Duration(hours: index + 1)),
        title: '${'A' * 140}\u0000',
      ),
    );

    final CalendarHomeWidgetPayload payload = buildCalendarHomeWidgetPayload(
      entries: entries,
      now: now,
      locale: 'xx',
      showDetails: true,
    );

    expect(payload.events, hasLength(kMaximumCalendarHomeWidgetEvents));
    expect(payload.events.first.title, hasLength(120));
    expect(payload.events.first.title, isNot(contains('\u0000')));
    expect(payload.locale, 'de');
  });
}
