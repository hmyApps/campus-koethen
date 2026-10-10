// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/application/grade_account_controller.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/domain/grade_failure.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grades.dart';

ProviderContainer _container({
  required FakeGradesGateway hisInOne,
  required FakeGradesGateway legacy,
  InMemoryGradeCredentialStore? store,
  InMemoryGradePortalStore? portalStore,
  InMemoryGradeCacheStore? cache,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      hisInOneGatewayProvider.overrideWithValue(hisInOne),
      legacyQisGatewayProvider.overrideWithValue(legacy),
      gradeCredentialStoreProvider.overrideWithValue(
        store ?? InMemoryGradeCredentialStore(),
      ),
      gradePortalStoreProvider.overrideWithValue(
        portalStore ?? InMemoryGradePortalStore(),
      ),
      gradeCacheStoreProvider.overrideWithValue(
        cache ?? InMemoryGradeCacheStore(),
      ),
      gradeClockProvider.overrideWithValue(
        MutableClock(DateTime.utc(2026, 8, 19)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('setup tries hisInOne first, then hisQisLegacy', () {
    test(
      'a non-empty hisInOne report wins immediately — legacy is never called',
      () async {
        final hisInOne = FakeGradesGateway(
          report: sampleReport('HISinOne-Kurs'),
        );
        final legacy = FakeGradesGateway(report: sampleReport('Legacy-Kurs'));
        final c = _container(hisInOne: hisInOne, legacy: legacy);
        await c.read(gradeAccountControllerProvider.future);

        final GradeReport report = await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'u', password: 'p');

        expect(report.entries.single.title, 'HISinOne-Kurs');
        expect(hisInOne.fetchCalls, 1);
        expect(legacy.fetchCalls, 0);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.activePortal,
          GradePortal.hisInOne,
        );
      },
    );

    test(
      'hisInOne logs in but is empty → legacy is tried and, if non-empty, wins',
      () async {
        final hisInOne = FakeGradesGateway(
          report: const GradeReport(<GradeEntry>[]),
        );
        final legacy = FakeGradesGateway(report: sampleReport('Legacy-Kurs'));
        final c = _container(hisInOne: hisInOne, legacy: legacy);
        await c.read(gradeAccountControllerProvider.future);

        final GradeReport report = await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'u', password: 'p');

        expect(report.entries.single.title, 'Legacy-Kurs');
        expect(hisInOne.fetchCalls, 1);
        expect(legacy.fetchCalls, 1);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.activePortal,
          GradePortal.hisQisLegacy,
        );
      },
    );

    test(
      'both portals empty → the first successful portal stays active',
      () async {
        final hisInOne = FakeGradesGateway(
          report: const GradeReport(<GradeEntry>[]),
        );
        final legacy = FakeGradesGateway(
          report: const GradeReport(<GradeEntry>[]),
        );
        final c = _container(hisInOne: hisInOne, legacy: legacy);
        await c.read(gradeAccountControllerProvider.future);

        final GradeReport report = await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'u', password: 'p');

        expect(report.isEmpty, isTrue);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.activePortal,
          GradePortal.hisInOne,
          reason: 'hisInOne was tried first and logged in successfully',
        );
      },
    );

    test(
      'at most two login attempts: invalid on hisInOne lets legacy try ONCE, then aborts',
      () async {
        final hisInOne = FakeGradesGateway(
          error: const GradeFailure(GradeFailureKind.invalidCredentials),
        );
        final legacy = FakeGradesGateway(
          error: const GradeFailure(GradeFailureKind.invalidCredentials),
        );
        final c = _container(hisInOne: hisInOne, legacy: legacy);
        await c.read(gradeAccountControllerProvider.future);

        await expectLater(
          c
              .read(gradeAccountControllerProvider.notifier)
              .signIn(username: 'u', password: 'wrong'),
          throwsA(
            isA<GradeFailure>().having(
              (GradeFailure e) => e.kind,
              'kind',
              GradeFailureKind.invalidCredentials,
            ),
          ),
        );
        expect(hisInOne.fetchCalls, 1);
        expect(legacy.fetchCalls, 1);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.isSignedIn,
          isFalse,
        );
      },
    );

    test(
      'a device-side failure on the first portal aborts immediately (no second attempt)',
      () async {
        final hisInOne = FakeGradesGateway(
          error: const GradeFailure(GradeFailureKind.networkUnavailable),
        );
        final legacy = FakeGradesGateway(report: sampleReport());
        final c = _container(hisInOne: hisInOne, legacy: legacy);
        await c.read(gradeAccountControllerProvider.future);

        await expectLater(
          c
              .read(gradeAccountControllerProvider.notifier)
              .signIn(username: 'u', password: 'p'),
          throwsA(
            isA<GradeFailure>().having(
              (GradeFailure e) => e.kind,
              'kind',
              GradeFailureKind.networkUnavailable,
            ),
          ),
        );
        expect(hisInOne.fetchCalls, 1);
        expect(legacy.fetchCalls, 0);
      },
    );
  });

  // Regression group for LEVIORA-154, reproduced against the live portal on
  // 2026-08-24: HISinOne accepts the credentials of an account whose results
  // still live in HIS-QIS. If that portal fails in a way that is specific to
  // IT (an unrecognised page, a portal error), setup must move on to the
  // legacy portal instead of aborting with no grades at all.
  group('a portal-specific failure falls through to the other portal', () {
    test(
      'portalStructureChanged on hisInOne → legacy is tried and wins',
      () async {
        final hisInOne = FakeGradesGateway(
          error: const GradeFailure(GradeFailureKind.portalStructureChanged),
        );
        final legacy = FakeGradesGateway(report: sampleReport('Legacy-Kurs'));
        final c = _container(hisInOne: hisInOne, legacy: legacy);
        await c.read(gradeAccountControllerProvider.future);

        final GradeReport report = await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'u', password: 'p');

        expect(report.entries.single.title, 'Legacy-Kurs');
        expect(hisInOne.fetchCalls, 1);
        expect(legacy.fetchCalls, 1);
        expect(
          c.read(gradeAccountControllerProvider).requireValue.activePortal,
          GradePortal.hisQisLegacy,
        );
      },
    );

    test('portalUnavailable on hisInOne → legacy is tried and wins', () async {
      final hisInOne = FakeGradesGateway(
        error: const GradeFailure(GradeFailureKind.portalUnavailable),
      );
      final legacy = FakeGradesGateway(report: sampleReport('Legacy-Kurs'));
      final c = _container(hisInOne: hisInOne, legacy: legacy);
      await c.read(gradeAccountControllerProvider.future);

      final GradeReport report = await c
          .read(gradeAccountControllerProvider.notifier)
          .signIn(username: 'u', password: 'p');

      expect(report.entries.single.title, 'Legacy-Kurs');
      expect(legacy.fetchCalls, 1);
    });

    test('both portals fail structurally → the failure is surfaced, nothing is '
        'persisted', () async {
      final hisInOne = FakeGradesGateway(
        error: const GradeFailure(GradeFailureKind.portalStructureChanged),
      );
      final legacy = FakeGradesGateway(
        error: const GradeFailure(GradeFailureKind.portalStructureChanged),
      );
      final store = InMemoryGradeCredentialStore();
      final c = _container(hisInOne: hisInOne, legacy: legacy, store: store);
      await c.read(gradeAccountControllerProvider.future);

      await expectLater(
        c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'u', password: 'p'),
        throwsA(
          isA<GradeFailure>().having(
            (GradeFailure e) => e.kind,
            'kind',
            GradeFailureKind.portalStructureChanged,
          ),
        ),
      );
      expect(store.writes, 0);
      expect(
        c.read(gradeAccountControllerProvider).requireValue.isSignedIn,
        isFalse,
      );
    });

    test(
      'a TLS rejection still aborts immediately — the second portal cannot fix '
      'a broken connection',
      () async {
        final hisInOne = FakeGradesGateway(
          error: const GradeFailure(GradeFailureKind.tlsOrHostRejected),
        );
        final legacy = FakeGradesGateway(report: sampleReport());
        final c = _container(hisInOne: hisInOne, legacy: legacy);
        await c.read(gradeAccountControllerProvider.future);

        await expectLater(
          c
              .read(gradeAccountControllerProvider.notifier)
              .signIn(username: 'u', password: 'p'),
          throwsA(
            isA<GradeFailure>().having(
              (GradeFailure e) => e.kind,
              'kind',
              GradeFailureKind.tlsOrHostRejected,
            ),
          ),
        );
        expect(legacy.fetchCalls, 0);
      },
    );
  });

  group('portal persistence and switching', () {
    test('the chosen portal is persisted', () async {
      final hisInOne = FakeGradesGateway(report: sampleReport());
      final legacy = FakeGradesGateway(report: sampleReport());
      final portalStore = InMemoryGradePortalStore();
      final c = _container(
        hisInOne: hisInOne,
        legacy: legacy,
        portalStore: portalStore,
      );
      await c.read(gradeAccountControllerProvider.future);

      await c
          .read(gradeAccountControllerProvider.notifier)
          .signIn(username: 'u', password: 'p');

      expect(portalStore.lastWritten, GradePortal.hisInOne);
    });

    test('switching portals discards the local cache', () async {
      final hisInOne = FakeGradesGateway(report: sampleReport());
      final legacy = FakeGradesGateway(report: sampleReport());
      final cache = InMemoryGradeCacheStore();
      final portalStore = InMemoryGradePortalStore();
      final c = _container(
        hisInOne: hisInOne,
        legacy: legacy,
        cache: cache,
        portalStore: portalStore,
      );
      await c.read(gradeAccountControllerProvider.future);
      await c
          .read(gradeAccountControllerProvider.notifier)
          .signIn(username: 'u', password: 'p');
      expect(await cache.readReport(), isNotNull);

      await c
          .read(gradeAccountControllerProvider.notifier)
          .switchPortal(GradePortal.hisQisLegacy);

      expect(cache.clears, greaterThanOrEqualTo(1));
      expect(await cache.readReport(), isNull);
      expect(portalStore.lastWritten, GradePortal.hisQisLegacy);
      expect(
        c.read(gradeAccountControllerProvider).requireValue.activePortal,
        GradePortal.hisQisLegacy,
      );
    });

    test('deleting the account also removes the portal choice', () async {
      final hisInOne = FakeGradesGateway(report: sampleReport());
      final legacy = FakeGradesGateway(report: sampleReport());
      final portalStore = InMemoryGradePortalStore();
      final c = _container(
        hisInOne: hisInOne,
        legacy: legacy,
        portalStore: portalStore,
      );
      await c.read(gradeAccountControllerProvider.future);
      await c
          .read(gradeAccountControllerProvider.notifier)
          .signIn(username: 'u', password: 'p');

      await c.read(gradeAccountControllerProvider.notifier).deleteEverything();

      expect(portalStore.clears, greaterThanOrEqualTo(1));
      expect(await portalStore.read(), isNull);
    });

    test('an account without a stored portal choice moves to HISinOne, the '
        'standard portal, and keeps that choice', () async {
      final store = InMemoryGradeCredentialStore()
        ..write(const GradeCredentials(username: 'legacyUser', password: 'pw'));
      final InMemoryGradePortalStore portalStore =
          InMemoryGradePortalStore(); // no portal written (1.x account)
      final c = _container(
        hisInOne: FakeGradesGateway(),
        legacy: FakeGradesGateway(),
        store: store,
        portalStore: portalStore,
      );

      final GradeAccountState s = await c.read(
        gradeAccountControllerProvider.future,
      );

      expect(s.activePortal, GradePortal.hisInOne);
      expect(portalStore.lastWritten, GradePortal.hisInOne);
    });

    test('moving an account without a portal choice drops the cached report '
        'of the old portal, like any portal switch', () async {
      final store = InMemoryGradeCredentialStore()
        ..write(const GradeCredentials(username: 'legacyUser', password: 'pw'));
      final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
      await cache.writeReport(sampleReport('Aus HIS-QIS'));
      final c = _container(
        hisInOne: FakeGradesGateway(),
        legacy: FakeGradesGateway(),
        store: store,
        portalStore: InMemoryGradePortalStore(),
        cache: cache,
      );

      await c.read(gradeAccountControllerProvider.future);

      // HIS-QIS grades never appear under HISinOne's name, and the first
      // HISinOne sync has no foreign baseline to report as "new grades".
      expect(await cache.readReport(), isNull);
    });

    test('an account that already chose a portal is never moved', () async {
      final store = InMemoryGradeCredentialStore()
        ..write(const GradeCredentials(username: 'qisUser', password: 'pw'));
      final InMemoryGradePortalStore portalStore = InMemoryGradePortalStore();
      await portalStore.write(GradePortal.hisQisLegacy);
      final InMemoryGradeCacheStore cache = InMemoryGradeCacheStore();
      await cache.writeReport(sampleReport('Aus HIS-QIS'));
      final c = _container(
        hisInOne: FakeGradesGateway(),
        legacy: FakeGradesGateway(),
        store: store,
        portalStore: portalStore,
        cache: cache,
      );

      final GradeAccountState s = await c.read(
        gradeAccountControllerProvider.future,
      );

      expect(s.activePortal, GradePortal.hisQisLegacy);
      expect(await cache.readReport(), isNotNull);
    });
  });
}
