// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'request_drafts.dart';
import 'request_validation.dart';

/// What came back from an attempt to submit.
///
/// One case per outcome the endpoint documents, because they call for different
/// things from the user: a rejected field can be corrected, a conflict cannot,
/// a rate limit only needs patience, and an unreachable endpoint should be
/// retried with the *same* key.
sealed class SubmissionResult {
  const SubmissionResult();
}

/// The submission became a case.
class SubmissionAccepted extends SubmissionResult {
  const SubmissionAccepted({
    required this.statusUrl,
    required this.receiptPdfUrl,
    required this.number,
    required this.wasReplay,
  });

  /// Secret status link — never logged, never put in a route.
  final String statusUrl;

  /// Receipt PDF, same token.
  final String receiptPdfUrl;

  final String? number;

  /// True for HTTP 200 / `Idempotency-Replayed: true`. A replay is a success:
  /// the case exists and nothing was filed twice.
  final bool wasReplay;
}

/// No endpoint is configured in this build.
///
/// The honest answer when `REQUESTS_BASE_URL` is empty or not HTTPS — **not**
/// an error, and emphatically not a fake success.
class SubmissionNotConnected extends SubmissionResult {
  const SubmissionNotConnected();
}

/// The endpoint refused the input (400), or a required field is missing.
class SubmissionRejected extends SubmissionResult {
  const SubmissionRejected({
    this.message = '',
    this.fieldErrors = const <RequestField, String>{},
    this.generalIssues = const <String>[],
  });

  /// The endpoint's own wording, written for the applicant.
  final String message;

  /// Issues mapped onto real form fields, so the form can point at them.
  final Map<RequestField, String> fieldErrors;

  /// Issues naming a field this build does not know. Shown as general text
  /// rather than dropped — an unmapped message is still information.
  final List<String> generalIssues;
}

/// The chosen location or area no longer exists (404).
class SubmissionTargetGone extends SubmissionResult {
  const SubmissionTargetGone({this.message = ''});

  final String message;
}

/// The same key was used for a different submission (409).
///
/// Not retryable: sending again cannot help, and sending with a fresh key
/// would file a second case. Needs a decision from the user.
class SubmissionConflict extends SubmissionResult {
  const SubmissionConflict();
}

/// A file, or the whole request, exceeded the size limit (413).
class SubmissionTooLarge extends SubmissionResult {
  const SubmissionTooLarge();
}

/// The endpoint rejected the content type (415). A client defect, not the
/// user's — surfaced separately so it cannot hide as a validation error.
class SubmissionUnsupportedMedia extends SubmissionResult {
  const SubmissionUnsupportedMedia();
}

/// Rate limited (429).
class SubmissionRateLimited extends SubmissionResult {
  const SubmissionRateLimited({this.retryAfter});

  final Duration? retryAfter;
}

/// Reached nobody, or the answer was ambiguous: no network, timeout, 5xx.
///
/// **The outcome is unknown.** The case may or may not have been filed, which
/// is exactly what the idempotency key exists for — the draft is frozen with a
/// [PendingSubmission] and a retry sends the identical payload under the same
/// key.
class SubmissionOutcomeUnknown extends SubmissionResult {
  const SubmissionOutcomeUnknown(this.reason)
    : acceptedWithoutUsableLink = false;

  /// The endpoint answered 200/201, but its status or receipt link was
  /// missing, not HTTPS or not on the configured origin.
  ///
  /// Not a failure: the case very likely exists. It cannot be stored without
  /// a usable link (and a foreign link must never receive the token), so the
  /// draft freezes and only an identical replay may follow — which returns
  /// the same case again if the endpoint is fixed.
  const SubmissionOutcomeUnknown.acceptedWithoutUsableLink(this.reason)
    : acceptedWithoutUsableLink = true;

  /// A short technical reason. Never carries the payload, a link or a name.
  final String reason;

  final bool acceptedWithoutUsableLink;
}

/// Port: whatever accepts submissions.
///
/// Two methods rather than one over a sealed draft: the endpoints differ in
/// path, content type and body shape, and a single method would only push that
/// switch one layer down while making both signatures vaguer.
/// How far an upload has got: bytes sent and, when the total is known, the
/// total. A four-document application can take minutes on mobile data.
typedef SubmissionProgress = void Function(int sent, int total);

abstract interface class RequestGateway {
  /// [onProgress] reports upload progress; [cancel] abandons the request.
  ///
  /// A cancelled submission produces [SubmissionOutcomeUnknown], exactly like
  /// a timeout — the bytes may or may not have arrived, and the draft has to
  /// be frozen either way so a retry replays under the same key rather than
  /// filing a second case.
  Future<SubmissionResult> submitApplication(
    FinanceApplicationDraft draft, {
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  });

  Future<SubmissionResult> submitFeedback(
    FeedbackDraft draft, {
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  });
}

/// A handle the UI keeps so it can abandon an upload in flight.
///
/// Deliberately its own type rather than Dio's `CancelToken`: the domain layer
/// must not know which HTTP client is underneath.
class SubmissionCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }

  /// Wired up by the gateway so a cancel reaches the transport.
  // ignore: use_setters_to_change_properties
  void bind(void Function() onCancel) => _onCancel = onCancel;
}

/// Used when no endpoint is configured for this build.
///
/// Inventing a URL or simulating a success would produce an app that tells
/// students their application was filed when nobody received it.
class NotConnectedRequestGateway implements RequestGateway {
  const NotConnectedRequestGateway();

  @override
  Future<SubmissionResult> submitApplication(
    FinanceApplicationDraft draft, {
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  }) => Future<SubmissionResult>.value(const SubmissionNotConnected());

  @override
  Future<SubmissionResult> submitFeedback(
    FeedbackDraft draft, {
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  }) => Future<SubmissionResult>.value(const SubmissionNotConnected());
}
