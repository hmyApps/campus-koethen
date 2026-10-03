// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:campus_koethen/features/timetable/presentation/timetable_group_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';
import '../../support/fake_timetable.dart';

void main() {
  group('the timetable group picker sheet', () {
    testWidgets(
      'distinguishes same-name courses by public metadata without exposing ids',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          const Scaffold(body: TimetableGroupPickerList()),
          overrides: <Override>[
            timetableGroupSearchProvider('').overrideWith(
              () => FixedTimetableGroupSearchController(
                fixedTimetableGroupSearch(const <TimetableGroup>[
                  TimetableGroup(
                    id: 'private-campus-uuid-1',
                    shortName: 'MER2',
                    longName: 'Ernährungstherapie',
                    department: 'FB1',
                  ),
                  TimetableGroup(
                    id: 'private-campus-uuid-2',
                    shortName: 'MER2',
                    longName: 'Ernährungstherapie dual',
                    department: 'FB1',
                  ),
                ]),
              ),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.text('MER2'), findsNWidgets(2));
        expect(find.text('Ernährungstherapie'), findsOneWidget);
        expect(find.text('Ernährungstherapie dual'), findsOneWidget);
        expect(find.textContaining('private-campus-uuid'), findsNothing);
      },
    );

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
          timetableGroupSearchProvider('').overrideWith(
            () => FixedTimetableGroupSearchController(
              fixedTimetableGroupSearch(const []),
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
}
