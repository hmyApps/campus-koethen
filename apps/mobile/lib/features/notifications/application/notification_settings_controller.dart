// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/key_value_store.dart';
import '../../../core/prefs/preference_keys.dart';
import '../../../core/prefs/settings_controller.dart';
import '../domain/notification_category.dart';
import '../domain/notification_preferences.dart';

/// Reads and writes [NotificationPreferences].
///
/// Small scalar settings in `shared_preferences`, nothing more. They survive a restart
/// because they are written the moment they change, and they survive a
/// reinstall not at all — which is correct: an opt-in is a decision about this
/// installation, and there is nowhere else it could have been kept.
class NotificationSettingsController extends Notifier<NotificationPreferences> {
  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  NotificationPreferences build() {
    final KeyValueStore store = ref.watch(keyValueStoreProvider);
    return NotificationPreferences(
      optedIn: store.getInt(PreferenceKeys.notificationsOptedIn) == 1,
      disabledCategories: _readDisabled(store),
      prePromptDeclined:
          store.getInt(PreferenceKeys.notificationsPrePromptDeclined) == 1,
      dailySummaryMinutes: _readDailySummaryMinutes(store),
      moodleDeadlineLeadMinutes: _readMoodleDeadlineLeadMinutes(store),
      eventReminderMinutes: _readEventReminderMinutes(store),
      eventReminderOverrides: _readEventReminderOverrides(store),
    );
  }

  static const Set<int> allowedEventReminderMinutes = <int>{
    15,
    60,
    6 * 60,
    24 * 60,
    2 * 24 * 60,
    7 * 24 * 60,
  };

  static int _readEventReminderMinutes(KeyValueStore store) {
    final int? value = store.getInt(
      PreferenceKeys.notificationEventReminderMinutes,
    );
    return allowedEventReminderMinutes.contains(value) ? value! : 24 * 60;
  }

  static Map<String, int> _readEventReminderOverrides(KeyValueStore store) {
    final Map<String, int> result = <String, int>{};
    final List<String> stored =
        store.getStringList(
          PreferenceKeys.notificationEventReminderOverrides,
        ) ??
        const <String>[];
    for (final String line in stored.take(200)) {
      final int separator = line.lastIndexOf('=');
      if (separator <= 0 || separator == line.length - 1) continue;
      final String id = line.substring(0, separator);
      final int? minutes = int.tryParse(line.substring(separator + 1));
      if (id.length > 220 ||
          minutes == null ||
          (minutes != -1 && !allowedEventReminderMinutes.contains(minutes))) {
        continue;
      }
      result[id] = minutes;
    }
    return Map<String, int>.unmodifiable(result);
  }

  Future<void> setEventReminderMinutes(int minutes) async {
    if (!allowedEventReminderMinutes.contains(minutes)) {
      throw ArgumentError.value(minutes, 'minutes');
    }
    state = state.copyWith(eventReminderMinutes: minutes);
    await _store.setInt(
      PreferenceKeys.notificationEventReminderMinutes,
      minutes,
    );
  }

  Future<void> setEventReminderOverride(String eventId, int? minutes) async {
    if (eventId.isEmpty || eventId.length > 220 || eventId.contains('=')) {
      throw ArgumentError.value(eventId, 'eventId');
    }
    if (minutes != null &&
        minutes != -1 &&
        !allowedEventReminderMinutes.contains(minutes)) {
      throw ArgumentError.value(minutes, 'minutes');
    }
    final Map<String, int> next = <String, int>{
      ...state.eventReminderOverrides,
    };
    if (minutes == null) {
      next.remove(eventId);
    } else {
      if (!next.containsKey(eventId) && next.length >= 200) {
        // The map preserves insertion order. Keep storage bounded without
        // turning a perfectly valid UI action into an unhandled error after
        // years of stale event ids.
        next.remove(next.keys.first);
      }
      // Reinsert an existing rule so the most recently changed event stays at
      // the back of the bounded queue.
      next.remove(eventId);
      next[eventId] = minutes;
    }
    state = state.copyWith(
      eventReminderOverrides: Map<String, int>.unmodifiable(next),
    );
    final List<String> encoded = next.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .toList(growable: false);
    await _store.setStringList(
      PreferenceKeys.notificationEventReminderOverrides,
      encoded,
    );
  }

  static int _readDailySummaryMinutes(KeyValueStore store) {
    final int? value = store.getInt(
      PreferenceKeys.notificationsDailySummaryMinutes,
    );
    return value != null && value >= 0 && value < 24 * 60 ? value : 8 * 60;
  }

  static int _readMoodleDeadlineLeadMinutes(KeyValueStore store) {
    final int? value = store.getInt(
      PreferenceKeys.notificationsMoodleDeadlineLeadMinutes,
    );
    return value != null && value >= 15 && value <= 30 * 24 * 60
        ? value
        : 24 * 60;
  }

  Future<void> setMoodleDeadlineLeadMinutes(int value) async {
    if (value < 15 || value > 30 * 24 * 60) {
      throw RangeError.range(value, 15, 30 * 24 * 60, 'value');
    }
    if (state.moodleDeadlineLeadMinutes == value) return;
    state = state.copyWith(moodleDeadlineLeadMinutes: value);
    await _store.setInt(
      PreferenceKeys.notificationsMoodleDeadlineLeadMinutes,
      value,
    );
  }

  Future<void> setDailySummaryMinutes(int value) async {
    if (value < 0 || value >= 24 * 60) {
      throw RangeError.range(value, 0, 24 * 60 - 1, 'value');
    }
    if (state.dailySummaryMinutes == value) return;
    state = state.copyWith(dailySummaryMinutes: value);
    await _store.setInt(PreferenceKeys.notificationsDailySummaryMinutes, value);
  }

  /// An unknown stored value is ignored rather than repaired: it can only come
  /// from a category a later version removed, and dropping it silently turns
  /// notifications back **on** for something that no longer exists — which is
  /// nothing.
  static Set<NotificationCategory> _readDisabled(KeyValueStore store) {
    final List<String>? stored = store.getStringList(
      PreferenceKeys.notificationCategoriesDisabled,
    );
    if (stored == null) return const <NotificationCategory>{};
    return <NotificationCategory>{
      for (final String value in stored)
        if (NotificationCategory.fromStorage(value)
            case final NotificationCategory c)
          c,
    };
  }

  /// Turns the whole feature on or off.
  ///
  /// Switching off does not itself cancel anything — the plan simply becomes
  /// empty, and the scheduler clears the pending entries when it applies it.
  /// One path, so "off" cannot mean two different things.
  Future<void> setOptedIn(bool value) async {
    if (state.optedIn == value) return;
    state = state.copyWith(optedIn: value);
    await _store.setInt(PreferenceKeys.notificationsOptedIn, value ? 1 : 0);
  }

  Future<void> setCategoryEnabled(
    NotificationCategory category,
    bool enabled,
  ) async {
    final Set<NotificationCategory> next = <NotificationCategory>{
      ...state.disabledCategories,
    };
    if (enabled) {
      next.remove(category);
    } else {
      next.add(category);
    }
    if (next.length == state.disabledCategories.length &&
        next.containsAll(state.disabledCategories)) {
      return;
    }
    state = state.copyWith(disabledCategories: next);
    await _store.setStringList(
      PreferenceKeys.notificationCategoriesDisabled,
      next
          .map((NotificationCategory c) => c.storageValue)
          .toList(growable: false),
    );
  }

  /// Records that the reader closed the pre-permission sheet without asking
  /// the operating system.
  Future<void> markPrePromptDeclined() async {
    if (state.prePromptDeclined) return;
    state = state.copyWith(prePromptDeclined: true);
    await _store.setInt(PreferenceKeys.notificationsPrePromptDeclined, 1);
  }
}

/// The reader's local notification settings.
final NotifierProvider<NotificationSettingsController, NotificationPreferences>
notificationSettingsProvider =
    NotifierProvider<NotificationSettingsController, NotificationPreferences>(
      NotificationSettingsController.new,
    );
