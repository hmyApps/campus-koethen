// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/features/document_wallet/application/document_wallet_controller.dart';
import 'package:campus_koethen/features/document_wallet/domain/wallet_document.dart';
import 'package:campus_koethen/features/document_wallet/presentation/wallet_save_action.dart';
import 'package:campus_koethen/features/grades/application/grade_account_controller.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grades.dart';
import '../../support/pump_app.dart';

// D-04: the first "save to wallet" of a session — and the first after a
// portal or account switch — must work without the wallet screen ever having
// been opened. These tests use the REAL controller; the screen test fakes it.

const GradeCredentials _creds = GradeCredentials(
  username: 'testuser',
  password: 'test-pw',
);

class _InMemoryWalletStore implements DocumentWalletStore {
  final Map<WalletDocumentKind, WalletDocument> documents =
      <WalletDocumentKind, WalletDocument>{};
  int clears = 0;

  @override
  Future<List<WalletDocument>> readAll() async =>
      List<WalletDocument>.unmodifiable(documents.values);

  @override
  Future<void> save(WalletDocument document) async =>
      documents[document.kind] = document;

  @override
  Future<void> delete(WalletDocumentKind kind) async => documents.remove(kind);

  @override
  Future<void> clear() async {
    clears++;
    documents.clear();
  }
}

AppDocument _pdf() {
  final Uint8List bytes = Uint8List.fromList('%PDF-1.7 test'.codeUnits);
  return AppDocument(
    filename: 'Immatrikulation.pdf',
    mediaType: 'application/pdf',
    bytes: bytes,
    sizeBytes: bytes.length,
  );
}

/// The same grades-linked wallet wipe `main.dart` registers.
List<Override> _overrides({
  required _InMemoryWalletStore wallet,
  required InMemoryGradePortalStore portalStore,
}) {
  final FakeGradesGateway gateway = FakeGradesGateway(report: sampleReport());
  return <Override>[
    legacyQisGatewayProvider.overrideWithValue(gateway),
    hisInOneGatewayProvider.overrideWithValue(gateway),
    gradesGatewayProvider.overrideWithValue(gateway),
    gradeCredentialStoreProvider.overrideWithValue(
      InMemoryGradeCredentialStore()..write(_creds),
    ),
    gradePortalStoreProvider.overrideWithValue(portalStore),
    gradeCacheStoreProvider.overrideWithValue(InMemoryGradeCacheStore()),
    gradeClockProvider.overrideWithValue(
      MutableClock(DateTime.utc(2026, 10, 6, 12)),
    ),
    documentWalletStoreProvider.overrideWithValue(wallet),
    gradeLinkedPersonalDataWipersProvider.overrideWith((Ref ref) {
      return <GradeLinkedPersonalDataWiper>[
        () async {
          await ref
              .read(documentWalletSessionGuardProvider)
              .invalidateAndWait();
          await ref.read(documentWalletStoreProvider).clear();
        },
      ];
    }),
  ];
}

void main() {
  test(
    'the first save of a session works before the wallet was opened',
    () async {
      final _InMemoryWalletStore wallet = _InMemoryWalletStore();
      final ProviderContainer c = ProviderContainer(
        overrides: _overrides(
          wallet: wallet,
          portalStore: InMemoryGradePortalStore()..write(GradePortal.hisInOne),
        ),
      );
      addTearDown(c.dispose);
      await c.read(gradeAccountControllerProvider.future);

      await c
          .read(documentWalletControllerProvider.notifier)
          .save(
            kind: WalletDocumentKind.enrollmentCertificate,
            document: _pdf(),
          );

      expect(wallet.documents.keys, <WalletDocumentKind>[
        WalletDocumentKind.enrollmentCertificate,
      ]);
      expect(c.read(documentWalletControllerProvider).value, hasLength(1));
    },
  );

  test('a save right after a portal switch works', () async {
    final _InMemoryWalletStore wallet = _InMemoryWalletStore();
    final ProviderContainer c = ProviderContainer(
      overrides: _overrides(
        wallet: wallet,
        portalStore: InMemoryGradePortalStore()..write(GradePortal.hisInOne),
      ),
    );
    addTearDown(c.dispose);
    await c.read(gradeAccountControllerProvider.future);
    // The wallet screen was opened earlier in this session.
    c.listen(documentWalletControllerProvider, (_, _) {});
    await c.read(documentWalletControllerProvider.future);

    await c
        .read(gradeAccountControllerProvider.notifier)
        .switchPortal(GradePortal.hisQisLegacy);
    expect(wallet.clears, 1, reason: 'the switch wipes the wallet');

    await c
        .read(documentWalletControllerProvider.notifier)
        .save(kind: WalletDocumentKind.transcript, document: _pdf());

    expect(wallet.documents.keys, <WalletDocumentKind>[
      WalletDocumentKind.transcript,
    ]);
  });

  testWidgets(
    'the save action reports success with the real controller on first use',
    (WidgetTester tester) async {
      final _InMemoryWalletStore wallet = _InMemoryWalletStore();
      await pumpScreen(
        tester,
        Scaffold(
          body: WalletSaveAction(
            kind: WalletDocumentKind.enrollmentCertificate,
            document: _pdf(),
          ),
        ),
        overrides: _overrides(
          wallet: wallet,
          portalStore: InMemoryGradePortalStore()..write(GradePortal.hisInOne),
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        AppLocales.german,
      );

      await tester.tap(find.byTooltip(l10n.documentWalletSaveAction));
      await tester.pumpAndSettle();

      expect(find.text(l10n.documentWalletSaveFailed), findsNothing);
      expect(find.text(l10n.documentWalletSaved), findsOneWidget);
      expect(wallet.documents, hasLength(1));
    },
  );
}
