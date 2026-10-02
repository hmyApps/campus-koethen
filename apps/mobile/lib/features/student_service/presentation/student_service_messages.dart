// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../l10n/l10n.dart';
import '../domain/student_service_failure.dart';

/// Maps a [StudentServiceFailure] to a localized, user-safe message. Switches
/// only on the typed kind — no raw portal text, HTML or session detail ever
/// reaches the UI. Same contract as `gradeFailureMessage`.
/// A short, fixed, non-sensitive label naming which specific structural
/// check failed (e.g. `'personalData'`, `'tabSwitch:report'`) — never raw
/// HTML, a URL or anything read from the portal. `null` unless [error] is a
/// [StudentServiceFailure] of kind [StudentServiceFailureKind.portalStructureChanged]
/// with a [StudentServiceFailure.stage] set. Shown alongside the ordinary
/// message so a report of a real portal mismatch can name the exact check
/// without needing device logs.
String? studentServiceDiagnosticStage(Object? error) =>
    error is StudentServiceFailure &&
        error.kind == StudentServiceFailureKind.portalStructureChanged
    ? error.stage
    : null;

String studentServiceFailureMessage(AppLocalizations l10n, Object? error) {
  if (error is StudentServiceFailure) {
    return switch (error.kind) {
      StudentServiceFailureKind.notConnected =>
        l10n.studentServiceNotConnectedMessage,
      StudentServiceFailureKind.invalidCredentials =>
        l10n.studentServiceErrorInvalidCredentials,
      StudentServiceFailureKind.tlsOrHostRejected =>
        l10n.studentServiceErrorTls,
      StudentServiceFailureKind.portalUnavailable =>
        l10n.studentServiceErrorPortalUnavailable,
      StudentServiceFailureKind.portalStructureChanged =>
        l10n.studentServiceErrorStructureChanged,
      StudentServiceFailureKind.timeout => l10n.studentServiceErrorTimeout,
      StudentServiceFailureKind.networkUnavailable =>
        l10n.studentServiceErrorNetwork,
      StudentServiceFailureKind.cacheUnavailable =>
        l10n.studentServiceErrorCache,
      StudentServiceFailureKind.documentTooLarge =>
        l10n.studentServiceErrorDocumentTooLarge,
      StudentServiceFailureKind.documentUnavailable =>
        l10n.studentServiceErrorDocumentUnavailable,
      StudentServiceFailureKind.unknown => l10n.studentServiceErrorGeneric,
    };
  }
  return l10n.studentServiceErrorGeneric;
}
