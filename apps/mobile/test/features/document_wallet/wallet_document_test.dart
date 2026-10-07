// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/document_wallet/domain/wallet_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognises the approved HISinOne document classes', () {
    expect(
      walletKindForCertificateLabel('Immatrikulationsbescheinigung'),
      WalletDocumentKind.enrollmentCertificate,
    );
    expect(
      walletKindForCertificateLabel('Gebührenbescheinigung'),
      WalletDocumentKind.feeCertificate,
    );
    expect(
      walletKindForCertificateLabel('Studienverlaufsbescheinigung'),
      WalletDocumentKind.studyProgressCertificate,
    );
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

  test('an unrecognised label is never silently accepted into the wallet', () {
    expect(walletKindForCertificateLabel('Irgendein anderes Dokument'), isNull);
  });
}
