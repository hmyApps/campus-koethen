// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/features/grades/application/grade_account_controller.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/mail/application/mail_account_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/data/mail_local_data_coordinator.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/moodle/application/moodle_account_controller.dart';
import 'package:campus_koethen/features/moodle/application/moodle_providers.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/settings/application/sign_out_everywhere_controller.dart';
import 'package:campus_koethen/features/settings/domain/direct_service.dart';
import 'package:campus_koethen/features/settings/presentation/sign_out_everywhere_tile.dart';
import 'package:campus_koethen/features/university_account/application/university_account_controller.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:campus_koethen/features/university_account/application/university_service_connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grades.dart';
import '../../support/fake_mail.dart';
import '../../support/fake_moodle.dart';
import '../../support/pump_app.dart';

const MailCredentials _mailCreds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);
const GradeCredentials _gradeCreds = GradeCredentials(
  username: 'stud',
  password: 'pw',
);
final MoodleToken _moodleToken = MoodleToken(
  value: 'tok',
  userId: 7,
  username: 'stud',
);
const UniversityIdentity _identity = UniversityIdentity(
  identifier: 'stud@hs-anhalt.de',
  password: 'pw',
);

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;
  Object? clearError;
  int clears = 0;

  @override
  Future<UniversityIdentity?> read() async => value;

  @override
  Future<void> write(UniversityIdentity identity) async => value = identity;

  @override
  Future<void> clear() async {
    clears++;
    if (clearError != null) throw clearError!;
    value = null;
  }
}

/// A token store that fails to clear exactly [failTimes] times, then succeeds
/// — mimics a transient "secure storage busy" failure a retry can recover
/// from.
class _FlakyMoodleTokenStore extends InMemoryMoodleTokenStore {
  _FlakyMoodleTokenStore({this.failTimes = 0});

  int failTimes;

  @override
  Future<void> clear() async {
    if (failTimes > 0) {
      failTimes--;
      throw Exception('secure storage unavailable');
    }
    await super.clear();
  }
}

class _Fixtures {
  _Fixtures({
    InMemoryMailCredentialStore? mailStore,
    FakeMailGateway? mailGateway,
    InMemoryGradeCredentialStore? gradeStore,
    InMemoryMoodleTokenStore? moodleStore,
  }) : mailStore = mailStore ?? InMemoryMailCredentialStore(),
       mailGateway = mailGateway ?? FakeMailGateway(),
       gradeStore = gradeStore ?? InMemoryGradeCredentialStore(),
       moodleStore = moodleStore ?? InMemoryMoodleTokenStore();

  final InMemoryMailCredentialStore mailStore;
  final FakeMailGateway mailGateway;
  final InMemoryGradeCredentialStore gradeStore;
  final InMemoryMoodleTokenStore moodleStore;
  final _MemoryIdentityStore identityStore = _MemoryIdentityStore();
  final InMemoryGradeCacheStore gradeCache = InMemoryGradeCacheStore();
  final InMemoryGradePortalStore gradePortalStore = InMemoryGradePortalStore();
  final InMemoryMoodleCacheStore moodleCache = InMemoryMoodleCacheStore();

  List<Override> get overrides => <Override>[
    mailCredentialStoreProvider.overrideWithValue(mailStore),
    mailGatewayProvider.overrideWithValue(mailGateway),
    mailLocalDataCoordinatorProvider.overrideWithValue(
      MailLocalDataCoordinator(
        credentials: mailStore,
        cache: MemoryMailCache(),
        wipeIntent: MemoryMailWipeIntentStore(),
      ),
    ),
    gradeCredentialStoreProvider.overrideWithValue(gradeStore),
    gradeCacheStoreProvider.overrideWithValue(gradeCache),
    gradePortalStoreProvider.overrideWithValue(gradePortalStore),
    gradesGatewayProvider.overrideWithValue(FakeGradesGateway()),
    moodleTokenStoreProvider.overrideWithValue(moodleStore),
    moodleCacheStoreProvider.overrideWithValue(moodleCache),
  ];

  Future<void> signInAll() async {
    await mailStore.write(_mailCreds);
    await gradeStore.write(_gradeCreds);
    await moodleStore.write(_moodleToken);
    await identityStore.write(_identity);
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Fixtures fixtures, {
  Locale locale = AppLocales.german,
}) => pumpScreen(
  tester,
  const Scaffold(body: SignOutEverywhereTile()),
  overrides: fixtures.overrides,
  universityIdentityStore: fixtures.identityStore,
  locale: locale,
);

void main() {
  group('nobody signed in', () {
    testWidgets('the tile is disabled and names no service', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _Fixtures());
      await tester.pump();

      final ListTile tile = tester.widget(find.byType(ListTile));
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      expect(find.text('Kein Hochschulzugang hinterlegt'), findsOneWidget);
    });
  });

  group('cancel', () {
    testWidgets('changes nothing', (WidgetTester tester) async {
      final _Fixtures fixtures = _Fixtures();
      await fixtures.mailStore.write(_mailCreds);
      await fixtures.identityStore.write(_identity);
      final ProviderContainer container = await _pump(tester, fixtures);
      await tester.pump();

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      // The confirmation names exactly the connected service.
      expect(find.text('Hochschulzugang vollständig löschen?'), findsOneWidget);
      expect(find.textContaining('Studentische E-Mail'), findsWidgets);

      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(await fixtures.mailStore.read(), isNotNull);
      expect(await fixtures.identityStore.read(), _identity);
      expect(
        container.read(mailAccountControllerProvider).value?.isSignedIn,
        isTrue,
      );
      expect(find.text('Hochschulzugang vollständig gelöscht.'), findsNothing);
    });
  });

  group('full success', () {
    testWidgets('signs every connected service out through its own path', (
      WidgetTester tester,
    ) async {
      final _Fixtures fixtures = _Fixtures();
      await fixtures.signInAll();
      final ProviderContainer container = await _pump(tester, fixtures);
      await tester.pump();

      expect(
        container.read(connectedDirectServicesProvider),
        containsAll(<DirectService>[
          DirectService.mail,
          DirectService.moodle,
          DirectService.grades,
        ]),
      );

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      // Confirmation names every connected service.
      expect(find.textContaining('Studentische E-Mail'), findsWidgets);
      expect(find.textContaining('Moodle'), findsWidgets);
      expect(find.textContaining('Noten'), findsWidgets);

      await tester.tap(find.text('Vollständig löschen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Hochschulzugang vollständig gelöscht.'),
        findsOneWidget,
      );
      expect(await fixtures.mailStore.read(), isNull);
      expect(await fixtures.gradeStore.read(), isNull);
      expect(await fixtures.moodleStore.read(), isNull);
      expect(await fixtures.identityStore.read(), isNull);
      expect(fixtures.gradeCache.clears, greaterThanOrEqualTo(1));
      expect(fixtures.moodleCache.clears, greaterThanOrEqualTo(1));
      expect(container.read(connectedDirectServicesProvider), isEmpty);
    });
  });

  group('partial failure', () {
    testWidgets('reports only the failed service and allows a scoped retry', (
      WidgetTester tester,
    ) async {
      final _FlakyMoodleTokenStore flakyMoodle = _FlakyMoodleTokenStore(
        failTimes: 1,
      );
      final _Fixtures fixtures = _Fixtures(moodleStore: flakyMoodle);
      await fixtures.signInAll();
      final ProviderContainer container = await _pump(tester, fixtures);
      await tester.pump();

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vollständig löschen'));
      await tester.pumpAndSettle();

      // Mail and grades succeeded and STAY signed out even though Moodle
      // failed — a partial result never reads as a full success.
      expect(find.text('Löschen unvollständig'), findsOneWidget);
      expect(find.textContaining('Moodle'), findsWidgets);
      expect(await fixtures.mailStore.read(), isNull);
      expect(await fixtures.gradeStore.read(), isNull);
      expect(await fixtures.moodleStore.read(), isNotNull);
      expect(await fixtures.identityStore.read(), _identity);
      expect(container.read(connectedDirectServicesProvider), <DirectService>[
        DirectService.moodle,
      ]);

      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Hochschulzugang vollständig gelöscht.'),
        findsOneWidget,
      );
      expect(await fixtures.moodleStore.read(), isNull);
      expect(await fixtures.identityStore.read(), isNull);
      expect(container.read(connectedDirectServicesProvider), isEmpty);
    });
  });

  group('after restart', () {
    testWidgets('every signed-out service asks for sign-in again', (
      WidgetTester tester,
    ) async {
      final _Fixtures fixtures = _Fixtures();
      await fixtures.signInAll();
      await _pump(tester, fixtures);
      await tester.pump();

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vollständig löschen'));
      await tester.pumpAndSettle();

      // Simulate a process restart: a brand-new container reading the very
      // same (now cleared) stores.
      final ProviderContainer restarted = ProviderContainer(
        overrides: <Override>[
          ...fixtures.overrides,
          universityIdentityStoreProvider.overrideWithValue(
            fixtures.identityStore,
          ),
        ],
      );
      addTearDown(restarted.dispose);

      expect(
        (await restarted.read(mailAccountControllerProvider.future)).isSignedIn,
        isFalse,
      );
      expect(
        await restarted.read(moodleAccountControllerProvider.future),
        isNull,
      );
      expect(
        (await restarted.read(
          gradeAccountControllerProvider.future,
        )).isSignedIn,
        isFalse,
      );
    });
  });

  testWidgets('renders in English', (WidgetTester tester) async {
    final _Fixtures fixtures = _Fixtures();
    await fixtures.mailStore.write(_mailCreds);
    await _pump(tester, fixtures, locale: AppLocales.english);
    await tester.pump();

    expect(find.text('Delete university access completely'), findsOneWidget);
    expect(
      find.text('1 connected service will be disconnected'),
      findsOneWidget,
    );

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('Delete university access completely?'), findsOneWidget);
  });

  testWidgets('can delete a retained identity when no service is connected', (
    WidgetTester tester,
  ) async {
    final _Fixtures fixtures = _Fixtures();
    await fixtures.identityStore.write(_identity);
    await _pump(tester, fixtures);
    await tester.pump();

    final ListTile tile = tester.widget(find.byType(ListTile));
    expect(tile.enabled, isTrue);

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollständig löschen'));
    await tester.pumpAndSettle();

    expect(await fixtures.identityStore.read(), isNull);
  });

  testWidgets('identity clear failure is reported and identity remains', (
    WidgetTester tester,
  ) async {
    final _Fixtures fixtures = _Fixtures();
    await fixtures.identityStore.write(_identity);
    fixtures.identityStore.clearError = StateError('secure storage busy');
    await _pump(tester, fixtures);
    await tester.pump();

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollständig löschen'));
    await tester.pumpAndSettle();

    expect(find.text('Löschen unvollständig'), findsOneWidget);
    expect(await fixtures.identityStore.read(), _identity);
  });

  testWidgets('the tile exposes an accessible label for screen readers', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final _Fixtures fixtures = _Fixtures();
    await fixtures.mailStore.write(_mailCreds);
    await _pump(tester, fixtures);
    await tester.pump();

    expect(
      find.bySemanticsLabel(RegExp('Hochschulzugang vollständig löschen')),
      findsOneWidget,
    );
    handle.dispose();
  });

  test(
    'complete deletion waits for an in-flight + and wipes its result',
    () async {
      final Completer<void> verifyGate = Completer<void>();
      final Completer<void> verifyStarted = Completer<void>();
      final FakeMailGateway gateway = FakeMailGateway(
        verifyGate: verifyGate,
        verifyStarted: verifyStarted,
      );
      final _Fixtures fixtures = _Fixtures(mailGateway: gateway);
      await fixtures.identityStore.write(_identity);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          ...fixtures.overrides,
          universityIdentityStoreProvider.overrideWithValue(
            fixtures.identityStore,
          ),
        ],
      );
      addTearDown(container.dispose);

      final Future<void> connecting = container
          .read(universityServiceConnectorProvider)
          .connect(DirectService.mail);
      await verifyStarted.future;
      final Future<SignOutEverywhereResult> deleting = container
          .read(signOutEverywhereServiceProvider)
          .signOutAll();

      verifyGate.complete();
      await connecting;
      final SignOutEverywhereResult result = await deleting;

      expect(result.isFullSuccess, isTrue);
      expect(await fixtures.mailStore.read(), isNull);
      expect(await fixtures.identityStore.read(), isNull);
    },
  );
}
