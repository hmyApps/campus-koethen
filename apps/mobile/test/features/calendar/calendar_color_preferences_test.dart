// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/calendar/application/calendar_color_preferences.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar-specific colour beats the editorial source colour', () async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container
        .read(calendarColorPreferencesProvider.notifier)
        .setColor(CalendarColorKeys.publicCalendar('fsr-ins'), 0xFFF9A825);

    final CalendarEntry input = CalendarEntry(
      id: 'event',
      source: CalendarSource.publicCalendar,
      title: 'Event',
      start: DateTime(2026, 10, 10),
      calendarSlug: 'fsr-ins',
      colorArgb: 0xFF0000FF,
    );
    final CalendarEntry output = applyCalendarColorPreferences(<CalendarEntry>[
      input,
    ], container.read(calendarColorPreferencesProvider)).single;

    expect(output.colorArgb, 0xFFF9A825);
    expect(store.getStringList(PreferenceKeys.calendarColorOverrides), <String>[
      'calendar:fsr-ins=4294551589',
    ]);
  });

  test('a source colour applies to every timetable entry', () async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container
        .read(calendarColorPreferencesProvider.notifier)
        .setColor(
          CalendarColorKeys.source(CalendarSource.timetable),
          0xFF616161,
        );
    final CalendarEntry output = applyCalendarColorPreferences(<CalendarEntry>[
      CalendarEntry(
        id: 'lesson',
        source: CalendarSource.timetable,
        title: 'Lesson',
        start: DateTime(2026, 10, 10),
      ),
    ], container.read(calendarColorPreferencesProvider)).single;
    expect(output.colorArgb, 0xFF616161);
  });
}
