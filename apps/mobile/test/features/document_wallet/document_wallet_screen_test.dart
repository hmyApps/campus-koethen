// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/features/document_wallet/application/document_wallet_controller.dart';
import 'package:campus_koethen/features/document_wallet/domain/wallet_document.dart';
import 'package:campus_koethen/features/document_wallet/presentation/document_wallet_screen.dart';
import 'package:campus_koethen/features/document_wallet/presentation/wallet_save_action.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

Uint8List _pdf() => Uint8List.fromList('%PDF-1.7 test'.codeUnits);

class _WalletController extends DocumentWalletController {
  _WalletController(this.documents);

  final List<WalletDocument> documents;
  WalletDocumentKind? deleted;
  WalletDocumentKind? saved;

  @override
  Future<List<WalletDocument>> build() async => documents;

  @override
  Future<void> delete(WalletDocumentKind kind) async {
    deleted = kind;
    state = AsyncData<List<WalletDocument>>(
      documents.where((WalletDocument value) => value.kind != kind).toList(),
    );
  }

  @override
  Future<void> save({
    required WalletDocumentKind kind,
    required AppDocument document,
  }) async {
    saved = kind;
  }
}

void main() {
  testWidgets('shows both offline document kinds and confirms deletion', (
    WidgetTester tester,
  ) async {
    final _WalletController controller = _WalletController(<WalletDocument>[
      WalletDocument(
        kind: WalletDocumentKind.enrollmentCertificate,
        filename: 'Immatrikulation.pdf',
        mediaType: 'application/pdf',
        bytes: _pdf(),
        savedAt: DateTime(2026, 10, 6, 10),
      ),
      WalletDocument(
        kind: WalletDocumentKind.transcript,
        filename: 'Leistungsuebersicht.pdf',
        mediaType: 'application/pdf',
        bytes: _pdf(),
        savedAt: DateTime(2026, 10, 6, 11),
      ),
    ]);
    final ProviderContainer container = await pumpScreen(
      tester,
      const DocumentWalletScreen(),
      textScaler: const TextScaler.linear(2),
      overrides: [
        documentWalletControllerProvider.overrideWith(() => controller),
      ],
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      AppLocales.german,
    );

    expect(find.text(l10n.documentWalletEnrollmentCertificate), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(l10n.documentWalletTranscript),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.documentWalletTranscript), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip(l10n.documentWalletDelete).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.documentWalletDeleteTitle), findsOneWidget);
    await tester.tap(find.text(l10n.documentWalletDelete));
    await tester.pumpAndSettle();

    expect(controller.deleted, isNotNull);
    expect(
      container.read(documentWalletControllerProvider).value,
      hasLength(1),
    );
  });

  testWidgets('explicit save action delegates once and reports success', (
    WidgetTester tester,
  ) async {
    final _WalletController controller = _WalletController(
      const <WalletDocument>[],
    );
    final AppDocument document = AppDocument(
      filename: 'Immatrikulation.pdf',
      mediaType: 'application/pdf',
      bytes: _pdf(),
      sizeBytes: _pdf().length,
    );
    await pumpScreen(
      tester,
      Scaffold(
        body: WalletSaveAction(
          kind: WalletDocumentKind.enrollmentCertificate,
          document: document,
        ),
      ),
      overrides: [
        documentWalletControllerProvider.overrideWith(() => controller),
      ],
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      AppLocales.german,
    );

    await tester.tap(find.byTooltip(l10n.documentWalletSaveAction));
    await tester.pumpAndSettle();

    expect(controller.saved, WalletDocumentKind.enrollmentCertificate);
    expect(find.text(l10n.documentWalletSaved), findsOneWidget);
    expect(find.byTooltip(l10n.documentWalletSaved), findsOneWidget);
  });
}
