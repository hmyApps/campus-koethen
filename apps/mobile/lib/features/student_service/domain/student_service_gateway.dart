// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import '../../grades/domain/grade_credentials.dart';
import 'student_service_overview.dart';

/// What came back from generating and fetching one certificate.
sealed class CertificateDownloadResult {
  const CertificateDownloadResult();
}

class CertificateDownloadLoaded extends CertificateDownloadResult {
  const CertificateDownloadLoaded({
    required this.bytes,
    required this.filename,
  });

  final Uint8List bytes;
  final String filename;
}

/// Larger than the in-app budget — never downloaded past the limit.
class CertificateTooLarge extends CertificateDownloadResult {
  const CertificateTooLarge();
}

class CertificateUnavailable extends CertificateDownloadResult {
  const CertificateUnavailable(this.reason);

  /// A short technical reason. Never a URL, a token or portal HTML.
  final String reason;
}

/// The single boundary to the read-only HISinOne student-service functions.
///
/// No Dio, cookie or HTML type appears here, so neither the UI nor the
/// Riverpod controllers depend on the transport. The implementation talks
/// ONLY to the pinned portal host (and, for exactly the generated-document
/// fetch, the separately pinned download host), logs out and clears the
/// session after every call, and maps every raw error to a
/// [StudentServiceFailure] so nothing sensitive escapes.
abstract interface class StudentServiceGateway {
  /// Logs in with [credentials] — the SAME credentials grades already
  /// verified, read fresh by the caller, never stored again here — navigates
  /// every tab of the "Studienservice" page, then logs out.
  ///
  /// Throws [StudentServiceFailure] on any problem. A tab whose content this
  /// build does not recognise is a [StudentServiceFailureKind.portalStructureChanged]
  /// failure, not a guess at its content.
  Future<StudentServiceOverview> fetchOverview(GradeCredentials credentials);

  /// Starts the AJAX generation job for [jobButtonId], polls until the
  /// portal reports it done, then fetches the resulting document from the
  /// one-time link the job hands back.
  ///
  /// Every step after login is a single HISinOne session: starting the job,
  /// polling and fetching the document all happen before that session's
  /// logout, because the download link is scoped to it.
  ///
  /// [isCancelled] is checked before every poll tick and before the document
  /// fetch. Once it reports `true` the job is abandoned (the session still
  /// logs out) and [CertificateUnavailable] with reason `cancelled` is
  /// returned — so deleting the grades connection never waits out the whole
  /// polling budget.
  Future<CertificateDownloadResult> downloadCertificate(
    GradeCredentials credentials,
    CertificateOffer offer, {
    bool Function()? isCancelled,
  });
}
