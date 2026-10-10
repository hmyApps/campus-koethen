// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/grades/application/grade_account_controller.dart';
import 'package:campus_koethen/features/grades/application/grades_controller.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/domain/grade_failure.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:campus_koethen/features/notifications/application/grade_change_notification.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/domain/notification_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grades.dart';
import '../../support/fake_notification_gateway.dart';

const GradeCredentials _creds = GradeCredentials(
  username: 'testuser',
  password: 'test-pw',
);

ProviderContainer _container({
  required FakeGradesGateway gateway,
  required InMemoryGradeCredentialStore store,
  required InMemoryGradeCacheStore cache,
  required MutableClock clock,
  InMemoryGradePortalStore? portalStore,
  GradeChangeNotification? gradeChangeNotification,
  List<GradeLinkedPersonalDataWiper>? wipers,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      if (wipers != null)
        gradeLinkedPersonalDataWipersProvider.overrideWith((Ref ref) => wipers),
      // Setup tries the per-portal gateways in order; pointing BOTH at the
      // same fake keeps every existing single-portal test scenario intact
      // (the first portal tried always answers deterministically).
      legacyQisGatewayProvider.overrideWithValue(gateway),
      hisInOneGatewayProvider.overrideWithValue(gateway),
      gradesGatewayProvider.overrideWithValue(gateway),
      gradeCredentialStoreProvider.overrideWithValue(store),
      // The accounts in these scenarios already chose their portal. The
      // one-time move of a choice-less 1.x account to HISinOne (which drops
      // its cache) is covered in grade_portal_selection_test.dart.
      gradePortalStoreProvider.overrideWithValue(
        portalStore ??
            (InMemoryGradePortalStore()..write(GradePortal.hisInOne)),
      ),
      gradeCacheStoreProvider.overrideWithValue(cache),
      gradeClockProvider.overrideWithValue(clock),
      if (gradeChangeNotification != null)
        gradeChangeNotificationProvider.overrideWithValue(
          gradeChangeNotification,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final DateTime t0 = DateTime.utc(2026, 7, 26, 12);

  group('account', () {
    test('starts signed out when the store is empty', () async {
      final c = _container(
        gateway: FakeGradesGateway(),
        store: InMemoryGradeCredentialStore(),
        cache: InMemoryGradeCacheStore(),
        clock: MutableClock(t0),
      );
      final GradeAccountState s = await c.read(
        gradeAccountControllerProvider.future,
      );
      expect(s.isSignedIn, isFalse);
    });

    test(
      'a failing linked-data wiper never breaks the signed-out read itself — '
      'every screen that watches this provider (including the HISinOne '
      'student-service gate) must still see a plain signed-out state, not an '
      'error, when the defensive wipe this runs on every build stumbles',
      () async {
        final c = ProviderContainer(
          overrides: <Override>[
            legacyQisGatewayProvider.overrideWithValue(FakeGradesGateway()),
            hisInOneGatewayProvider.overrideWithValue(FakeGradesGateway()),
            gradesGatewayProvider.overrideWithValue(FakeGradesGateway()),
            gradeCredentialStoreProvider.overrideWithValue(
              InMemoryGradeCredentialStore(),
            ),
            gradePortalStoreProvider.overrideWithValue(
              InMemoryGradePortalStore(),
            ),
            gradeCacheStoreProvider.overrideWithValue(
              InMemoryGradeCacheStore(),
            ),
            gradeClockProvider.overrideWithValue(MutableClock(t0)),
            gradeLinkedPersonalDataWipersProvider.overrideWith(
              (Ref ref) => <GradeLinkedPersonalDataWiper>[
                () async =>
                    throw const GradeFailure(GradeFailureKind.cacheUnavailable),
              ],
            ),
          ],
        );
        addTearDown(c.dispose);

        final GradeAccountState s = await c.read(
          gradeAccountControllerProvider.future,
        );
        expect(s.isSignedIn, isFalse);
      },
    );

    // D-06: a keystore read failure must reach the account screen's error
    // branch. Reading it as "signed out" ran the catch-up wipe of the wallet
    // and student-service data, and silently moved HISinOne accounts to the
    // legacy portal.
    test(
      'a credential read failure is an account error and wipes nothing',
      () async {
        int wipes = 0;
        final InMemoryGradeCredentialStore store =
            InMemoryGradeCredentialStore()
              ..write(_creds)
              ..readError = const GradeFailure(
                GradeFailureKind.secureStorageUnavailable,
              );
        final ProviderContainer c = _container(
          gateway: FakeGradesGateway(),
          store: store,
          cache: InMemoryGradeCacheStore(),
          clock: MutableClock(t0),
          wipers: <GradeLinkedPersonalDataWiper>[() async => wipes++],
        );

        await expectLater(
          c.read(gradeAccountControllerProvider.future),
          throwsA(
            const GradeFailure(GradeFailureKind.secureStorageUnavailable),
          ),
        );
        expect(wipes, 0, reason: 'no confirmed absence, no catch-up wipe');
      },
    );

    test('a portal-choice read failure is an account error, never a silent '
        'fallback to the legacy portal', () async {
      final InMemoryGradePortalStore portalStore = InMemoryGradePortalStore()
        ..write(GradePortal.hisInOne)
        ..readError = const GradeFailure(
          GradeFailureKind.secureStorageUnavailable,
        );
      final ProviderContainer c = _container(
        gateway: FakeGradesGateway(),
        store: InMemoryGradeCredentialStore()..write(_creds),
        cache: InMemoryGradeCacheStore(),
        clock: MutableClock(t0),
        portalStore: portalStore,
      );

      await expectLater(
        c.read(gradeAccountControllerProvider.future),
        throwsA(const GradeFailure(GradeFailureKind.secureStorageUnavailable)),
      );

      // The screen's retry re-reads once the keystore is available again.
      portalStore.readError = null;
      c.invalidate(gradeAccountControllerProvider);
      final GradeAccountState s = await c.read(
        gradeAccountControllerProvider.future,
      );
      expect(s.activePortal, GradePortal.hisInOne);
    });

    test('restores a stored account (username only, no password)', () async {
      final store = InMemoryGradeCredentialStore()..write(_creds);
      final c = _container(
        gateway: FakeGradesGateway(),
        store: store,
        cache: InMemoryGradeCacheStore(),
        clock: MutableClock(t0),
      );
      final GradeAccountState s = await c.read(
        gradeAccountControllerProvider.future,
      );
      expect(s.username, 'testuser');
      expect(s.toString().contains('test-pw'), isFalse);
    });

    test(
      'signIn verifies via the portal, then stores creds and seeds cache',
      () async {
        final gateway = FakeGradesGateway(report: sampleReport());
        final store = InMemoryGradeCredentialStore();
        final cache = InMemoryGradeCacheStore();
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: MutableClock(t0),
        );
        await c.read(gradeAccountControllerProvider.future);

        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: '  testuser ', password: 'test-pw');

        expect(gateway.fetchCalls, 1);
        expect(store.writes, 1);
        expect(store.lastWritten?.username, 'testuser');
        expect(cache.reportWrites, 1, reason: 'the initial report is cached');
        expect(await cache.readLastSuccessfulSync(), t0);
        expect(await cache.readLastAttemptedSync(), t0);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.isSignedIn,
          isTrue,
        );
      },
    );

    test(
      'switching accounts wipes the old report before publishing the new one',
      () async {
        final gateway = FakeGradesGateway(report: sampleReport('New account'));
        final store = InMemoryGradeCredentialStore()..write(_creds);
        final cache = InMemoryGradeCacheStore();
        await cache.writeReport(sampleReport('Old account'));
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: MutableClock(t0),
        );
        await c.read(gradeAccountControllerProvider.future);

        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'other-user', password: 'new-pw');

        expect(cache.clears, 1);
        expect((await cache.readReport())!.entries.single.title, 'New account');
        expect(store.lastWritten?.username, 'other-user');
        expect(
          c.read(gradeAccountControllerProvider).requireValue.username,
          'other-user',
        );
      },
    );

    test(
      'a failed account-switch cache wipe never leaves the old grades account shown as connected',
      () async {
        final gateway = FakeGradesGateway(report: sampleReport('New account'));
        final store = InMemoryGradeCredentialStore()..write(_creds);
        final cache = InMemoryGradeCacheStore();
        await cache.writeReport(sampleReport('Old account'));
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: MutableClock(t0),
        );
        await c.read(gradeAccountControllerProvider.future);
        cache.clearError = const GradeFailure(
          GradeFailureKind.cacheUnavailable,
        );

        await expectLater(
          c
              .read(gradeAccountControllerProvider.notifier)
              .signIn(username: 'other-user', password: 'new-password'),
          throwsA(const GradeFailure(GradeFailureKind.cacheUnavailable)),
        );

        expect(c.read(gradeAccountControllerProvider).hasError, isTrue);
      },
    );

    test('does NOT store credentials when the portal rejects them', () async {
      final gateway = FakeGradesGateway(
        error: const GradeFailure(GradeFailureKind.invalidCredentials),
      );
      final store = InMemoryGradeCredentialStore();
      final cache = InMemoryGradeCacheStore();
      final c = _container(
        gateway: gateway,
        store: store,
        cache: cache,
        clock: MutableClock(t0),
      );
      await c.read(gradeAccountControllerProvider.future);

      await expectLater(
        c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'testuser', password: 'wrong'),
        throwsA(isA<GradeFailure>()),
      );
      expect(store.writes, 0);
      expect(cache.reportWrites, 0);
      expect(
        c.read(gradeAccountControllerProvider).requireValue.isSignedIn,
        isFalse,
      );
    });

    test('surfaces a secure-storage failure and stays signed out', () async {
      final gateway = FakeGradesGateway(report: sampleReport());
      final store = InMemoryGradeCredentialStore(available: false);
      final c = _container(
        gateway: gateway,
        store: store,
        cache: InMemoryGradeCacheStore(),
        clock: MutableClock(t0),
      );
      await c.read(gradeAccountControllerProvider.future);

      await expectLater(
        c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'testuser', password: 'test-pw'),
        throwsA(
          isA<GradeFailure>().having(
            (GradeFailure e) => e.kind,
            'kind',
            GradeFailureKind.secureStorageUnavailable,
          ),
        ),
      );
      expect(
        c.read(gradeAccountControllerProvider).requireValue.isSignedIn,
        isFalse,
      );
    });

    test(
      'deleteEverything wipes credentials, cache, key and timestamps',
      () async {
        final store = InMemoryGradeCredentialStore()..write(_creds);
        final cache = InMemoryGradeCacheStore();
        await cache.writeReport(sampleReport());
        await cache.writeLastSuccessfulSync(t0);
        final c = _container(
          gateway: FakeGradesGateway(),
          store: store,
          cache: cache,
          clock: MutableClock(t0),
        );
        await c.read(gradeAccountControllerProvider.future);

        await c
            .read(gradeAccountControllerProvider.notifier)
            .deleteEverything();

        expect(store.clears, greaterThanOrEqualTo(1));
        expect(cache.clears, greaterThanOrEqualTo(1));
        expect(await cache.readReport(), isNull);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.isSignedIn,
          isFalse,
        );
      },
    );
  });

  group('sync policy', () {
    Future<ProviderContainer> signedIn({
      required FakeGradesGateway gateway,
      required InMemoryGradeCacheStore cache,
      required MutableClock clock,
    }) async {
      final store = InMemoryGradeCredentialStore()..write(_creds);
      final c = _container(
        gateway: gateway,
        store: store,
        cache: cache,
        clock: clock,
      );
      await c.read(gradeAccountControllerProvider.future);
      // Keep the controller alive like a screen would.
      c.listen(gradesControllerProvider, (_, _) {});
      await c.read(gradesControllerProvider.future);
      return c;
    }

    test('first open without a cache syncs', () async {
      final gateway = FakeGradesGateway(report: sampleReport());
      final cache = InMemoryGradeCacheStore();
      final c = await signedIn(
        gateway: gateway,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(gradesControllerProvider.notifier).maybeAutoSync();

      expect(gateway.fetchCalls, 1);
      expect(await cache.readReport(), isNotNull);
    });

    test('a cache younger than 24h prevents an automatic net call', () async {
      final gateway = FakeGradesGateway(report: sampleReport());
      final cache = InMemoryGradeCacheStore();
      await cache.writeLastAttemptedSync(t0.subtract(const Duration(hours: 1)));
      final c = await signedIn(
        gateway: gateway,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(gradesControllerProvider.notifier).maybeAutoSync();

      expect(gateway.fetchCalls, 0);
    });

    test('after 24h exactly one automatic attempt runs', () async {
      final gateway = FakeGradesGateway(report: sampleReport());
      final cache = InMemoryGradeCacheStore();
      await cache.writeLastAttemptedSync(
        t0.subtract(const Duration(hours: 25)),
      );
      final c = await signedIn(
        gateway: gateway,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(gradesControllerProvider.notifier).maybeAutoSync();

      expect(gateway.fetchCalls, 1);
    });

    test('concurrent automatic syncs cause only one portal call', () async {
      final gateway = FakeGradesGateway(
        report: sampleReport(),
        delay: const Duration(milliseconds: 30),
      );
      final cache = InMemoryGradeCacheStore();
      final c = await signedIn(
        gateway: gateway,
        cache: cache,
        clock: MutableClock(t0),
      );

      final notifier = c.read(gradesControllerProvider.notifier);
      await Future.wait(<Future<void>>[
        notifier.maybeAutoSync(),
        notifier.maybeAutoSync(),
      ]);

      expect(gateway.fetchCalls, 1);
    });

    test('manual refresh bypasses the 24h gate', () async {
      final gateway = FakeGradesGateway(report: sampleReport());
      final cache = InMemoryGradeCacheStore();
      await cache.writeLastAttemptedSync(t0); // just attempted
      final c = await signedIn(
        gateway: gateway,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(gradesControllerProvider.notifier).refresh();

      expect(gateway.fetchCalls, 1);
    });

    test(
      'a newly entered result reaches the immediate notification service',
      () async {
        final FakeNotificationGateway notifications = FakeNotificationGateway();
        final GradeChangeNotification service = GradeChangeNotification(
          gateway: notifications,
          preferences: const NotificationPreferences(optedIn: true),
          permission: NotificationPermissionStatus.granted,
          title: 'Neue Note eingetragen',
          body: 'Notenspiegel öffnen',
        );
        final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
        await cache.writeReport(
          GradeReport(<GradeEntry>[
            GradeEntry(
              examNumber: '1',
              title: 'Grundlagen',
              grade: const Grade.none(),
              status: ExamStatus.present,
              statusText: 'vorhanden',
              examDate: DateTime(2026, 2, 12),
            ),
          ]),
        );
        final InMemoryGradeCredentialStore store =
            InMemoryGradeCredentialStore()..write(_creds);
        final ProviderContainer c = _container(
          gateway: FakeGradesGateway(report: sampleReport()),
          store: store,
          cache: cache,
          clock: MutableClock(t0),
          gradeChangeNotification: service,
        );
        await c.read(gradeAccountControllerProvider.future);
        await c.read(gradesControllerProvider.future);

        await c.read(gradesControllerProvider.notifier).refresh();

        expect(notifications.shown, hasLength(1));
      },
    );

    test('logout waits for and discards a delayed sync response', () async {
      final Completer<GradeReport> response = Completer<GradeReport>();
      final gateway = FakeGradesGateway()..pendingReport = response;
      final cache = InMemoryGradeCacheStore();
      final c = await signedIn(
        gateway: gateway,
        cache: cache,
        clock: MutableClock(t0),
      );

      final Future<void> refresh = c
          .read(gradesControllerProvider.notifier)
          .refresh();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.fetchCalls, 1);

      bool logoutCompleted = false;
      final Future<void> logout = c
          .read(gradeAccountControllerProvider.notifier)
          .deleteEverything()
          .whenComplete(() => logoutCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(
        logoutCompleted,
        isFalse,
        reason: 'the wipe must follow the last in-flight cache write',
      );

      response.complete(sampleReport('Verspätete Antwort'));
      await Future.wait(<Future<void>>[refresh, logout]);

      expect(cache.isEmpty, isTrue);
      expect(
        c.read(gradeAccountControllerProvider).requireValue.isSignedIn,
        isFalse,
      );
      expect(c.read(gradesControllerProvider).value?.report, isNull);
    });

    test('a failed sync keeps the old cache and lastSuccessfulSync', () async {
      final gateway = FakeGradesGateway(
        error: const GradeFailure(GradeFailureKind.timeout),
      );
      final cache = InMemoryGradeCacheStore();
      await cache.writeReport(sampleReport('Alt'));
      await cache.writeLastSuccessfulSync(t0.subtract(const Duration(days: 2)));
      final c = await signedIn(
        gateway: gateway,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(gradesControllerProvider.notifier).refresh();

      final GradesViewState s = c.read(gradesControllerProvider).requireValue;
      expect(s.error?.kind, GradeFailureKind.timeout);
      expect(s.report, isNotNull, reason: 'the old cache stays visible');
      expect(s.report!.entries.single.title, 'Alt');
      expect(
        cache.reportWrites,
        1,
        reason: 'the failed sync did not overwrite',
      );
      expect(
        await cache.readLastSuccessfulSync(),
        t0.subtract(const Duration(days: 2)),
      );
    });

    test('lastSuccessfulSync changes only on success', () async {
      final gateway = FakeGradesGateway(report: sampleReport());
      final cache = InMemoryGradeCacheStore();
      final c = await signedIn(
        gateway: gateway,
        cache: cache,
        clock: MutableClock(t0),
      );

      await c.read(gradesControllerProvider.notifier).refresh();

      expect(await cache.readLastSuccessfulSync(), t0);
    });

    test(
      'a failed auto attempt is not retried on every build; manual still works',
      () async {
        final gateway = FakeGradesGateway(
          error: const GradeFailure(GradeFailureKind.portalUnavailable),
        );
        final cache = InMemoryGradeCacheStore();
        final clock = MutableClock(t0);
        final c = await signedIn(gateway: gateway, cache: cache, clock: clock);
        final notifier = c.read(gradesControllerProvider.notifier);

        await notifier
            .maybeAutoSync(); // attempt #1 (fails, records lastAttempt)
        await notifier.maybeAutoSync(); // within 24h → skipped
        expect(gateway.fetchCalls, 1);

        // The user can still force a sync.
        await notifier.refresh();
        expect(gateway.fetchCalls, 2);
      },
    );
  });

  // Regression for LEVIORA-154: an empty answer must never replace grades we
  // already have. HISinOne answers with an empty Leistungen page for accounts
  // whose results live in HIS-QIS — if that ever reaches a refresh, the cached
  // Notenspiegel has to survive it.
  group('an empty report never overwrites a non-empty cache', () {
    test(
      'keeps the cache, keeps lastSuccessfulSync, surfaces the anomaly',
      () async {
        final gateway = FakeGradesGateway(report: sampleReport('Grundlagen'));
        final store = InMemoryGradeCredentialStore()..write(_creds);
        final cache = InMemoryGradeCacheStore();
        final clock = MutableClock(t0);
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: clock,
        );
        await c.read(gradeAccountControllerProvider.future);
        await c.read(gradesControllerProvider.future);
        await c.read(gradesControllerProvider.notifier).refresh();

        final DateTime firstSync = c
            .read(gradesControllerProvider)
            .requireValue
            .lastSuccessfulSync!;

        // The portal now answers with nothing at all.
        gateway.report = const GradeReport(<GradeEntry>[]);
        clock.advance(const Duration(days: 2));
        await c.read(gradesControllerProvider.notifier).refresh();

        final GradesViewState after = c
            .read(gradesControllerProvider)
            .requireValue;
        expect(after.report!.entries.single.title, 'Grundlagen');
        expect(after.lastSuccessfulSync, firstSync);
        expect(after.error?.kind, GradeFailureKind.portalStructureChanged);
        expect((await cache.readReport())!.entries, hasLength(1));
      },
    );

    test(
      'an empty report IS cached when there is nothing cached yet',
      () async {
        final gateway = FakeGradesGateway(
          report: const GradeReport(<GradeEntry>[]),
        );
        final store = InMemoryGradeCredentialStore()..write(_creds);
        final cache = InMemoryGradeCacheStore();
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: MutableClock(t0),
        );
        await c.read(gradeAccountControllerProvider.future);
        await c.read(gradesControllerProvider.future);
        await c.read(gradesControllerProvider.notifier).refresh();

        final GradesViewState after = c
            .read(gradesControllerProvider)
            .requireValue;
        expect(after.report!.isEmpty, isTrue);
        expect(after.error, isNull);
        expect(after.lastSuccessfulSync, isNotNull);
      },
    );
  });

  group('local wipe is reported honestly', () {
    test(
      'credential deletion failure still attempts portal and cache wipes',
      () async {
        final store = InMemoryGradeCredentialStore()..write(_creds);
        final cache = InMemoryGradeCacheStore();
        await cache.writeReport(sampleReport());
        final portalStore = InMemoryGradePortalStore()
          ..write(GradePortal.hisInOne);
        final c = _container(
          gateway: FakeGradesGateway(),
          store: store,
          cache: cache,
          clock: MutableClock(t0),
          portalStore: portalStore,
        );
        await c.read(gradeAccountControllerProvider.future);
        store.clearError = const GradeFailure(
          GradeFailureKind.secureStorageUnavailable,
        );

        await expectLater(
          c.read(gradeAccountControllerProvider.notifier).deleteEverything(),
          throwsA(
            const GradeFailure(GradeFailureKind.secureStorageUnavailable),
          ),
        );

        expect(portalStore.clears, 1);
        expect(cache.clears, 1);
        expect(cache.isEmpty, isTrue);
        expect(
          c.read(gradeAccountControllerProvider).value?.isSignedIn ?? false,
          isTrue,
        );
      },
    );

    test(
      'deleteEverything throws and stays signed in when the cache survives',
      () async {
        // The whole point of "delete credentials and local grades" is that
        // afterwards nothing is left. Swallowing a failed clear reported
        // "signed out" while the encrypted report and its key were still on
        // the device — the one claim this path must never make falsely.
        final gateway = FakeGradesGateway(report: sampleReport());
        final store = InMemoryGradeCredentialStore();
        final cache = InMemoryGradeCacheStore();
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: MutableClock(t0),
        );
        await c.read(gradeAccountControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: _creds.username, password: _creds.password);

        cache.clearError = StateError('keystore unavailable');

        await expectLater(
          c.read(gradeAccountControllerProvider.notifier).deleteEverything(),
          throwsA(
            isA<GradeFailure>().having(
              (GradeFailure f) => f.kind,
              'kind',
              GradeFailureKind.cacheUnavailable,
            ),
          ),
        );

        // Credentials are gone (that step succeeded) but the state must NOT
        // claim a clean signed-out account while the cache is still there.
        expect(cache.isEmpty, isFalse);
        expect(
          c.read(gradeAccountControllerProvider).value?.isSignedIn ?? false,
          isTrue,
        );
      },
    );

    test(
      'deleteEverything still attempts every store before it throws',
      () async {
        final gateway = FakeGradesGateway(report: sampleReport());
        final store = InMemoryGradeCredentialStore();
        final cache = InMemoryGradeCacheStore();
        final portalStore = InMemoryGradePortalStore();
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: MutableClock(t0),
          portalStore: portalStore,
        );
        await c.read(gradeAccountControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: _creds.username, password: _creds.password);

        final int clearsBefore = cache.clears;
        cache.clearError = StateError('keystore unavailable');
        await expectLater(
          c.read(gradeAccountControllerProvider.notifier).deleteEverything(),
          throwsA(isA<GradeFailure>()),
        );

        // A partial wipe that removed more is better than one that stopped at
        // the first error, so the portal choice is cleared regardless.
        expect(await store.read(), isNull);
        expect(portalStore.clears, 1);
        expect(cache.clears, clearsBefore + 1);
      },
    );

    test(
      'switchPortal aborts when the old portal cache cannot be cleared',
      () async {
        // Writing the new portal over a cache that still holds the old
        // portal's report showed those grades under the new portal's host —
        // exactly what docs/grades.md rules out.
        final gateway = FakeGradesGateway(report: sampleReport());
        final store = InMemoryGradeCredentialStore();
        final cache = InMemoryGradeCacheStore();
        final portalStore = InMemoryGradePortalStore();
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: MutableClock(t0),
          portalStore: portalStore,
        );
        await c.read(gradeAccountControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: _creds.username, password: _creds.password);

        final GradePortal before = c
            .read(gradeAccountControllerProvider)
            .requireValue
            .activePortal!;
        final GradePortal target = before == GradePortal.hisInOne
            ? GradePortal.hisQisLegacy
            : GradePortal.hisInOne;
        final int writesBefore = portalStore.writes;

        cache.clearError = StateError('cache locked');
        await expectLater(
          c.read(gradeAccountControllerProvider.notifier).switchPortal(target),
          throwsA(isA<StateError>()),
        );

        // Neither the stored choice nor the published state moved.
        expect(portalStore.writes, writesBefore);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.activePortal,
          before,
        );
      },
    );

    // R3-2-N02: an abandoned switch must not leave the grades session
    // deactivated — refresh used to do nothing at all until an app restart.
    test(
      'an aborted switchPortal (cache clear failed) leaves refresh working on '
      'the unchanged portal',
      () async {
        final FakeGradesGateway gateway = FakeGradesGateway(
          report: sampleReport(),
        );
        final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
        final ProviderContainer c = _container(
          gateway: gateway,
          store: InMemoryGradeCredentialStore(),
          cache: cache,
          clock: MutableClock(t0),
        );
        await c.read(gradeAccountControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: _creds.username, password: _creds.password);
        c.listen(gradesControllerProvider, (_, _) {});
        await c.read(gradesControllerProvider.future);
        final GradePortal before = c
            .read(gradeAccountControllerProvider)
            .requireValue
            .activePortal!;

        cache.clearError = StateError('cache locked');
        await expectLater(
          c
              .read(gradeAccountControllerProvider.notifier)
              .switchPortal(
                before == GradePortal.hisInOne
                    ? GradePortal.hisQisLegacy
                    : GradePortal.hisInOne,
              ),
          throwsA(isA<StateError>()),
        );
        cache.clearError = null;
        final int callsBefore = gateway.fetchCalls;

        await c.read(gradesControllerProvider.notifier).refresh();

        expect(gateway.fetchCalls, callsBefore + 1);
        expect(c.read(gradesControllerProvider).requireValue.error, isNull);
      },
    );

    test(
      'an aborted switchPortal (linked wipe failed) re-activates the session '
      'and keeps the stored portal choice',
      () async {
        final FakeGradesGateway gateway = FakeGradesGateway(
          report: sampleReport(),
        );
        final InMemoryGradePortalStore portalStore = InMemoryGradePortalStore();
        bool failWipe = false;
        final ProviderContainer c = _container(
          gateway: gateway,
          store: InMemoryGradeCredentialStore(),
          cache: InMemoryGradeCacheStore(),
          clock: MutableClock(t0),
          portalStore: portalStore,
          wipers: <GradeLinkedPersonalDataWiper>[
            () async {
              if (failWipe) throw StateError('wallet locked');
            },
          ],
        );
        await c.read(gradeAccountControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: _creds.username, password: _creds.password);
        c.listen(gradesControllerProvider, (_, _) {});
        await c.read(gradesControllerProvider.future);
        final GradePortal before = portalStore.lastWritten!;
        final int writesBefore = portalStore.writes;

        failWipe = true;
        await expectLater(
          c
              .read(gradeAccountControllerProvider.notifier)
              .switchPortal(
                before == GradePortal.hisInOne
                    ? GradePortal.hisQisLegacy
                    : GradePortal.hisInOne,
              ),
          throwsA(const GradeFailure(GradeFailureKind.cacheUnavailable)),
        );
        final int callsBefore = gateway.fetchCalls;

        await c.read(gradesControllerProvider.notifier).refresh();

        expect(portalStore.writes, writesBefore);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.activePortal,
          before,
        );
        expect(gateway.fetchCalls, callsBefore + 1);
      },
    );

    test('a switchPortal whose portal-choice write fails is surfaced as an '
        'account error instead of a silently dead session', () async {
      final InMemoryGradePortalStore portalStore = InMemoryGradePortalStore();
      final ProviderContainer c = _container(
        gateway: FakeGradesGateway(report: sampleReport()),
        store: InMemoryGradeCredentialStore(),
        cache: InMemoryGradeCacheStore(),
        clock: MutableClock(t0),
        portalStore: portalStore,
      );
      await c.read(gradeAccountControllerProvider.future);
      await c
          .read(gradeAccountControllerProvider.notifier)
          .signIn(username: _creds.username, password: _creds.password);
      final GradePortal before = portalStore.lastWritten!;

      portalStore.writeError = const GradeFailure(
        GradeFailureKind.secureStorageUnavailable,
      );
      await expectLater(
        c
            .read(gradeAccountControllerProvider.notifier)
            .switchPortal(
              before == GradePortal.hisInOne
                  ? GradePortal.hisQisLegacy
                  : GradePortal.hisInOne,
            ),
        throwsA(const GradeFailure(GradeFailureKind.secureStorageUnavailable)),
      );

      // The stored choice is now unknown; the screen's retry re-reads it
      // from secure storage instead of trusting either portal.
      expect(c.read(gradeAccountControllerProvider).hasError, isTrue);
    });
  });

  // D-01: the "new grade" diff and the empty-report guard compare against the
  // PERSISTED last successful report (docs/grades.md), never against whatever
  // happens to be in memory at the moment a sync starts.
  group('the sync baseline is the persisted cache', () {
    GradeChangeNotification notificationService(
      FakeNotificationGateway gateway,
    ) => GradeChangeNotification(
      gateway: gateway,
      preferences: const NotificationPreferences(optedIn: true),
      permission: NotificationPermissionStatus.granted,
      title: 'Neue Note eingetragen',
      body: 'Notenspiegel öffnen',
    );

    GradeReport pendingReport() => GradeReport(<GradeEntry>[
      GradeEntry(
        examNumber: '1',
        title: 'Grundlagen',
        grade: const Grade.none(),
        status: ExamStatus.present,
        statusText: 'vorhanden',
      ),
    ]);

    test('an automatic sync started before the screen state finished loading '
        'never lets an empty answer replace the cached grades', () async {
      final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
      await cache.writeReport(sampleReport('Grundlagen'));
      final FakeGradesGateway gateway = FakeGradesGateway(
        report: const GradeReport(<GradeEntry>[]),
      );
      final ProviderContainer c = _container(
        gateway: gateway,
        store: InMemoryGradeCredentialStore()..write(_creds),
        cache: cache,
        clock: MutableClock(t0),
      );
      await c.read(gradeAccountControllerProvider.future);
      c.listen(gradesControllerProvider, (_, _) {});

      // Exactly what the overview screen's post-frame callback does: no
      // prior `await future`, so build() may still be reading the cache.
      await c.read(gradesControllerProvider.notifier).maybeAutoSync();

      expect(gateway.fetchCalls, 1);
      expect((await cache.readReport())!.entries.single.title, 'Grundlagen');
      expect(cache.reportWrites, 1, reason: 'only the seeded write');
      final GradesViewState s = c.read(gradesControllerProvider).requireValue;
      expect(s.error?.kind, GradeFailureKind.portalStructureChanged);
      expect(s.report!.entries.single.title, 'Grundlagen');
    });

    test('an automatic sync started before the screen state finished loading '
        'still announces a newly entered grade', () async {
      final FakeNotificationGateway notifications = FakeNotificationGateway();
      final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
      await cache.writeReport(pendingReport());
      final ProviderContainer c = _container(
        gateway: FakeGradesGateway(report: sampleReport()),
        store: InMemoryGradeCredentialStore()..write(_creds),
        cache: cache,
        clock: MutableClock(t0),
        gradeChangeNotification: notificationService(notifications),
      );
      await c.read(gradeAccountControllerProvider.future);
      c.listen(gradesControllerProvider, (_, _) {});

      await c.read(gradesControllerProvider.notifier).maybeAutoSync();

      expect(notifications.shown, hasLength(1));
    });

    test('after a portal switch an empty first report becomes the new baseline '
        'instead of being reported as a structure change', () async {
      final FakeGradesGateway gateway = FakeGradesGateway(
        report: sampleReport('Altes Portal'),
      );
      final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
      final InMemoryGradePortalStore portalStore = InMemoryGradePortalStore();
      final ProviderContainer c = _container(
        gateway: gateway,
        store: InMemoryGradeCredentialStore(),
        cache: cache,
        clock: MutableClock(t0),
        portalStore: portalStore,
      );
      await c.read(gradeAccountControllerProvider.future);
      await c
          .read(gradeAccountControllerProvider.notifier)
          .signIn(username: _creds.username, password: _creds.password);
      c.listen(gradesControllerProvider, (_, _) {});
      await c.read(gradesControllerProvider.future);
      final GradePortal before = c
          .read(gradeAccountControllerProvider)
          .requireValue
          .activePortal!;

      await c
          .read(gradeAccountControllerProvider.notifier)
          .switchPortal(
            before == GradePortal.hisInOne
                ? GradePortal.hisQisLegacy
                : GradePortal.hisInOne,
          );
      gateway.report = const GradeReport(<GradeEntry>[]);
      // Exactly what the overview screen does right after the switch.
      await c.read(gradesControllerProvider.notifier).refresh();

      final GradesViewState s = c.read(gradesControllerProvider).requireValue;
      expect(s.error, isNull);
      expect(s.report!.isEmpty, isTrue);
      expect(s.lastSuccessfulSync, t0);
      expect((await cache.readReport())!.isEmpty, isTrue);
    });

    test(
      'after a portal switch the previous portal report is never the baseline '
      'for "new grade" notices',
      () async {
        final FakeNotificationGateway notifications = FakeNotificationGateway();
        final FakeGradesGateway gateway = FakeGradesGateway(
          report: pendingReport(),
        );
        final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
        final ProviderContainer c = _container(
          gateway: gateway,
          store: InMemoryGradeCredentialStore(),
          cache: cache,
          clock: MutableClock(t0),
          gradeChangeNotification: notificationService(notifications),
        );
        await c.read(gradeAccountControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: _creds.username, password: _creds.password);
        c.listen(gradesControllerProvider, (_, _) {});
        await c.read(gradesControllerProvider.future);
        final GradePortal before = c
            .read(gradeAccountControllerProvider)
            .requireValue
            .activePortal!;

        await c
            .read(gradeAccountControllerProvider.notifier)
            .switchPortal(
              before == GradePortal.hisInOne
                  ? GradePortal.hisQisLegacy
                  : GradePortal.hisInOne,
            );
        gateway.report = sampleReport();
        await c.read(gradesControllerProvider.notifier).refresh();

        expect(
          notifications.shown,
          isEmpty,
          reason: 'the first report of the new portal is only a baseline',
        );
        expect((await cache.readReport())!.entries.single.grade.isEmpty, false);
      },
    );
  });

  group('re-authentication after a password change', () {
    // D-05: re-authentication only replaces the credentials. Report, diff and
    // the empty-report guard belong to the regular refresh().
    test(
      'never writes the verification report — an empty answer cannot replace '
      'the cached grades',
      () async {
        final FakeGradesGateway gateway = FakeGradesGateway(
          report: sampleReport('Grundlagen'),
        );
        final InMemoryGradeCredentialStore store =
            InMemoryGradeCredentialStore();
        final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
        final MutableClock clock = MutableClock(t0);
        final ProviderContainer c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: clock,
        );
        await c.read(gradeAccountControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: _creds.username, password: _creds.password);
        final int writesBefore = cache.reportWrites;

        gateway.report = const GradeReport(<GradeEntry>[]);
        clock.advance(const Duration(days: 1));
        await c
            .read(gradeAccountControllerProvider.notifier)
            .reauthenticate(password: 'new-pw');

        expect((await store.read())?.password, 'new-pw');
        expect(cache.reportWrites, writesBefore);
        expect((await cache.readReport())!.entries.single.title, 'Grundlagen');
        expect(await cache.readLastSuccessfulSync(), t0);
        expect(await cache.readLastAttemptedSync(), t0);
      },
    );

    test(
      'a grade entered while the password was outdated is still announced by '
      'the refresh that follows',
      () async {
        final FakeNotificationGateway notifications = FakeNotificationGateway();
        final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
        await cache.writeReport(
          GradeReport(<GradeEntry>[
            GradeEntry(
              examNumber: '1',
              title: 'Grundlagen',
              grade: const Grade.none(),
              status: ExamStatus.present,
              statusText: 'vorhanden',
            ),
          ]),
        );
        final ProviderContainer c = _container(
          gateway: FakeGradesGateway(report: sampleReport()),
          store: InMemoryGradeCredentialStore()..write(_creds),
          cache: cache,
          clock: MutableClock(t0),
          gradeChangeNotification: GradeChangeNotification(
            gateway: notifications,
            preferences: const NotificationPreferences(optedIn: true),
            permission: NotificationPermissionStatus.granted,
            title: 'Neue Note eingetragen',
            body: 'Notenspiegel öffnen',
          ),
        );
        await c.read(gradeAccountControllerProvider.future);
        c.listen(gradesControllerProvider, (_, _) {});
        await c.read(gradesControllerProvider.future);

        await c
            .read(gradeAccountControllerProvider.notifier)
            .reauthenticate(password: 'new-pw');
        // Exactly what the overview screen does after a successful re-login.
        await c.read(gradesControllerProvider.notifier).refresh();

        expect(notifications.shown, hasLength(1));
      },
    );

    test(
      'keeps the cached report and the portal, and rewrites credentials',
      () async {
        final gateway = FakeGradesGateway(report: sampleReport());
        final store = InMemoryGradeCredentialStore();
        final cache = InMemoryGradeCacheStore();
        final portalStore = InMemoryGradePortalStore();
        final c = _container(
          gateway: gateway,
          store: store,
          cache: cache,
          clock: MutableClock(t0),
          portalStore: portalStore,
        );
        await c.read(gradeAccountControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: _creds.username, password: _creds.password);
        final GradePortal portal = c
            .read(gradeAccountControllerProvider)
            .requireValue
            .activePortal!;

        await c
            .read(gradeAccountControllerProvider.notifier)
            .reauthenticate(password: 'new-pw');

        expect((await store.read())?.password, 'new-pw');
        expect((await store.read())?.username, _creds.username);
        // The portal is not re-detected: a new password does not move an
        // account between portals.
        expect(
          c.read(gradeAccountControllerProvider).requireValue.activePortal,
          portal,
        );
        expect(cache.isEmpty, isFalse);
      },
    );

    test('a rejected password is never written', () async {
      final gateway = FakeGradesGateway(report: sampleReport());
      final store = InMemoryGradeCredentialStore();
      final cache = InMemoryGradeCacheStore();
      final c = _container(
        gateway: gateway,
        store: store,
        cache: cache,
        clock: MutableClock(t0),
      );
      await c.read(gradeAccountControllerProvider.future);
      await c
          .read(gradeAccountControllerProvider.notifier)
          .signIn(username: _creds.username, password: _creds.password);

      gateway.error = const GradeFailure(GradeFailureKind.invalidCredentials);
      await expectLater(
        c
            .read(gradeAccountControllerProvider.notifier)
            .reauthenticate(password: 'wrong-pw'),
        throwsA(isA<GradeFailure>()),
      );

      expect((await store.read())?.password, _creds.password);
    });
  });
}
