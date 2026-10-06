// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/document_wallet/domain/wallet_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognises only the two approved HISinOne document classes', () {
    expect(
      walletKindForCertificateLabel('Immatrikulationsbescheinigung'),
      WalletDocumentKind.enrollmentCertificate,
    );
    expect(walletKindForCertificateLabel('Gebührenbescheinigung'), isNull);
    expect(
      walletKindForExamReportLabel(
        'Leistungsübersicht (bestandene Leistungen) [PDF]',
      ),
      WalletDocumentKind.transcript,
    );
    expect(
      walletKindForExamReportLabel('Leistungsübersicht fehlende Leistungen'),
      isNull,
    );
  });
}
