// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Why a mail operation failed, in terms the UI can localise.
///
/// This enum is the ONLY error detail that crosses the gateway boundary. Raw
/// server responses, stack traces and — above all — credentials never do.
enum MailFailureKind {
  invalidEmail,
  invalidCredentials,
  network,
  timeout,
  tls,
  serverUnreachable,
  protocol,
  secureStorageUnavailable,
  localDataWipeIncomplete,

  /// The account was removed or replaced while this request was in flight, so
  /// the result belongs to a session that no longer exists.
  ///
  /// Deliberately *not* [invalidCredentials]: nothing is wrong with anyone's
  /// password here, and reporting a deliberate disconnect as "sign-in failed"
  /// sent people off to re-enter a password that was never rejected.
  sessionClosed,

  /// The server renumbered the mailbox (its UIDVALIDITY changed) since the
  /// message ids in use were read, so an id may now name another message.
  /// Destructive actions refuse to run; a refresh rebuilds the list.
  mailboxChanged,

  /// The SMTP submission stalled after the message data had been handed to
  /// the server. The server may or may not have accepted it, so the message
  /// must not be re-sent automatically; the user should check the Sent
  /// folder first.
  sendOutcomeUnknown,

  /// A file picked for an outgoing message could not be read at send time
  /// (e.g. it was deleted, moved, or revoked access in between). Never
  /// carries the path or the raw I/O error.
  attachmentUnreadable,

  /// The configured per-file, count or aggregate compose budget was exceeded.
  attachmentLimitExceeded,
}

/// A gateway/controller error carrying only a classification.
class MailFailure implements Exception {
  const MailFailure(this.kind, {this.step, this.detail});

  final MailFailureKind kind;

  /// Which step of a multi-step server action failed (e.g. `copy`), for the
  /// few actions where "unexpected response" alone cannot be diagnosed. A
  /// fixed label, never user content.
  final String? step;

  /// The server's own short reason for refusing [step], shortened. Shown on
  /// screen only; never logged or reported.
  final String? detail;

  @override
  String toString() => 'MailFailure(${kind.name})';
}
