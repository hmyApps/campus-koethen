// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:campus_koethen/features/timetable/presentation/timetable_group_picker_sheet.dart';
import 'package:campus_koethen/features/timetable/presentation/timetable_subscriptions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

void main() {
  group('the timetable group picker sheet', () {
    testWidgets('never overflows and keeps the search field reachable, at the '
        'smallest supported viewport, a large Android keyboard and 200% '
        'text scale', (WidgetTester tester) async {
      // The smallest supported Android viewport with a keyboard tall
      // enough to cover most of it — the exact constellation that first
      // surfaced the bug.
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      await pumpScreen(
        tester,
        Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTimetableGroupPickerSheet(context, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        overrides: <Override>[
          timetableGroupsProvider.overrideWith(
            (Ref ref) async => const Loaded<List<TimetableGroup>>(
              value: <TimetableGroup>[],
              meta: ApiMeta.empty,
            ),
          ),
        ],
        textScaler: const TextScaler.linear(2),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The headline claim: this constellation used to throw a
      // `RenderFlex overflowed` error — the "black-and-yellow tape" bug —
      // rather than merely looking cramped.
      expect(tester.takeException(), isNull);

      // Cramped as it is, the field must still be reachable by scrolling
      // the sheet's own content — not clipped away with no way back to it.
      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final double keyboardTop = 480 - 300;
      final Rect field = tester.getRect(find.byType(TextField));
      expect(
        field.bottom,
        lessThanOrEqualTo(keyboardTop),
        reason:
            'the search field must stay reachable above the keyboard, '
            'not lost behind it with no way to scroll it into view',
      );
    });
  });

  testWidgets('additional group and module sheets survive 200 percent text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    const TimetableGroup primary = TimetableGroup(
      id: 'primary',
      shortName: 'AIN4',
    );
    const TimetableGroup other = TimetableGroup(
      id: 'other',
      shortName: 'AIN2',
      longName: 'Angewandte Informatik zweites Semester',
    );
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAdditionalTimetableGroupsSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      overrides: <Override>[
        timetableGroupsProvider.overrideWith(
          (Ref ref) async => const Loaded<List<TimetableGroup>>(
            value: <TimetableGroup>[primary, other],
            meta: ApiMeta.empty,
          ),
        ),
        timetableModulesProvider.overrideWith(
          (Ref ref, String groupId) async =>
              const Loaded<List<TimetableModule>>(
                value: <TimetableModule>[
                  TimetableModule(
                    title: 'Mathematik 2',
                    subjectCode: 'MATH2',
                    moduleKey: 'code:MATH2',
                  ),
                ],
                meta: ApiMeta.empty,
              ),
        ),
      ],
      keyValueStore: InMemoryKeyValueStore(<String, Object>{
        PreferenceKeys.preferredTimetableGroup: primary.id,
      }),
      textScaler: const TextScaler.linear(2),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Finder moduleAction = find.text('Einzelne Module auswählen');
    await tester.ensureVisible(moduleAction);
    await tester.pumpAndSettle();
    await tester.tap(moduleAction);
    await tester.pumpAndSettle();
    expect(find.text('Module aus AIN2'), findsOneWidget);
    expect(find.text('Mathematik 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
