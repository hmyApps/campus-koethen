// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'exam_report.dart';
import 'grade_credentials.dart';

/// The HISinOne-only boundary for downloading one of the exam overview's own
/// fixed "Bescheinigungen" print buttons. Unlike [GradesGateway], which both
/// portals implement, this capability exists only on HISinOne — the legacy
/// portal has no such section — so it is its own interface rather than an
/// addition to the shared one, exactly like `StudentServiceGateway`.
abstract interface class ExamReportGateway {
  /// Logs in with [credentials] — the SAME credentials grades already
  /// verified — re-reads the exam overview fresh, refuses if [offer] is no
  /// longer listed, then submits that one fixed button as a normal full
  /// form POST (never AJAX) and follows the resulting same-host redirect
  /// chain to the document.
  ///
  /// Throws [GradeFailure] only for a portal-structure problem; every other
  /// outcome is an [ExamReportDownloadResult].
  Future<ExamReportDownloadResult> downloadExamReport(
    GradeCredentials credentials,
    ExamReportOffer offer,
  );
}
