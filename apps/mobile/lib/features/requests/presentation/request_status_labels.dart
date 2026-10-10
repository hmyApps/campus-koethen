// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../l10n/l10n.dart';
import '../domain/request_drafts.dart';
import '../domain/request_gateway.dart';
import '../domain/request_validation.dart';
import '../domain/status_gateway.dart';

/// Wording for everything the domain reports as a typed value.
///
/// Kept in one place so no visible German ever lands in domain or data code
/// (AGENTS.md §6) and so the two forms cannot drift apart in how they name the
/// same failure.
abstract final class RequestLabels {
  static String kind(AppLocalizations l10n, RequestKind kind) => switch (kind) {
    RequestKind.financeApplication => l10n.requestsCaseApplication,
    RequestKind.feedback => l10n.requestsCaseFeedback,
  };

  static String fieldError(
    AppLocalizations l10n,
    RequestFieldError error,
  ) => switch (error) {
    RequestFieldError.locationMissing => l10n.requestsErrorLocationMissing,
    RequestFieldError.titleMissing => l10n.requestsErrorTitleMissing,
    RequestFieldError.titleTooLong => l10n.requestsErrorTitleTooLong,
    RequestFieldError.applicantMissing => l10n.requestsErrorApplicantMissing,
    RequestFieldError.applicantTooLong => l10n.requestsErrorApplicantTooLong,
    RequestFieldError.requiredFileMissing => l10n.requestsErrorFileMissing,
    RequestFieldError.fileWrongType => l10n.requestsErrorFileWrongType,
    RequestFieldError.fileTooLarge => l10n.requestsErrorFileTooLarge,
    RequestFieldError.areaMissing => l10n.requestsErrorAreaMissing,
    RequestFieldError.submitterNameTooLong =>
      l10n.requestsErrorSubmitterNameTooLong,
    RequestFieldError.feedbackMissing => l10n.requestsErrorFeedbackMissing,
    RequestFieldError.feedbackTooLong => l10n.requestsErrorFeedbackTooLong,
  };

  /// The message for a submission outcome that is not a success.
  ///
  /// [SubmissionRejected] is deliberately absent: its issues belong at the
  /// fields they name, not in a banner that says "something was wrong".
  static String? submissionProblem(
    AppLocalizations l10n,
    SubmissionResult result,
  ) => switch (result) {
    SubmissionAccepted() => null,
    SubmissionRejected() => l10n.requestsSubmitRejected,
    SubmissionNotConnected() => l10n.requestsNotConnectedBody,
    SubmissionTargetGone() => l10n.requestsSubmitTargetGone,
    SubmissionConflict() => l10n.requestsSubmitConflict,
    SubmissionTooLarge() => l10n.requestsSubmitTooLarge,
    SubmissionUnsupportedMedia() => l10n.requestsSubmitUnsupportedMedia,
    SubmissionRateLimited() => l10n.requestsSubmitRateLimited,
    SubmissionOutcomeUnknown(acceptedWithoutUsableLink: true) =>
      l10n.requestsSubmitAcceptedUnusable,
    SubmissionOutcomeUnknown() => l10n.requestsSubmitOutcomeUnknown,
  };

  /// What a failed status read means for the reader.
  ///
  /// Never "the case is gone": a 404 here is indistinguishable from an unknown
  /// token, and the local record is what holds the only link back.
  static String? statusProblem(AppLocalizations l10n, StatusResult result) =>
      switch (result) {
        StatusLoaded() => null,
        StatusNotConnected() => l10n.requestsNotConnectedBody,
        StatusLinkInvalid() => l10n.requestsStatusLinkInvalid,
        StatusNotFound() => l10n.requestsStatusNotFound,
        StatusRateLimited() => l10n.requestsStatusRateLimited,
        StatusUnavailable() => l10n.requestsStatusUnavailable,
      };

  /// The committee's own column name, or a plain statement that there is none.
  ///
  /// The name is never mapped onto an app-side vocabulary: the boards choose
  /// their own words, and translating "Bei der Kasse" into "accepted" would
  /// report something nobody said.
  static String statusName(AppLocalizations l10n, String? name) =>
      (name ?? '').trim().isEmpty ? l10n.requestsStatusUnknownName : name!;

  static String actions(AppLocalizations l10n, {required String? submitMode}) =>
      switch (submitMode) {
        'resubmission' => l10n.requestsActionsResubmission,
        'receipt' => l10n.requestsActionsReceipt,
        _ => l10n.requestsActionsNone,
      };
}
