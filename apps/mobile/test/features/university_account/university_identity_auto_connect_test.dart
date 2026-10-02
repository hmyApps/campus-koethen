// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/settings/domain/direct_service.dart';
import 'package:campus_koethen/features/university_account/application/university_service_connector.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:campus_koethen/features/university_account/presentation/university_identity_auto_connect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

const UniversityIdentity _identity = UniversityIdentity(
  identifier: 'student@hs-anhalt.de',
  password: 'secret',
);

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;

  @override
  Future<UniversityIdentity?> read() async => value;

  @override
  Future<void> write(UniversityIdentity identity) async => value = identity;

  @override
  Future<void> clear() async => value = null;
}

class _Adapter implements UniversityServiceAdapter {
  _Adapter({this.connectError});

  Object? connectError;
  int connectCalls = 0;
  UniversityIdentity? lastIdentity;

  @override
  Future<void> connect(UniversityIdentity value, {String? displayName}) async {
    connectCalls++;
    lastIdentity = value;
    if (connectError != null) throw connectError!;
  }

  @override
  Future<void> disconnect() async {}
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _MemoryIdentityStore store,
  required _Adapter adapter,
  required Widget fallback,
}) => pumpScreen(
  tester,
  UniversityIdentityAutoConnect(
    service: DirectService.moodle,
    builder: (BuildContext context, Object? error) => fallback,
  ),
  universityIdentityStore: store,
  overrides: <Override>[
    universityServiceAdapterProvider(
      DirectService.moodle,
    ).overrideWithValue(adapter),
  ],
);

void main() {
  testWidgets(
    'an existing central identity is used automatically — no form, no '
    'second credential entry',
    (WidgetTester tester) async {
      final _Adapter adapter = _Adapter();
      await _pump(
        tester,
        store: _MemoryIdentityStore()..value = _identity,
        adapter: adapter,
        fallback: const Text('manual form'),
      );
      // Not pumpAndSettle: on success this widget stays on its own spinner
      // forever by design — it is the ENCLOSING gate (e.g. `MoodleScreen`)
      // that switches away once the service reports "connected", which this
      // isolated test has no such gate to do.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(adapter.connectCalls, 1);
      expect(adapter.lastIdentity, _identity);
      expect(find.text('manual form'), findsNothing);
    },
  );

  testWidgets('no stored identity shows the manual form immediately, never '
      'attempting a connection', (WidgetTester tester) async {
    final _Adapter adapter = _Adapter();
    await _pump(
      tester,
      store: _MemoryIdentityStore(),
      adapter: adapter,
      fallback: const Text('manual form'),
    );
    await tester.pumpAndSettle();

    expect(adapter.connectCalls, 0);
    expect(find.text('manual form'), findsOneWidget);
  });

  testWidgets(
    'a failed auto-connect (e.g. a changed password) falls back to the '
    'manual form instead of leaving the reader stuck',
    (WidgetTester tester) async {
      final _Adapter adapter = _Adapter(connectError: Exception('rejected'));
      await _pump(
        tester,
        store: _MemoryIdentityStore()..value = _identity,
        adapter: adapter,
        fallback: const Text('manual form'),
      );
      await tester.pumpAndSettle();

      expect(adapter.connectCalls, 1);
      expect(find.text('manual form'), findsOneWidget);
    },
  );
}
