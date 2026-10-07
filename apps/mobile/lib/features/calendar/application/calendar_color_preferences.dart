// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/preference_keys.dart';
import '../../../core/prefs/settings_controller.dart';
import '../domain/calendar_entry.dart';

abstract final class CalendarColorKeys {
  static String source(CalendarSource source) =>
      'source:${source.storageValue}';

  static String publicCalendar(String slug) => 'calendar:$slug';

  static String forEntry(CalendarEntry entry) => entry.calendarSlug == null
      ? source(entry.source)
      : publicCalendar(entry.calendarSlug!);
}

class CalendarColorPreferences {
  CalendarColorPreferences([Map<String, int> overrides = const <String, int>{}])
    : overrides = Map<String, int>.unmodifiable(overrides);

  final Map<String, int> overrides;

  int? overrideFor(String key) => overrides[key];

  int? colorFor(CalendarEntry entry) =>
      overrideFor(CalendarColorKeys.forEntry(entry)) ?? entry.colorArgb;
}

class CalendarColorPreferencesController
    extends Notifier<CalendarColorPreferences> {
  // The backend permits up to 100 public calendars per request. Leave room
  // for source-level colours as well while keeping this scalar list bounded.
  static const int _maxOverrides = 128;

  @override
  CalendarColorPreferences build() {
    final List<String> stored =
        ref
            .watch(keyValueStoreProvider)
            .getStringList(PreferenceKeys.calendarColorOverrides) ??
        const <String>[];
    final Map<String, int> parsed = <String, int>{};
    for (final String line in stored.take(_maxOverrides)) {
      final int separator = line.lastIndexOf('=');
      if (separator <= 0 || separator == line.length - 1) continue;
      final String key = line.substring(0, separator);
      final int? color = int.tryParse(line.substring(separator + 1));
      if (!_validKey(key) || color == null || color < 0 || color > 0xFFFFFFFF) {
        continue;
      }
      parsed[key] = color;
    }
    return CalendarColorPreferences(parsed);
  }

  Future<void> setColor(String key, int? argb) async {
    if (!_validKey(key)) throw ArgumentError.value(key, 'key');
    if (argb != null && (argb < 0 || argb > 0xFFFFFFFF)) {
      throw RangeError.range(argb, 0, 0xFFFFFFFF, 'argb');
    }
    final Map<String, int> next = <String, int>{...state.overrides};
    if (argb == null) {
      next.remove(key);
    } else {
      if (!next.containsKey(key) && next.length >= _maxOverrides) {
        next.remove(next.keys.first);
      }
      next.remove(key);
      next[key] = argb;
    }
    state = CalendarColorPreferences(next);
    final List<String> encoded = next.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .toList(growable: false);
    await ref
        .read(keyValueStoreProvider)
        .setStringList(PreferenceKeys.calendarColorOverrides, encoded);
  }

  static bool _validKey(String key) =>
      key.length <= 180 &&
      (key.startsWith('source:') || key.startsWith('calendar:')) &&
      !key.contains('=');
}

final NotifierProvider<
  CalendarColorPreferencesController,
  CalendarColorPreferences
>
calendarColorPreferencesProvider =
    NotifierProvider<
      CalendarColorPreferencesController,
      CalendarColorPreferences
    >(CalendarColorPreferencesController.new);

List<CalendarEntry> applyCalendarColorPreferences(
  Iterable<CalendarEntry> entries,
  CalendarColorPreferences preferences,
) => entries
    .map((entry) => entry.copyWithColor(preferences.colorFor(entry)))
    .toList(growable: false);
