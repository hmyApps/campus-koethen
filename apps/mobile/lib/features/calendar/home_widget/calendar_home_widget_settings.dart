// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../core/prefs/key_value_store.dart';
import '../../../core/prefs/preference_keys.dart';
import '../../../core/prefs/settings_controller.dart';

@immutable
class CalendarHomeWidgetSettings {
  const CalendarHomeWidgetSettings({
    required this.enabled,
    required this.showDetails,
  });

  final bool enabled;
  final bool showDetails;

  CalendarHomeWidgetSettings copyWith({bool? enabled, bool? showDetails}) =>
      CalendarHomeWidgetSettings(
        enabled: enabled ?? this.enabled,
        showDetails: showDetails ?? this.showDetails,
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarHomeWidgetSettings &&
      other.enabled == enabled &&
      other.showDetails == showDetails;

  @override
  int get hashCode => Object.hash(enabled, showDetails);
}

class CalendarHomeWidgetSettingsController
    extends Notifier<CalendarHomeWidgetSettings> {
  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  CalendarHomeWidgetSettings build() {
    ref.watch(keyValueStoreProvider);
    final bool enabled =
        _store.getInt(PreferenceKeys.calendarHomeWidgetEnabled) == 1;
    return CalendarHomeWidgetSettings(
      enabled: enabled,
      showDetails:
          enabled &&
          _store.getInt(PreferenceKeys.calendarHomeWidgetShowDetails) == 1,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final bool showDetails = enabled && state.showDetails;
    state = state.copyWith(enabled: enabled, showDetails: showDetails);
    await _store.setInt(
      PreferenceKeys.calendarHomeWidgetEnabled,
      enabled ? 1 : 0,
    );
    if (!enabled) {
      await _store.setInt(PreferenceKeys.calendarHomeWidgetShowDetails, 0);
    }
  }

  Future<void> setShowDetails(bool showDetails) async {
    final bool accepted = state.enabled && showDetails;
    state = state.copyWith(showDetails: accepted);
    await _store.setInt(
      PreferenceKeys.calendarHomeWidgetShowDetails,
      accepted ? 1 : 0,
    );
  }
}

final NotifierProvider<
  CalendarHomeWidgetSettingsController,
  CalendarHomeWidgetSettings
>
calendarHomeWidgetSettingsProvider =
    NotifierProvider<
      CalendarHomeWidgetSettingsController,
      CalendarHomeWidgetSettings
    >(CalendarHomeWidgetSettingsController.new);
