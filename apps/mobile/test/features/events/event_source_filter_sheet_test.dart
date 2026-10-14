// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/events/application/event_providers.dart';
import 'package:campus_koethen/features/events/application/event_sort_order.dart';
import 'package:campus_koethen/features/events/application/event_source_filter.dart';
import 'package:campus_koethen/features/events/domain/event_sort.dart';
import 'package:campus_koethen/features/events/presentation/event_source_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

const List<EventSourceOption> _options = <EventSourceOption>[
  EventSourceOption(key: 'campus-events', label: 'Campus Events'),
  EventSourceOption(key: 'stura-termine', label: 'StuRa Termine'),
];

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  Set<String> selected = const <String>{'campus-events', 'stura-termine'},
  String? storedSortOrder,
}) async {
  final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
    PreferenceKeys.eventSourceStoreVersion:
        PreferenceKeys.eventSourceStoreCurrentVersion,
    PreferenceKeys.eventSourceSeenKeys: _options
        .map((EventSourceOption o) => o.key)
        .toList(),
    PreferenceKeys.eventSourceSelectedKeys: selected.toList(),
    PreferenceKeys.eventSortOrder: ?storedSortOrder,
  });
  final ProviderContainer container = await pumpScreen(
    tester,
    Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showEventSourceFilterSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    keyValueStore: store,
    overrides: <Override>[
      eventSourceOptionsProvider.overrideWith((Ref ref) async => _options),
    ],
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('lists every source with its current selection', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, selected: <String>{'campus-events'});

    expect(find.text('Campus Events'), findsOneWidget);
    expect(find.text('StuRa Termine'), findsOneWidget);
    final CheckboxListTile campus = tester.widget(
      find.widgetWithText(CheckboxListTile, 'Campus Events'),
    );
    final CheckboxListTile stura = tester.widget(
      find.widgetWithText(CheckboxListTile, 'StuRa Termine'),
    );
    expect(campus.value, isTrue);
    expect(stura.value, isFalse);
  });

  testWidgets('Alle abwählen clears every checkbox', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpSheet(tester);

    await tester.tap(find.text('Alle abwählen'));
    await tester.pumpAndSettle();

    expect(container.read(eventSourceFilterProvider).selectedKeys, isEmpty);
  });

  testWidgets('Alle auswählen selects every option', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpSheet(
      tester,
      selected: const <String>{},
    );

    await tester.tap(find.text('Alle auswählen'));
    await tester.pumpAndSettle();

    expect(container.read(eventSourceFilterProvider).selectedKeys, <String>{
      'campus-events',
      'stura-termine',
    });
  });

  testWidgets('toggling one checkbox updates only that source', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpSheet(
      tester,
      selected: <String>{'campus-events'},
    );

    await tester.tap(find.text('StuRa Termine'));
    await tester.pumpAndSettle();

    expect(container.read(eventSourceFilterProvider).selectedKeys, <String>{
      'campus-events',
      'stura-termine',
    });
  });

  group('Sortierung', () {
    RadioListTile<EventSortOrder> tile(WidgetTester tester, String label) =>
        tester.widget(
          find.widgetWithText(RadioListTile<EventSortOrder>, label),
        );

    void expectChecked(WidgetTester tester, String label, bool checked) =>
        expect(
          tester.getSemantics(
            find.widgetWithText(RadioListTile<EventSortOrder>, label),
          ),
          isSemantics(isChecked: checked, isInMutuallyExclusiveGroup: true),
        );

    testWidgets('offers both orders with chronological as the default', (
      WidgetTester tester,
    ) async {
      await _pumpSheet(tester);
      await tester.scrollUntilVisible(find.text('Neueste zuerst'), 50);

      expect(find.text('Sortierung'), findsOneWidget);
      expect(tile(tester, 'Chronologisch').value, EventSortOrder.chronological);
      expectChecked(tester, 'Chronologisch', true);
      expectChecked(tester, 'Neueste zuerst', false);
    });

    testWidgets('choosing "Neueste zuerst" applies and persists it', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await _pumpSheet(tester);
      final KeyValueStore store = container.read(keyValueStoreProvider);
      await tester.scrollUntilVisible(find.text('Neueste zuerst'), 50);

      await tester.tap(find.text('Neueste zuerst'));
      await tester.pumpAndSettle();

      expect(
        container.read(eventSortOrderProvider),
        EventSortOrder.newestFirst,
      );
      expect(store.getString(PreferenceKeys.eventSortOrder), 'newestFirst');
      expectChecked(tester, 'Neueste zuerst', true);
    });

    testWidgets('restores a stored order', (WidgetTester tester) async {
      await _pumpSheet(tester, storedSortOrder: 'newestFirst');
      await tester.scrollUntilVisible(find.text('Neueste zuerst'), 50);

      expectChecked(tester, 'Neueste zuerst', true);
      expectChecked(tester, 'Chronologisch', false);
    });

    testWidgets('each option is a radio with a 48dp touch target', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpSheet(tester);
      await tester.scrollUntilVisible(find.text('Neueste zuerst'), 50);

      for (final String label in <String>['Chronologisch', 'Neueste zuerst']) {
        final Finder option = find.widgetWithText(
          RadioListTile<EventSortOrder>,
          label,
        );
        expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
      }
      expectChecked(tester, 'Chronologisch', true);
      handle.dispose();
    });
  });
}
