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

  /// A file picked for an outgoing message could not be read at send time
  /// (e.g. it was deleted, moved, or revoked access in between). Never
  /// carries the path or the raw I/O error.
  attachmentUnreadable,

  /// The configured per-file, count or aggregate compose budget was exceeded.
  attachmentLimitExceeded,
}

/// A gateway/controller error carrying only a classification.
class MailFailure implements Exception {
  const MailFailure(this.kind);

  final MailFailureKind kind;

  @override
  String toString() => 'MailFailure(${kind.name})';
}
