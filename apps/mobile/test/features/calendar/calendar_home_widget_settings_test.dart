// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/calendar/home_widget/calendar_home_widget_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to disabled with private titles', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(calendarHomeWidgetSettingsProvider),
      const CalendarHomeWidgetSettings(enabled: false, showDetails: false),
    );
  });

  test(
    'persists opt-in and never leaves details enabled when disabled',
    () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final CalendarHomeWidgetSettingsController controller = container.read(
        calendarHomeWidgetSettingsProvider.notifier,
      );

      await controller.setEnabled(true);
      await controller.setShowDetails(true);
      await controller.setEnabled(false);

      expect(
        container.read(calendarHomeWidgetSettingsProvider),
        const CalendarHomeWidgetSettings(enabled: false, showDetails: false),
      );

      final ProviderContainer restored = ProviderContainer(
        overrides: <Override>[keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(restored.dispose);
      expect(
        restored.read(calendarHomeWidgetSettingsProvider),
        const CalendarHomeWidgetSettings(enabled: false, showDetails: false),
      );
    },
  );
}
