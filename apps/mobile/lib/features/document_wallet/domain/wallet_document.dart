// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../../core/documents/app_document.dart';

enum WalletDocumentKind {
  enrollmentCertificate('enrollment-certificate'),
  transcript('transcript'),
  feeCertificate('fee-certificate'),
  studyProgressCertificate('study-progress-certificate');

  const WalletDocumentKind(this.storageValue);

  final String storageValue;

  static WalletDocumentKind? fromStorage(String? value) {
    for (final WalletDocumentKind kind in values) {
      if (kind.storageValue == value) return kind;
    }
    return null;
  }
}

@immutable
class WalletDocument {
  WalletDocument({
    required this.kind,
    required String filename,
    required this.mediaType,
    required Uint8List bytes,
    required this.savedAt,
  }) : filename = safeDocumentFilename(filename),
       bytes = Uint8List.fromList(bytes);

  factory WalletDocument.fromAppDocument({
    required WalletDocumentKind kind,
    required AppDocument document,
    required DateTime savedAt,
  }) => WalletDocument(
    kind: kind,
    filename: document.filename,
    mediaType: document.mediaType,
    bytes: document.bytes,
    savedAt: savedAt,
  );

  final WalletDocumentKind kind;
  final String filename;
  final String mediaType;
  final Uint8List bytes;
  final DateTime savedAt;

  AppDocument toAppDocument() => AppDocument(
    filename: filename,
    mediaType: mediaType,
    bytes: Uint8List.fromList(bytes),
    sizeBytes: bytes.length,
  );
}

enum DocumentWalletFailureKind { invalidDocument, storageUnavailable }

class DocumentWalletFailure implements Exception {
  const DocumentWalletFailure(this.kind);

  final DocumentWalletFailureKind kind;
}

abstract interface class DocumentWalletStore {
  Future<List<WalletDocument>> readAll();
  Future<void> save(WalletDocument document);
  Future<void> delete(WalletDocumentKind kind);
  Future<void> clear();
}

/// The wallet intentionally accepts only these specific, confirmed-real
/// Studienservice "Bescheinigungen" offers — never an arbitrary/unrecognised
/// one — matched by label text since the portal gives no stable id for them.
WalletDocumentKind? walletKindForCertificateLabel(String label) {
  final String value = label.trim().toLowerCase();
  if (value.contains('immatrikulationsbescheinigung') ||
      value.contains('studienbescheinigung') ||
      value.contains('certificate of enrolment') ||
      value.contains('certificate of enrollment')) {
    return WalletDocumentKind.enrollmentCertificate;
  }
  if (value.contains('gebührenbescheinigung') ||
      value.contains('gebuehrenbescheinigung')) {
    return WalletDocumentKind.feeCertificate;
  }
  if (value.contains('studienverlaufsbescheinigung')) {
    return WalletDocumentKind.studyProgressCertificate;
  }
  return null;
}

/// Missing-exam lists are not a transcript and must never silently replace it.
WalletDocumentKind? walletKindForExamReportLabel(String label) {
  final String value = label.trim().toLowerCase();
  if (value.contains('fehlende leistungen') || value.contains('missing exam')) {
    return null;
  }
  if (value.contains('leistungsübersicht') ||
      value.contains('leistungsuebersicht') ||
      value.contains('list of passed exam') ||
      (value.contains('bestandene') && value.contains('prüfung'))) {
    return WalletDocumentKind.transcript;
  }
  return null;
}
