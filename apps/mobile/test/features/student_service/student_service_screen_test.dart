// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/app_routes.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/theme/app_theme.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
import 'package:campus_koethen/features/student_service/application/student_service_providers.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_cache_store.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_failure.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_gateway.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_overview.dart';
import 'package:campus_koethen/features/student_service/presentation/student_service_screen.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_grades.dart';
import '../../support/pump_app.dart';

const GradeCredentials _credentials = GradeCredentials(
  username: 'student42',
  password: 'test-password',
);
final DateTime _now = DateTime.utc(2026, 10, 2, 12);

class _StudentServiceCache implements StudentServiceCacheStore {
  _StudentServiceCache(this.overview)
    : lastSuccessfulSync = _now,
      lastAttemptedSync = _now;

  StudentServiceOverview? overview;
  DateTime? lastSuccessfulSync;
  DateTime? lastAttemptedSync;

  @override
  Future<void> clear() async {
    overview = null;
    lastSuccessfulSync = null;
    lastAttemptedSync = null;
  }

  @override
  Future<DateTime?> readLastAttemptedSync() async => lastAttemptedSync;

  @override
  Future<DateTime?> readLastSuccessfulSync() async => lastSuccessfulSync;

  @override
  Future<StudentServiceOverview?> readOverview() async => overview;

  @override
  Future<void> writeLastAttemptedSync(DateTime at) async {
    lastAttemptedSync = at;
  }

  @override
  Future<void> writeLastSuccessfulSync(DateTime at) async {
    lastSuccessfulSync = at;
  }

  @override
  Future<void> writeOverview(StudentServiceOverview value) async {
    overview = value;
  }
}

class _StudentServiceGateway implements StudentServiceGateway {
  _StudentServiceGateway(this.overview);

  final StudentServiceOverview overview;

  @override
  Future<CertificateDownloadResult> downloadCertificate(
    GradeCredentials credentials,
    CertificateOffer offer, {
    bool Function()? isCancelled,
  }) async => const CertificateUnavailable('fixture');

  @override
  Future<StudentServiceOverview> fetchOverview(
    GradeCredentials credentials,
  ) async => overview;
}

class _FailingStudentServiceGateway implements StudentServiceGateway {
  _FailingStudentServiceGateway([
    this.failure = const StudentServiceFailure(
      StudentServiceFailureKind.networkUnavailable,
    ),
  ]);

  final StudentServiceFailure failure;
  int fetchCount = 0;

  @override
  Future<CertificateDownloadResult> downloadCertificate(
    GradeCredentials credentials,
    CertificateOffer offer, {
    bool Function()? isCancelled,
  }) async => const CertificateUnavailable('fixture');

  @override
  Future<StudentServiceOverview> fetchOverview(
    GradeCredentials credentials,
  ) async {
    fetchCount++;
    throw failure;
  }
}

StudentServiceOverview _overview() => StudentServiceOverview(
  personalData: const <PersonalDataField>[
    PersonalDataField(
      label: 'Sehr lange Bezeichnung der Matrikelnummer',
      value: '000000000000000000000',
    ),
    PersonalDataField(label: 'Hörerstatus', value: 'Student'),
  ],
  hoererstatus: 'Student',
  contactTiles: const <ContactTile>[
    ContactTile(
      heading: 'Semesteranschrift mit langem Namen',
      lines: <String>[
        'Eine außergewöhnlich lange Beispielstraße 123, 06366 Köthen',
      ],
    ),
  ],
  programmes: const <ProgrammeEntry>[
    ProgrammeEntry(
      subject: 'Angewandte Informatik mit sehr langer Vertiefungsbezeichnung',
      subjectSemester: '3. Fachsemester',
      subjectIndicator: 'H',
      examinationVersion: '2023',
    ),
  ],
  certificates: const <CertificateOffer>[
    CertificateOffer(
      name: 'Studienverlaufsbescheinigung mit sehr langer Bezeichnung',
      jobButtonId: 'fixture-job',
    ),
  ],
  paymentHint: const PaymentHint(kind: PaymentHintKind.noneOpen),
  fetchedAt: _now,
);

List<Override> _connectedOverrides(
  StudentServiceOverview overview, {
  StudentServiceCacheStore? cache,
  StudentServiceGateway? gateway,
}) {
  final InMemoryGradeCredentialStore credentials =
      InMemoryGradeCredentialStore()..write(_credentials);
  final InMemoryGradePortalStore portal = InMemoryGradePortalStore()
    ..write(GradePortal.hisInOne);
  return <Override>[
    gradeCredentialStoreProvider.overrideWithValue(credentials),
    gradePortalStoreProvider.overrideWithValue(portal),
    gradeCacheStoreProvider.overrideWithValue(InMemoryGradeCacheStore()),
    gradeClockProvider.overrideWithValue(MutableClock(_now)),
    studentServiceCacheStoreProvider.overrideWithValue(
      cache ?? _StudentServiceCache(overview),
    ),
    studentServiceGatewayProvider.overrideWithValue(
      gateway ?? _StudentServiceGateway(overview),
    ),
    studentServiceClockProvider.overrideWithValue(MutableClock(_now)),
  ];
}

void main() {
  testWidgets('signed-out action navigates to the grades route', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.studentService,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.studentService,
          builder: (_, _) => const StudentServiceScreen(),
        ),
        GoRoute(
          path: AppRoutes.grades,
          builder: (_, _) => const Scaffold(body: Text('grades-target')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        gradeCredentialStoreProvider.overrideWithValue(
          InMemoryGradeCredentialStore(),
        ),
        gradePortalStoreProvider.overrideWithValue(InMemoryGradePortalStore()),
        gradeCacheStoreProvider.overrideWithValue(InMemoryGradeCacheStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: AppLocales.german,
          supportedLocales: AppLocales.supported,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zu Noten'));
    await tester.pumpAndSettle();

    expect(find.text('grades-target'), findsOneWidget);
  });

  testWidgets('certificates render above the personal-data sections', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const StudentServiceScreen(),
      overrides: _connectedOverrides(_overview()),
    );
    await tester.pumpAndSettle();

    final double certificatesTop = tester
        .getTopLeft(find.text('Bescheinigungen'))
        .dy;
    final double personalDataTop = tester
        .getTopLeft(find.text('Personendaten'))
        .dy;

    expect(certificatesTop, lessThan(personalDataTop));
  });

  testWidgets('overview and certificate error fit at 320dp and 200% text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final StudentServiceOverview overview = _overview();

    await pumpScreen(
      tester,
      const StudentServiceScreen(),
      overrides: _connectedOverrides(overview),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Personendaten'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('PDF erstellen'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('PDF erstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Bescheinigungen'), findsOneWidget);
    await tester.tap(find.text('PDF erstellen'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Das Dokument konnte nicht abgerufen werden. '
        '(Diagnosecode: fixture)',
      ),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed HISinOne load explains the cause and can be retried', (
    WidgetTester tester,
  ) async {
    final _StudentServiceCache cache = _StudentServiceCache(null)
      ..lastAttemptedSync = null
      ..lastSuccessfulSync = null;
    final _FailingStudentServiceGateway gateway =
        _FailingStudentServiceGateway();

    await pumpScreen(
      tester,
      const StudentServiceScreen(),
      overrides: _connectedOverrides(
        _overview(),
        cache: cache,
        gateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.text('Keine Netzwerkverbindung.'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(gateway.fetchCount, 1);

    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();

    expect(gateway.fetchCount, 2);
  });

  testWidgets(
    'a recent failed attempt with nothing cached offers a manual load '
    'instead of spinning forever',
    (WidgetTester tester) async {
      // The cache's default lastAttemptedSync is "just now" — exactly what
      // it would be after an earlier attempt failed this session (or in a
      // previous app run) and the 24h auto-sync throttle is still in
      // effect. No overview was ever cached, and the in-memory error from
      // that earlier attempt is gone (e.g. the app was restarted). This is
      // the state a classified failure such as the real
      // "tabSwitchRequest:studyserviceForm:newContactData_TabBtn" portal
      // change leaves behind once the throttle kicks in.
      final _StudentServiceCache cache = _StudentServiceCache(null);
      final _FailingStudentServiceGateway gateway =
          _FailingStudentServiceGateway();

      await pumpScreen(
        tester,
        const StudentServiceScreen(),
        overrides: _connectedOverrides(
          _overview(),
          cache: cache,
          gateway: gateway,
        ),
      );
      await tester.pumpAndSettle();

      // Auto-sync must honour the throttle and not call the gateway.
      expect(gateway.fetchCount, 0);
      // The screen must not be an un-escapable spinner: a manual load
      // action has to be visible and tappable.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Aktualisieren'), findsOneWidget);

      await tester.tap(find.text('Aktualisieren'));
      await tester.pumpAndSettle();

      expect(gateway.fetchCount, 1);
      expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    },
  );

  testWidgets(
    'a real portal mismatch names the exact failing check, not just "changed"',
    (WidgetTester tester) async {
      final _StudentServiceCache cache = _StudentServiceCache(null)
        ..lastAttemptedSync = null
        ..lastSuccessfulSync = null;
      final _FailingStudentServiceGateway gateway =
          _FailingStudentServiceGateway(
            const StudentServiceFailure(
              StudentServiceFailureKind.portalStructureChanged,
              stage: 'contactTiles',
            ),
          );

      await pumpScreen(
        tester,
        const StudentServiceScreen(),
        overrides: _connectedOverrides(
          _overview(),
          cache: cache,
          gateway: gateway,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
      expect(find.textContaining('Diagnosecode: contactTiles'), findsOneWidget);
    },
  );
}
