// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/presentation/grade_tile.dart';
import 'package:campus_koethen/features/grades/presentation/grades_screen.dart';
import 'package:campus_koethen/features/grades/presentation/grade_setup_screen.dart';
import 'package:campus_koethen/features/more/presentation/more_screen.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grades.dart';
import '../../support/pump_app.dart';

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;
  int writes = 0;

  @override
  Future<UniversityIdentity?> read() async => value;

  @override
  Future<void> write(UniversityIdentity identity) async {
    writes++;
    value = identity;
  }

  @override
  Future<void> clear() async => value = null;
}

const GradeCredentials _creds = GradeCredentials(
  username: 'testuser',
  password: 'test-pw',
);
final DateTime _t0 = DateTime.utc(2026, 7, 26, 12);

List<Override> _grades({
  required FakeGradesGateway gateway,
  required InMemoryGradeCredentialStore store,
  required InMemoryGradeCacheStore cache,
  MutableClock? clock,
}) {
  return <Override>[
    legacyQisGatewayProvider.overrideWithValue(gateway),
    hisInOneGatewayProvider.overrideWithValue(gateway),
    gradesGatewayProvider.overrideWithValue(gateway),
    gradeCredentialStoreProvider.overrideWithValue(store),
    gradePortalStoreProvider.overrideWithValue(InMemoryGradePortalStore()),
    gradeCacheStoreProvider.overrideWithValue(cache),
    gradeClockProvider.overrideWithValue(clock ?? MutableClock(_t0)),
  ];
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('More lists the grades entry', (WidgetTester tester) async {
    await pumpScreen(tester, const MoreScreen());
    await tester.pumpAndSettle();
    expect(find.text('Noten'), findsOneWidget);
  });

  testWidgets('the credit account is shown as the average, not as a row', (
    WidgetTester tester,
  ) async {
    // The number comes from HIS-QIS unchanged, and the administrative
    // admission row has no business on a list of results.
    _tall(tester);
    await pumpScreen(
      tester,
      const GradesScreen(),
      overrides: _grades(
        gateway: FakeGradesGateway(
          report: GradeReport(<GradeEntry>[
            const GradeEntry(
              examNumber: '1',
              title: 'Analysis I',
              grade: Grade.graded(1.7),
              status: ExamStatus.passed,
              statusText: 'bestanden',
            ),
            const GradeEntry(
              examNumber: '2',
              title: 'Credit-Sammelkonto',
              grade: Grade.graded(2.4),
              status: ExamStatus.passed,
              statusText: 'bestanden',
            ),
            const GradeEntry(
              examNumber: '3',
              title: 'Zulassung zur Abschlussarbeit',
              grade: Grade.none(),
              status: ExamStatus.passed,
              statusText: 'bestanden',
            ),
          ]),
        ),
        store: InMemoryGradeCredentialStore()..write(_creds),
        cache: InMemoryGradeCacheStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Durchschnitt'), findsOneWidget);
    expect(find.text('2,4'), findsOneWidget);
    expect(find.text('Credit-Sammelkonto'), findsNothing);
    expect(find.text('Zulassung zur Abschlussarbeit'), findsNothing);
    // The real exam is untouched.
    expect(find.text('Analysis I'), findsOneWidget);
  });

  testWidgets('gate shows the setup screen when signed out', (
    WidgetTester tester,
  ) async {
    _tall(tester);
    await pumpScreen(
      tester,
      const GradesScreen(),
      overrides: _grades(
        gateway: FakeGradesGateway(),
        store: InMemoryGradeCredentialStore(),
        cache: InMemoryGradeCacheStore(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anmelden und Noten laden'), findsOneWidget);
    expect(find.text('Benutzername'), findsOneWidget);
  });

  testWidgets('setup requires consent before contacting the portal', (
    WidgetTester tester,
  ) async {
    _tall(tester);
    final gateway = FakeGradesGateway(report: sampleReport());
    await pumpScreen(
      tester,
      const GradesScreen(),
      overrides: _grades(
        gateway: gateway,
        store: InMemoryGradeCredentialStore(),
        cache: InMemoryGradeCacheStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'testuser');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-pw');
    await tester.tap(find.text('Anmelden und Noten laden'));
    await tester.pumpAndSettle();

    expect(
      find.text('Bitte stimme der lokalen Speicherung zu.'),
      findsOneWidget,
    );
    expect(gateway.fetchCalls, 0);
  });

  testWidgets('setup signs in and reveals the overview', (
    WidgetTester tester,
  ) async {
    _tall(tester);
    final gateway = FakeGradesGateway(report: sampleReport('Grundlagen'));
    final store = InMemoryGradeCredentialStore();
    final cache = InMemoryGradeCacheStore();
    await pumpScreen(
      tester,
      const GradesScreen(),
      overrides: _grades(gateway: gateway, store: store, cache: cache),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'testuser');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-pw');
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anmelden und Noten laden'));
    await tester.pumpAndSettle();

    expect(gateway.fetchCalls, 1);
    expect(store.writes, 1);
    expect(find.text('Grundlagen'), findsOneWidget);
    expect(find.textContaining('Zuletzt aktualisiert'), findsOneWidget);
  });

  testWidgets('overview shows the cached grades without an auto sync', (
    WidgetTester tester,
  ) async {
    final gateway = FakeGradesGateway();
    final store = InMemoryGradeCredentialStore()..write(_creds);
    final cache = InMemoryGradeCacheStore();
    await cache.writeReport(sampleReport('Grundlagen'));
    await cache.writeLastSuccessfulSync(_t0);
    await cache.writeLastAttemptedSync(_t0); // within 24h → no auto sync

    await pumpScreen(
      tester,
      const GradesScreen(),
      overrides: _grades(gateway: gateway, store: store, cache: cache),
    );
    await tester.pumpAndSettle();

    expect(find.text('Grundlagen'), findsOneWidget);
    expect(gateway.fetchCalls, 0, reason: 'the 24h gate blocks the auto sync');
  });

  testWidgets('delete asks for confirmation and returns to setup', (
    WidgetTester tester,
  ) async {
    _tall(tester);
    final store = InMemoryGradeCredentialStore()..write(_creds);
    final cache = InMemoryGradeCacheStore();
    await cache.writeReport(sampleReport());
    await cache.writeLastSuccessfulSync(_t0);
    await cache.writeLastAttemptedSync(_t0);

    await pumpScreen(
      tester,
      const GradesScreen(),
      overrides: _grades(
        gateway: FakeGradesGateway(),
        store: store,
        cache: cache,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noten-Verbindung und lokale Noten löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();

    expect(store.clears, greaterThanOrEqualTo(1));
    expect(cache.clears, greaterThanOrEqualTo(1));
    expect(find.text('Anmelden und Noten laden'), findsOneWidget);
  });

  group('university identity reuse', () {
    testWidgets(
      'ticking "also use for other services" retains the identity centrally',
      (WidgetTester tester) async {
        _tall(tester);
        final identityStore = _MemoryIdentityStore();
        await pumpScreen(
          tester,
          const GradeSetupScreen(),
          overrides: _grades(
            gateway: FakeGradesGateway(report: sampleReport()),
            store: InMemoryGradeCredentialStore(),
            cache: InMemoryGradeCacheStore(),
          ),
          universityIdentityStore: identityStore,
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).at(0), 'testuser');
        await tester.enterText(find.byType(TextFormField).at(1), 'test-pw');
        // Checkbox 0 is the grades-only storage consent, 1 is the new "also
        // use for other services" offer.
        await tester.tap(find.byType(Checkbox).at(0));
        await tester.tap(find.byType(Checkbox).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Anmelden und Noten laden'));
        await tester.pumpAndSettle();

        expect(identityStore.writes, 1);
        expect(identityStore.value?.identifier, 'testuser');
        expect(identityStore.value?.password, 'test-pw');
      },
    );

    testWidgets('hides the reuse offer once a central identity is stored', (
      WidgetTester tester,
    ) async {
      _tall(tester);
      await pumpScreen(
        tester,
        const GradeSetupScreen(),
        overrides: _grades(
          gateway: FakeGradesGateway(),
          store: InMemoryGradeCredentialStore(),
          cache: InMemoryGradeCacheStore(),
        ),
        universityIdentityStore: _MemoryIdentityStore()
          ..value = const UniversityIdentity(
            identifier: 'stud',
            password: 'pw',
          ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Diese Zugangsdaten auch für Mail, Moodle und Noten automatisch verwenden.',
        ),
        findsNothing,
      );
    });
  });

  testWidgets('announces and locks the grade sign-in loading state', (
    WidgetTester tester,
  ) async {
    _tall(tester);
    final FakeGradesGateway gateway = FakeGradesGateway()
      ..pendingReport = Completer<GradeReport>();
    await pumpScreen(
      tester,
      const GradeSetupScreen(),
      overrides: _grades(
        gateway: gateway,
        store: InMemoryGradeCredentialStore(),
        cache: InMemoryGradeCacheStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'testuser');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-pw');
    await tester.tap(find.byType(Checkbox).first);
    await tester.tap(find.text('Anmelden und Noten laden'));
    await tester.pump();

    expect(find.text('Noten werden geladen …'), findsOneWidget);
    expect(find.bySemanticsLabel('Noten werden aktualisiert'), findsOneWidget);
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
    expect(
      tester
          .widgetList<PopScope>(find.byType(PopScope))
          .any((PopScope scope) => !scope.canPop),
      isTrue,
    );

    gateway.pendingReport!.complete(sampleReport());
    await tester.pumpAndSettle();
  });

  testWidgets('a long report builds only the rows that are on screen', (
    WidgetTester tester,
  ) async {
    // A Studienverlauf is far longer than one screen. Every tile used to be
    // instantiated on every rebuild, however far below the fold it sat.
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      const GradesScreen(),
      overrides: _grades(
        gateway: FakeGradesGateway(
          report: GradeReport(<GradeEntry>[
            for (int i = 0; i < 60; i++)
              GradeEntry(
                examNumber: '$i',
                title: 'Pruefung $i',
                grade: const Grade.graded(2),
                status: ExamStatus.passed,
                statusText: 'bestanden',
              ),
          ]),
        ),
        store: InMemoryGradeCredentialStore()..write(_creds),
        cache: InMemoryGradeCacheStore(),
      ),
    );
    await tester.pumpAndSettle();

    final int built = tester.widgetList(find.byType(GradeTile)).length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60));

    // Scrolling reaches the rest — nothing is lost, it is only built later.
    await tester.scrollUntilVisible(
      find.text('Pruefung 59'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Pruefung 59'), findsOneWidget);
  });
}
