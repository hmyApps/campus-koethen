// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/grades/application/grade_account_controller.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
import 'package:campus_koethen/features/student_service/application/student_service_controller.dart';
import 'package:campus_koethen/features/student_service/application/student_service_providers.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_cache_store.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_failure.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_gateway.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_overview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grades.dart';

const GradeCredentials _creds = GradeCredentials(
  username: 'testuser',
  password: 'test-pw',
);

StudentServiceOverview _overview({DateTime? fetchedAt}) =>
    StudentServiceOverview(
      personalData: const <PersonalDataField>[],
      hoererstatus: 'Student',
      contactTiles: const <ContactTile>[],
      programmes: const <ProgrammeEntry>[],
      certificates: const <CertificateOffer>[],
      paymentHint: const PaymentHint(kind: PaymentHintKind.noneOpen),
      fetchedAt: fetchedAt ?? DateTime.utc(2026, 10, 1),
    );

/// Scriptable fake, same shape as `FakeGradesGateway`.
class FakeStudentServiceGateway implements StudentServiceGateway {
  FakeStudentServiceGateway({this.overview, this.error});

  StudentServiceOverview? overview;
  StudentServiceFailure? error;

  /// Deterministic gate for the logout-race test.
  Completer<StudentServiceOverview>? pendingOverview;

  int fetchCalls = 0;

  @override
  Future<StudentServiceOverview> fetchOverview(
    GradeCredentials credentials,
  ) async {
    fetchCalls++;
    if (pendingOverview != null) return pendingOverview!.future;
    if (error != null) throw error!;
    return overview ?? _overview();
  }

  @override
  Future<CertificateDownloadResult> downloadCertificate(
    GradeCredentials credentials,
    CertificateOffer offer,
  ) async => const CertificateUnavailable('not-scripted');
}

/// In-memory cache. Records writes so the race test can assert a late
/// overview is never persisted after the account was deleted.
class InMemoryStudentServiceCacheStore implements StudentServiceCacheStore {
  StudentServiceOverview? _overview;
  DateTime? _lastSuccess;
  DateTime? _lastAttempt;
  int overviewWrites = 0;
  int clears = 0;

  @override
  Future<StudentServiceOverview?> readOverview() async => _overview;

  @override
  Future<void> writeOverview(StudentServiceOverview overview) async {
    _overview = overview;
    overviewWrites++;
  }

  @override
  Future<DateTime?> readLastSuccessfulSync() async => _lastSuccess;

  @override
  Future<void> writeLastSuccessfulSync(DateTime at) async => _lastSuccess = at;

  @override
  Future<DateTime?> readLastAttemptedSync() async => _lastAttempt;

  @override
  Future<void> writeLastAttemptedSync(DateTime at) async => _lastAttempt = at;

  @override
  Future<void> clear() async {
    clears++;
    _overview = null;
    _lastSuccess = null;
    _lastAttempt = null;
  }

  bool get isEmpty => _overview == null && _lastSuccess == null;
}

void main() {
  final DateTime t0 = DateTime.utc(2026, 10, 1, 12);

  ProviderContainer container({
    required InMemoryGradeCredentialStore gradeStore,
    required InMemoryGradePortalStore portalStore,
    required InMemoryGradeCacheStore gradeCache,
    required FakeStudentServiceGateway gateway,
    required InMemoryStudentServiceCacheStore cache,
    MutableClock? clock,
  }) {
    final List<Override> overrides = <Override>[
      gradeCredentialStoreProvider.overrideWithValue(gradeStore),
      gradePortalStoreProvider.overrideWithValue(portalStore),
      gradeCacheStoreProvider.overrideWithValue(gradeCache),
      gradeClockProvider.overrideWithValue(clock ?? MutableClock(t0)),
      studentServiceGatewayProvider.overrideWithValue(gateway),
      studentServiceCacheStoreProvider.overrideWithValue(cache),
      studentServiceClockProvider.overrideWithValue(clock ?? MutableClock(t0)),
      gradeLinkedPersonalDataWipersProvider.overrideWith(
        (Ref ref) => <GradeLinkedPersonalDataWiper>[
          () async {
            await ref
                .read(studentServiceSessionGuardProvider)
                .invalidateAndWait();
            await cache.clear();
          },
        ],
      ),
    ];
    final ProviderContainer c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    return c;
  }

  Future<ProviderContainer> connectedOnHisInOne({
    required FakeStudentServiceGateway gateway,
    required InMemoryStudentServiceCacheStore cache,
    MutableClock? clock,
  }) async {
    final gradeStore = InMemoryGradeCredentialStore()..write(_creds);
    final portalStore = InMemoryGradePortalStore()..write(GradePortal.hisInOne);
    final c = container(
      gradeStore: gradeStore,
      portalStore: portalStore,
      gradeCache: InMemoryGradeCacheStore(),
      gateway: gateway,
      cache: cache,
      clock: clock,
    );
    await c.read(gradeAccountControllerProvider.future);
    c.listen(studentServiceControllerProvider, (_, _) {});
    await c.read(studentServiceControllerProvider.future);
    return c;
  }

  group('availability', () {
    test('not connected to grades: nothing is fetched', () async {
      final gateway = FakeStudentServiceGateway();
      final c = container(
        gradeStore: InMemoryGradeCredentialStore(),
        portalStore: InMemoryGradePortalStore(),
        gradeCache: InMemoryGradeCacheStore(),
        gateway: gateway,
        cache: InMemoryStudentServiceCacheStore(),
      );
      await c.read(gradeAccountControllerProvider.future);

      final state = await c.read(studentServiceControllerProvider.future);

      expect(state.overview, isNull);
      await c.read(studentServiceControllerProvider.notifier).maybeAutoSync();
      expect(gateway.fetchCalls, 0);
    });

    test(
      'connected on the legacy HIS-QIS portal: nothing is fetched',
      () async {
        final gateway = FakeStudentServiceGateway();
        final gradeStore = InMemoryGradeCredentialStore()..write(_creds);
        final portalStore = InMemoryGradePortalStore()
          ..write(GradePortal.hisQisLegacy);
        final c = container(
          gradeStore: gradeStore,
          portalStore: portalStore,
          gradeCache: InMemoryGradeCacheStore(),
          gateway: gateway,
          cache: InMemoryStudentServiceCacheStore(),
        );
        await c.read(gradeAccountControllerProvider.future);

        await c.read(studentServiceControllerProvider.future);
        await c.read(studentServiceControllerProvider.notifier).maybeAutoSync();

        expect(gateway.fetchCalls, 0);
      },
    );
  });

  group('sync', () {
    test('connected on HISinOne: first open syncs and caches', () async {
      final gateway = FakeStudentServiceGateway(overview: _overview());
      final cache = InMemoryStudentServiceCacheStore();
      final c = await connectedOnHisInOne(gateway: gateway, cache: cache);

      await c.read(studentServiceControllerProvider.notifier).refresh();

      expect(gateway.fetchCalls, 1);
      expect(cache.overviewWrites, 1);
      expect(
        c.read(studentServiceControllerProvider).requireValue.overview,
        isNotNull,
      );
    });

    test('a failed sync keeps the old cache and surfaces the error', () async {
      final gateway = FakeStudentServiceGateway(
        error: const StudentServiceFailure(
          StudentServiceFailureKind.portalUnavailable,
        ),
      );
      final cache = InMemoryStudentServiceCacheStore()
        ..writeOverview(_overview());
      final c = await connectedOnHisInOne(gateway: gateway, cache: cache);

      await c.read(studentServiceControllerProvider.notifier).refresh();

      final state = c.read(studentServiceControllerProvider).requireValue;
      expect(state.error?.kind, StudentServiceFailureKind.portalUnavailable);
      expect(state.overview, isNotNull, reason: 'old cache stays visible');
    });

    test(
      'disconnecting grades waits for and discards a delayed sync response',
      () async {
        final Completer<StudentServiceOverview> response =
            Completer<StudentServiceOverview>();
        final gateway = FakeStudentServiceGateway()..pendingOverview = response;
        final cache = InMemoryStudentServiceCacheStore();
        final gradeStore = InMemoryGradeCredentialStore()..write(_creds);
        final portalStore = InMemoryGradePortalStore()
          ..write(GradePortal.hisInOne);
        final gradeCache = InMemoryGradeCacheStore();
        final c = container(
          gradeStore: gradeStore,
          portalStore: portalStore,
          gradeCache: gradeCache,
          gateway: gateway,
          cache: cache,
        );
        await c.read(gradeAccountControllerProvider.future);
        c.listen(studentServiceControllerProvider, (_, _) {});
        await c.read(studentServiceControllerProvider.future);

        final Future<void> refresh = c
            .read(studentServiceControllerProvider.notifier)
            .refresh();
        await Future<void>.delayed(Duration.zero);
        expect(gateway.fetchCalls, 1);

        // Start the real production sequence: invalidate, drain the in-flight
        // writer, and only then wipe. It deliberately remains pending until
        // the response below has been discarded by the session guard.
        final Future<void> deletion = c
            .read(gradeAccountControllerProvider.notifier)
            .deleteEverything();
        await Future<void>.delayed(Duration.zero);
        expect(cache.clears, 0, reason: 'wipe waits for the in-flight writer');

        response.complete(_overview());
        await Future.wait(<Future<void>>[refresh, deletion]);

        expect(
          cache.overviewWrites,
          0,
          reason: 'the late overview must never be written once grades is gone',
        );
        expect(
          c.read(gradeAccountControllerProvider).requireValue.isSignedIn,
          isFalse,
        );
        expect(
          cache.clears,
          1,
          reason: 'logout must wipe personal HISinOne data',
        );
      },
    );

    test(
      'a fresh HISinOne login reactivates sync after a completed logout',
      () async {
        final gateway = FakeStudentServiceGateway(overview: _overview());
        final cache = InMemoryStudentServiceCacheStore();
        final gradeGateway = FakeGradesGateway(report: sampleReport());
        final gradeStore = InMemoryGradeCredentialStore()..write(_creds);
        final portalStore = InMemoryGradePortalStore()
          ..write(GradePortal.hisInOne);
        final c = ProviderContainer(
          overrides: <Override>[
            gradeCredentialStoreProvider.overrideWithValue(gradeStore),
            gradePortalStoreProvider.overrideWithValue(portalStore),
            gradeCacheStoreProvider.overrideWithValue(
              InMemoryGradeCacheStore(),
            ),
            gradeClockProvider.overrideWithValue(MutableClock(t0)),
            hisInOneGatewayProvider.overrideWithValue(gradeGateway),
            legacyQisGatewayProvider.overrideWithValue(gradeGateway),
            studentServiceGatewayProvider.overrideWithValue(gateway),
            studentServiceCacheStoreProvider.overrideWithValue(cache),
            gradeLinkedPersonalDataWipersProvider.overrideWith(
              (Ref ref) => <GradeLinkedPersonalDataWiper>[
                () async {
                  await ref
                      .read(studentServiceSessionGuardProvider)
                      .invalidateAndWait();
                  await cache.clear();
                },
              ],
            ),
          ],
        );
        addTearDown(c.dispose);
        await c.read(gradeAccountControllerProvider.future);
        c.listen(studentServiceControllerProvider, (_, _) {});
        await c.read(studentServiceControllerProvider.future);
        await c.read(studentServiceControllerProvider.notifier).refresh();
        expect(gateway.fetchCalls, 1);

        await c
            .read(gradeAccountControllerProvider.notifier)
            .deleteEverything();
        await c.read(studentServiceControllerProvider.future);
        await c
            .read(gradeAccountControllerProvider.notifier)
            .signIn(username: 'second-user', password: 'new-secret');
        await c.read(studentServiceControllerProvider.future);
        await c.read(studentServiceControllerProvider.notifier).refresh();

        expect(gateway.fetchCalls, 2);
        expect(cache.clears, greaterThanOrEqualTo(1));
      },
    );
  });
}
