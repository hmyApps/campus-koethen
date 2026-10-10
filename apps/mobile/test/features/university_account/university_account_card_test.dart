// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/settings/application/sign_out_everywhere_controller.dart';
import 'package:campus_koethen/features/settings/domain/direct_service.dart';
import 'package:campus_koethen/features/nextcloud/application/nextcloud_providers.dart';
import 'package:campus_koethen/features/university_account/application/university_service_connector.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:campus_koethen/features/university_account/presentation/university_account_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';
import '../../support/fake_nextcloud.dart';

const UniversityIdentity _identity = UniversityIdentity(
  identifier: 'student@hs-anhalt.de',
  password: 'secret',
);

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;
  Object? readError;
  int writes = 0;

  @override
  Future<UniversityIdentity?> read() async {
    if (readError != null) throw readError!;
    return value;
  }

  @override
  Future<void> write(UniversityIdentity identity) async {
    writes++;
    value = identity;
  }

  @override
  Future<void> clear() async => value = null;
}

class _Adapter implements UniversityServiceAdapter {
  _Adapter({this.connectGate, this.connectStarted});

  final Completer<void>? connectGate;
  final Completer<void>? connectStarted;
  UniversityIdentity? identity;
  int disconnects = 0;
  Object? connectError;

  @override
  Future<void> connect(UniversityIdentity value, {String? displayName}) async {
    if (connectStarted != null && !connectStarted!.isCompleted) {
      connectStarted!.complete();
    }
    await connectGate?.future;
    if (connectError != null) throw connectError!;
    identity = value;
  }

  @override
  Future<void> disconnect() async => disconnects++;
}

List<Override> _overrides({
  required Map<DirectService, _Adapter> adapters,
  List<DirectService> connected = const <DirectService>[],
}) => <Override>[
  nextcloudCredentialStoreProvider.overrideWithValue(
    InMemoryNextcloudCredentialStore(),
  ),
  connectedDirectServicesProvider.overrideWithValue(connected),
  universityServiceConnectionSnapshotProvider.overrideWithValue(
    UniversityServiceConnectionSnapshot(connected: connected.toSet()),
  ),
  for (final MapEntry<DirectService, _Adapter> entry in adapters.entries)
    universityServiceAdapterProvider(entry.key).overrideWithValue(entry.value),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _MemoryIdentityStore store,
  required Map<DirectService, _Adapter> adapters,
  List<DirectService> connected = const <DirectService>[],
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return pumpScreen(
    tester,
    const Scaffold(body: SingleChildScrollView(child: UniversityAccountCard())),
    universityIdentityStore: store,
    overrides: _overrides(adapters: adapters, connected: connected),
  );
}

void main() {
  testWidgets('shows explicit status and semantic plus/minus actions', (
    WidgetTester tester,
  ) async {
    final _MemoryIdentityStore store = _MemoryIdentityStore()
      ..value = _identity;
    final Map<DirectService, _Adapter> adapters = <DirectService, _Adapter>{
      for (final DirectService service in DirectService.values)
        service: _Adapter(),
    };
    await _pump(
      tester,
      store: store,
      adapters: adapters,
      connected: const <DirectService>[DirectService.mail],
    );
    await tester.pump();

    expect(find.text('Hochschulzugang'), findsOneWidget);
    expect(find.textContaining('student@hs-anhalt.de'), findsOneWidget);
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('Nicht verbunden'), findsNWidgets(4));
    expect(find.byTooltip('Studentische E-Mail trennen'), findsOneWidget);
    expect(find.byTooltip('Moodle verbinden'), findsOneWidget);

    await tester.tap(find.byTooltip('Studentische E-Mail trennen'));
    await tester.pump();
    expect(adapters[DirectService.mail]!.disconnects, 1);
    expect(store.value, _identity);
  });

  testWidgets('first plus validates and stores only after explicit consent', (
    WidgetTester tester,
  ) async {
    final _MemoryIdentityStore store = _MemoryIdentityStore();
    final Map<DirectService, _Adapter> adapters = <DirectService, _Adapter>{
      for (final DirectService service in DirectService.values)
        service: _Adapter(),
    };
    await _pump(tester, store: store, adapters: adapters);
    await tester.pump();

    await tester.tap(find.byTooltip('Moodle verbinden'));
    await tester.pumpAndSettle();
    expect(find.text('Hochschulzugang einrichten'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Hochschul-Benutzername oder -Mailadresse',
      ),
      'student@hs-anhalt.de',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hochschul-Passwort'),
      'secret',
    );

    await tester.ensureVisible(find.text('Prüfen und sicher hinterlegen'));
    await tester.tap(find.text('Prüfen und sicher hinterlegen'));
    await tester.pump();
    expect(store.writes, 0);
    expect(
      find.text('Bitte bestätige die lokale Speicherung.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('Prüfen und sicher hinterlegen'));
    await tester.tap(find.text('Prüfen und sicher hinterlegen'));
    await tester.pumpAndSettle();

    expect(adapters[DirectService.moodle]!.identity, _identity);
    expect(store.value, _identity);
    expect(store.writes, 1);
    expect(find.text('Hochschulzugang einrichten'), findsNothing);
  });

  testWidgets('failed service validation leaves central identity absent', (
    WidgetTester tester,
  ) async {
    final _MemoryIdentityStore store = _MemoryIdentityStore();
    final Map<DirectService, _Adapter> adapters = <DirectService, _Adapter>{
      for (final DirectService service in DirectService.values)
        service: _Adapter(),
    };
    adapters[DirectService.grades]!.connectError = StateError('rejected');
    await _pump(tester, store: store, adapters: adapters);
    await tester.pump();

    await tester.tap(find.byTooltip('Noten (HISinOne / HIS-QIS) verbinden'));
    await tester.pumpAndSettle();
    for (final ({String label, String value}) field
        in <({String label, String value})>[
          (
            label: 'Hochschul-Benutzername oder -Mailadresse',
            value: 'student@hs-anhalt.de',
          ),
          (label: 'Hochschul-Passwort', value: 'secret'),
        ]) {
      await tester.enterText(
        find.widgetWithText(TextFormField, field.label),
        field.value,
      );
    }
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('Prüfen und sicher hinterlegen'));
    await tester.tap(find.text('Prüfen und sicher hinterlegen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Verbindung fehlgeschlagen'), findsOneWidget);
    expect(store.value, isNull);
    expect(store.writes, 0);
  });

  testWidgets('setup sheet announces and locks credential verification', (
    WidgetTester tester,
  ) async {
    final Completer<void> connectGate = Completer<void>();
    final Completer<void> connectStarted = Completer<void>();
    final _MemoryIdentityStore store = _MemoryIdentityStore();
    final Map<DirectService, _Adapter> adapters = <DirectService, _Adapter>{
      for (final DirectService service in DirectService.values)
        service: service == DirectService.moodle
            ? _Adapter(connectGate: connectGate, connectStarted: connectStarted)
            : _Adapter(),
    };
    await _pump(tester, store: store, adapters: adapters);
    await tester.pump();

    await tester.tap(find.byTooltip('Moodle verbinden'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Hochschul-Benutzername oder -Mailadresse',
      ),
      'student@hs-anhalt.de',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hochschul-Passwort'),
      'secret',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('Prüfen und sicher hinterlegen'));
    await tester.tap(find.text('Prüfen und sicher hinterlegen'));
    await connectStarted.future;
    await tester.pump();

    expect(find.text('Zugang wird geprüft …'), findsOneWidget);
    expect(find.bySemanticsLabel('Zugang wird geprüft …'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Abbrechen'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widgetList<PopScope>(find.byType(PopScope))
          .any((PopScope scope) => !scope.canPop),
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Passwort anzeigen'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    connectGate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('account update reports a failed reconnect on its service row', (
    WidgetTester tester,
  ) async {
    final _MemoryIdentityStore store = _MemoryIdentityStore()
      ..value = _identity;
    final Map<DirectService, _Adapter> adapters = <DirectService, _Adapter>{
      for (final DirectService service in DirectService.values)
        service: _Adapter(),
    };
    adapters[DirectService.moodle]!.connectError = StateError('rejected');
    await _pump(
      tester,
      store: store,
      adapters: adapters,
      connected: const <DirectService>[
        DirectService.mail,
        DirectService.moodle,
      ],
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Zugangsdaten aktualisieren'));
    await tester.tap(find.text('Zugangsdaten aktualisieren'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Hochschul-Benutzername oder -Mailadresse',
      ),
      'replacement@hs-anhalt.de',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hochschul-Passwort'),
      'new-secret',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('Prüfen und sicher hinterlegen'));
    await tester.tap(find.text('Prüfen und sicher hinterlegen'));
    await tester.pumpAndSettle();

    expect(store.value?.identifier, 'replacement@hs-anhalt.de');
    expect(
      find.textContaining('Moodle konnte mit den neuen Zugangsdaten'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the generic account sheet never offers HSA-GPT as validating service',
    (WidgetTester tester) async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final Map<DirectService, _Adapter> adapters = <DirectService, _Adapter>{
        for (final DirectService service in DirectService.values)
          service: _Adapter(),
      };
      await _pump(tester, store: store, adapters: adapters);
      await tester.pump();

      await tester.ensureVisible(find.text('Zugangsdaten aktualisieren'));
      await tester.tap(find.text('Zugangsdaten aktualisieren'));
      await tester.pumpAndSettle();

      final DropdownButton<DirectService> dropdown = tester
          .widget<DropdownButton<DirectService>>(
            find.byType(DropdownButton<DirectService>),
          );
      final List<DirectService?> offered = dropdown.items!
          .map((DropdownMenuItem<DirectService> item) => item.value)
          .toList();
      expect(offered, isNot(contains(DirectService.hsaKi)));
      expect(offered, contains(DirectService.mail));
    },
  );

  testWidgets('does not overflow at 320 dp and 200 percent text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _MemoryIdentityStore store = _MemoryIdentityStore()
      ..value = _identity;
    final Map<DirectService, _Adapter> adapters = <DirectService, _Adapter>{
      for (final DirectService service in DirectService.values)
        service: _Adapter(),
    };
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: UniversityAccountCard()),
      ),
      overrides: _overrides(adapters: adapters),
      universityIdentityStore: store,
      textScaler: const TextScaler.linear(2),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'surfaces a secure-store load failure and disables account changes',
    (WidgetTester tester) async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..readError = const UniversityAccountFailure(
          UniversityAccountFailureKind.secureStorageUnavailable,
        );
      final Map<DirectService, _Adapter> adapters = <DirectService, _Adapter>{
        for (final DirectService service in DirectService.values)
          service: _Adapter(),
      };
      await _pump(tester, store: store, adapters: adapters);
      await tester.pump();

      expect(
        find.textContaining('sichere Schlüsselspeicher ist nicht verfügbar'),
        findsOneWidget,
      );
      final Iterable<IconButton> centralActions = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .where(
            (IconButton button) =>
                button.tooltip?.contains('verbinden') == true &&
                button.tooltip != 'Nextcloud verbinden',
          );
      expect(centralActions, isNotEmpty);
      expect(
        centralActions.every((IconButton button) => button.onPressed == null),
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Nextcloud verbinden'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
