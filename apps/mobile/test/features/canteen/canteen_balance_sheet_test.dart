// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/canteen/application/canteen_balance_providers.dart';
import 'package:campus_koethen/features/canteen/application/canteen_providers.dart';
import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/features/canteen/data/canteen_models.dart';
import 'package:campus_koethen/features/canteen/domain/canteen_balance_apdu.dart';
import 'package:campus_koethen/features/canteen/domain/canteen_balance_reader.dart';
import 'package:campus_koethen/features/canteen/presentation/canteen_balance_sheet.dart';
import 'package:campus_koethen/features/canteen/presentation/canteen_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

class _FakeReader implements CanteenBalanceReader {
  CanteenBalanceAvailability support = CanteenBalanceAvailability.available;
  CanteenBalance balance = const CanteenBalance(milliEuros: 12345);
  CanteenBalanceReadException? failure;
  Completer<CanteenBalance>? pending;
  final List<CanteenBalanceReadOrigin> origins = <CanteenBalanceReadOrigin>[];
  int cancels = 0;

  @override
  Future<CanteenBalanceAvailability> availability() async => support;

  @override
  Stream<void> get externalTagDiscovered => const Stream<void>.empty();

  @override
  Future<bool> hasPendingExternalTag() async => false;

  @override
  Future<CanteenBalance> read({
    required CanteenBalanceReadOrigin origin,
    required String prompt,
  }) async {
    origins.add(origin);
    final CanteenBalanceReadException? failure = this.failure;
    if (failure != null) throw failure;
    return pending?.future ?? balance;
  }

  @override
  Future<void> cancel() async => cancels++;
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  _FakeReader reader, {
  CanteenBalanceReadOrigin origin = CanteenBalanceReadOrigin.manual,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await pumpScreen(
    tester,
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showCanteenBalanceSheet(context, origin: origin),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    overrides: <Override>[
      canteenBalanceReaderProvider.overrideWithValue(reader),
    ],
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('Mensa masthead exposes the manual 48dp balance action', (
    WidgetTester tester,
  ) async {
    final _FakeReader reader = _FakeReader();
    await pumpScreen(
      tester,
      const CanteenScreen(),
      overrides: <Override>[
        canteenBalanceReaderProvider.overrideWithValue(reader),
        canteensProvider.overrideWith(
          (Ref ref) async => const Loaded<List<Canteen>>(
            value: <Canteen>[],
            meta: ApiMeta.empty,
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    final Finder action = find.byTooltip('Guthaben prüfen');
    expect(action, findsOneWidget);
    expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Mensa-Guthaben prüfen'), findsOneWidget);
    // No separate "Start" tap: opening the sheet reads immediately.
    expect(reader.origins, <CanteenBalanceReadOrigin>[
      CanteenBalanceReadOrigin.manual,
    ]);
    expect(find.textContaining('12,35'), findsOneWidget);
  });

  testWidgets('external route token opens the sheet without a second tap', (
    WidgetTester tester,
  ) async {
    final _FakeReader reader = _FakeReader();
    await pumpScreen(
      tester,
      const CanteenScreen(externalBalanceLaunchToken: 'launch-1'),
      overrides: <Override>[
        canteenBalanceReaderProvider.overrideWithValue(reader),
        canteensProvider.overrideWith(
          (Ref ref) async => const Loaded<List<Canteen>>(
            value: <Canteen>[],
            meta: ApiMeta.empty,
          ),
        ),
      ],
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(reader.origins, <CanteenBalanceReadOrigin>[
      CanteenBalanceReadOrigin.externalTag,
    ]);
    expect(find.textContaining('12,35'), findsOneWidget);
  });

  testWidgets(
    'manual entry starts reading immediately, explanation shown throughout',
    (WidgetTester tester) async {
      final Completer<CanteenBalance> pending = Completer<CanteenBalance>();
      final _FakeReader reader = _FakeReader()..pending = pending;
      await _pumpLauncher(tester, reader);

      // No separate "Start" tap — the read is already under way.
      expect(reader.origins, <CanteenBalanceReadOrigin>[
        CanteenBalanceReadOrigin.manual,
      ]);
      expect(find.text('Mensa-Guthaben prüfen'), findsOneWidget);
      expect(find.textContaining('nicht gespeichert'), findsOneWidget);
      expect(find.text('Karte wird gelesen …'), findsOneWidget);

      pending.complete(const CanteenBalance(milliEuros: 12345));
      await tester.pumpAndSettle();

      expect(find.textContaining('12,35'), findsOneWidget);
    },
  );

  testWidgets(
    'external Android entry starts immediately and remains cancellable',
    (WidgetTester tester) async {
      final Completer<CanteenBalance> pending = Completer<CanteenBalance>();
      final _FakeReader reader = _FakeReader()..pending = pending;
      await _pumpLauncher(
        tester,
        reader,
        origin: CanteenBalanceReadOrigin.externalTag,
      );

      expect(reader.origins, <CanteenBalanceReadOrigin>[
        CanteenBalanceReadOrigin.externalTag,
      ]);
      expect(find.text('Karte wird gelesen …'), findsOneWidget);
      expect(find.textContaining('nicht gespeichert'), findsOneWidget);

      await tester.tap(find.text('Abbrechen'));
      await tester.pump();
      expect(reader.cancels, 1);
    },
  );

  testWidgets('unsupported hardware has an explicit state and never reads', (
    WidgetTester tester,
  ) async {
    final _FakeReader reader = _FakeReader()
      ..support = CanteenBalanceAvailability.notSupported;
    await _pumpLauncher(tester, reader);

    expect(find.text('NFC nicht verfügbar'), findsOneWidget);
    expect(reader.origins, isEmpty);
  });

  testWidgets('a read failure is never rendered as a zero balance', (
    WidgetTester tester,
  ) async {
    final _FakeReader reader = _FakeReader()
      ..failure = const CanteenBalanceReadException(
        CanteenBalanceFailure.invalidResponse,
      );
    await _pumpLauncher(tester, reader);
    await tester.pumpAndSettle();

    expect(find.text('Karte konnte nicht gelesen werden'), findsOneWidget);
    expect(find.textContaining('0,00'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('external tag retry falls back to active manual reader mode', (
    WidgetTester tester,
  ) async {
    final _FakeReader reader = _FakeReader()
      ..failure = const CanteenBalanceReadException(
        CanteenBalanceFailure.tagLost,
      );
    await _pumpLauncher(
      tester,
      reader,
      origin: CanteenBalanceReadOrigin.externalTag,
    );
    await tester.pumpAndSettle();

    expect(reader.origins, <CanteenBalanceReadOrigin>[
      CanteenBalanceReadOrigin.externalTag,
    ]);
    reader.failure = null;

    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();

    expect(reader.origins, <CanteenBalanceReadOrigin>[
      CanteenBalanceReadOrigin.externalTag,
      CanteenBalanceReadOrigin.manual,
    ]);
    expect(find.textContaining('12,35'), findsOneWidget);
  });

  testWidgets('sheet fits at 320dp and 200 percent text', (
    WidgetTester tester,
  ) async {
    final _FakeReader reader = _FakeReader();
    await _pumpLauncher(tester, reader, textScale: 2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('12,35'), findsOneWidget);
  });
}
