// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/features/document_wallet/application/document_wallet_controller.dart';
import 'package:campus_koethen/features/document_wallet/domain/wallet_document.dart';
import 'package:campus_koethen/features/document_wallet/presentation/document_wallet_screen.dart';
import 'package:campus_koethen/features/nextcloud/application/nextcloud_providers.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_account.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_entry.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_nextcloud.dart';
import '../../support/pump_app.dart';

const NextcloudCredential _credential = NextcloudCredential(
  server: 'https://cloud.hs-anhalt.de',
  loginName: 'student-login',
  userId: 'student-id',
  appPassword: 'secret',
);

class _Wallet extends DocumentWalletController {
  @override
  Future<List<WalletDocument>> build() async => <WalletDocument>[
    WalletDocument.custom(
      document: AppDocument(
        filename: 'Skript.pdf',
        mediaType: 'application/pdf',
        bytes: Uint8List.fromList('%PDF-1.7 x'.codeUnits),
      ),
      savedAt: DateTime(2026, 10, 16),
      id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
  ];
}

void main() {
  testWidgets('exports to the chosen folder after the unencrypted warning', (
    WidgetTester tester,
  ) async {
    final FakeNextcloudGateway gateway = FakeNextcloudGateway()
      ..entries = const <NextcloudEntry>[
        NextcloudEntry(
          path: '/Dokumente',
          name: 'Dokumente',
          isDirectory: true,
        ),
      ];
    await pumpScreen(
      tester,
      const DocumentWalletScreen(),
      overrides: [
        documentWalletControllerProvider.overrideWith(_Wallet.new),
        nextcloudCredentialStoreProvider.overrideWithValue(
          InMemoryNextcloudCredentialStore()..value = _credential,
        ),
        nextcloudGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      AppLocales.german,
    );

    await tester.tap(find.byTooltip(l10n.documentWalletExportAction));
    await tester.pumpAndSettle();
    expect(find.text(l10n.documentWalletExportWarningTitle), findsOneWidget);
    await tester.tap(find.text(l10n.documentWalletExportContinue));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dokumente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.documentWalletExportHere));
    await tester.pumpAndSettle();

    expect(gateway.uploadedDirectories, <String>['/Dokumente']);
    expect(find.text(l10n.documentWalletExported), findsOneWidget);
  });

  testWidgets('declining the warning uploads nothing', (
    WidgetTester tester,
  ) async {
    final FakeNextcloudGateway gateway = FakeNextcloudGateway();
    await pumpScreen(
      tester,
      const DocumentWalletScreen(),
      overrides: [
        documentWalletControllerProvider.overrideWith(_Wallet.new),
        nextcloudCredentialStoreProvider.overrideWithValue(
          InMemoryNextcloudCredentialStore()..value = _credential,
        ),
        nextcloudGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      AppLocales.german,
    );

    await tester.tap(find.byTooltip(l10n.documentWalletExportAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.documentWalletCancel));
    await tester.pumpAndSettle();

    expect(gateway.uploadedDirectories, isEmpty);
    expect(gateway.listedPaths, isEmpty);
  });

  testWidgets('without a Nextcloud connection it explains instead', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const DocumentWalletScreen(),
      overrides: [
        documentWalletControllerProvider.overrideWith(_Wallet.new),
        nextcloudCredentialStoreProvider.overrideWithValue(
          InMemoryNextcloudCredentialStore(),
        ),
        nextcloudGatewayProvider.overrideWithValue(FakeNextcloudGateway()),
      ],
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      AppLocales.german,
    );

    await tester.tap(find.byTooltip(l10n.documentWalletExportAction));
    await tester.pumpAndSettle();

    expect(find.text(l10n.documentWalletExportNotConnected), findsOneWidget);
  });
}
