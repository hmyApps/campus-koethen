// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/calendar/application/calendar_providers.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/home_widget/calendar_home_widget_host.dart';
import 'package:campus_koethen/features/calendar/home_widget/calendar_home_widget_payload.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-07: when the merged calendar may replace the OS widget's last payload.
///
/// Any source error used to hold the sync back. A connected Moodle account
/// without a course cache whose sync keeps failing therefore froze the widget
/// for good, although lectures and public calendars were all there.
CalendarEntry _entry(CalendarSource source, String id) => CalendarEntry(
  id: id,
  source: source,
  title: 'Demo-Eintrag',
  start: DateTime.utc(2026, 10, 12, 8),
  end: DateTime.utc(2026, 10, 12, 10),
);

CalendarData _data(
  List<CalendarEntry> entries, {
  bool timetableLoading = false,
  bool hasTimetableError = false,
  bool moodleLoading = false,
  bool hasMoodleError = false,
  bool publicCalendarsLoading = false,
  bool hasPublicCalendarError = false,
}) => CalendarData(
  entries: entries,
  enabledSources: <CalendarSource>{...kMergeableCalendarSources},
  timetableLoading: timetableLoading,
  hasTimetableError: hasTimetableError,
  moodleConnected: true,
  moodleLoading: moodleLoading,
  hasMoodleError: hasMoodleError,
  publicCalendarsLoading: publicCalendarsLoading,
  hasPublicCalendarError: hasPublicCalendarError,
);

void main() {
  final CalendarEntry lecture = _entry(CalendarSource.timetable, 'timetable:1');
  final CalendarEntry publicEvent = _entry(
    CalendarSource.publicCalendar,
    'publicCalendar:demo:1',
  );

  test('a failing Moodle without any cached deadline no longer blocks the '
      'other sources', () {
    expect(
      calendarHomeWidgetMaySync(
        _data(<CalendarEntry>[lecture, publicEvent], hasMoodleError: true),
      ),
      isTrue,
    );
  });

  test('a failing source that still has cached entries is synced', () {
    expect(
      calendarHomeWidgetMaySync(
        _data(<CalendarEntry>[lecture], hasTimetableError: true),
      ),
      isTrue,
    );
  });

  test('a source still loading with entries already in hand is synced', () {
    expect(
      calendarHomeWidgetMaySync(
        _data(<CalendarEntry>[lecture, publicEvent], timetableLoading: true),
      ),
      isTrue,
    );
  });

  test('a source still loading without data holds the sync back', () {
    // It answers in a moment; replacing the payload now would only blank
    // its entries on the home screen in between.
    for (final CalendarData data in <CalendarData>[
      _data(<CalendarEntry>[publicEvent], timetableLoading: true),
      _data(<CalendarEntry>[lecture], moodleLoading: true),
      _data(<CalendarEntry>[lecture], publicCalendarsLoading: true),
    ]) {
      expect(calendarHomeWidgetMaySync(data), isFalse);
    }
  });

  test('a failure with nothing to show keeps the last payload', () {
    expect(
      calendarHomeWidgetMaySync(
        _data(const <CalendarEntry>[], hasTimetableError: true),
      ),
      isFalse,
    );
    // Exchange entries never reach the widget, so they do not count as
    // something to show either.
    expect(
      calendarHomeWidgetMaySync(
        _data(<CalendarEntry>[
          _entry(CalendarSource.exchangeCalendar, 'exchange:demo'),
        ], hasPublicCalendarError: true),
      ),
      isFalse,
    );
  });

  test('a complete calendar is synced, even when it is empty', () {
    expect(calendarHomeWidgetMaySync(_data(const <CalendarEntry>[])), isTrue);
    expect(calendarHomeWidgetMaySync(_data(<CalendarEntry>[lecture])), isTrue);
  });

  test('a synced payload still never carries Exchange appointments', () {
    final CalendarData data = _data(<CalendarEntry>[
      lecture,
      _entry(CalendarSource.exchangeCalendar, 'exchange:demo'),
    ], hasMoodleError: true);
    expect(calendarHomeWidgetMaySync(data), isTrue);

    final CalendarHomeWidgetPayload payload = buildCalendarHomeWidgetPayload(
      entries: data.entries,
      now: DateTime.utc(2026, 10, 12, 6),
      locale: 'de',
      showDetails: true,
    );
    expect(payload.events.map((CalendarHomeWidgetEvent e) => e.id), <String>[
      'timetable:1',
    ]);
  });
}
