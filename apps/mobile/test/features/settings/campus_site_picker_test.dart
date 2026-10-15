// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/site/campus_site.dart';
import 'package:campus_koethen/features/settings/presentation/campus_site_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('offers the three sites with nothing preselected', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester, const Scaffold(body: CampusSiteOptions()));

    expect(find.text('Köthen'), findsOneWidget);
    expect(find.text('Bernburg'), findsOneWidget);
    expect(find.text('Dessau'), findsOneWidget);
    final RadioGroup<CampusSite> group = tester.widget<RadioGroup<CampusSite>>(
      find.byType(RadioGroup<CampusSite>),
    );
    expect(group.groupValue, isNull);
  });

  testWidgets('a choice is stored and shown as selected', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    await pumpScreen(
      tester,
      const Scaffold(body: CampusSiteOptions()),
      keyValueStore: store,
    );

    await tester.tap(find.text('Dessau'));
    await tester.pumpAndSettle();

    expect(store.getString(PreferenceKeys.campusSite), 'dessau');
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(CampusSiteOptions)),
    );
    expect(container.read(settingsProvider).campusSite, CampusSite.dessau);
  });

  testWidgets('the settings sheet explains the effect and closes after a '
      'choice', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showCampusSitePickerSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Mensa, Lageplan und Kontakte zeigen diesen Standort zuerst.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Bernburg'));
    await tester.pumpAndSettle();

    expect(find.text('Bernburg'), findsNothing, reason: 'the sheet closed');
  });
}
