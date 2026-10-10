// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'mail_credentials.dart';
import 'mail_failure.dart';
import 'mail_folder.dart';
import 'mail_message.dart';

/// Outcome of trying to store a sent copy after a successful SMTP send.
enum SentCopyResult {
  /// Appended to the Sent/Gesendet folder.
  appended,

  /// The send succeeded but the copy could not be stored. The send still counts.
  appendFailed,

  /// No Sent-like folder exists and none is created unprompted.
  noSentFolder,
}

/// Signals emitted by the foreground IMAP watcher. No message content crosses
/// this stream; a change only asks the normal cache sync to reconcile.
enum MailLiveSignal { connected, pollingFallback, changed }

/// One page of headers plus the state of the mailbox it was read from.
///
/// The mailbox state is what makes a page interpretable: [messagesExists]
/// tells whether the page covered the whole mailbox, [uidValidity] whether
/// its UIDs still mean the same messages as the ones cached earlier.
class MailHeaderPage {
  const MailHeaderPage({
    required this.headers,
    required this.messagesExists,
    this.uidValidity,
  });

  /// The headers of this page, newest first.
  final List<MailMessageHeader> headers;

  /// Number of messages in the mailbox when the page was read (IMAP EXISTS).
  final int messagesExists;

  /// The mailbox's UIDVALIDITY, or null when the server did not report one.
  final int? uidValidity;
}

/// The single boundary to enough_mail.
///
/// No enough_mail type appears in this interface, so neither the UI nor the
/// Riverpod controllers ever depend on the library. Request methods open and
/// close their own connections; only [watchInbox] owns a cancellable IMAP IDLE
/// connection while the app is in the foreground.
abstract interface class MailGateway {
  /// Verifies BOTH the IMAP (993, implicit TLS) and SMTP (587, STARTTLS)
  /// connections and authentication. Throws [MailFailure] on any problem and
  /// never persists anything.
  Future<void> verifyConnection(MailCredentials credentials);

  /// Lists all mailboxes (folders) on the server via IMAP LIST.
  Future<List<MailFolder>> fetchMailboxes(MailCredentials credentials);

  /// Loads up to [limit] headers from [mailboxPath]. No bodies.
  ///
  /// Without [beforeId], the newest headers are returned. When [beforeId] is
  /// set, only messages with an older IMAP UID are considered; this provides a
  /// stable cursor even while new mail arrives or other messages are deleted.
  /// The page also reports the mailbox's EXISTS count and UIDVALIDITY as seen
  /// by the same SELECT.
  Future<MailHeaderPage> fetchHeaders(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    int limit = 50,
    String? beforeId,
  });

  /// Server-side search (IMAP SEARCH) over [mailboxPath]. Matches [query] in
  /// BOTH the sender and the content, so it finds messages that are not cached
  /// locally. Returns up to [limit] matching headers, newest first.
  Future<List<MailMessageHeader>> searchMessages(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String query,
    int limit = 50,
  });

  /// Loads one message from [mailboxPath] as safe plain text, plus attachments.
  ///
  /// Image attachments always carry their bytes (for the inline preview); other
  /// attachment bytes are decoded only when [includeAttachmentBytes] is true.
  Future<MailMessageDetail> fetchMessage(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
    bool includeAttachmentBytes = false,
  });

  /// Loads several messages from [mailboxPath] in ONE IMAP session, for
  /// efficient background prefetch. Missing ids are simply skipped.
  Future<List<MailMessageDetail>> fetchMessages(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required List<String> ids,
    bool includeAttachmentBytes = false,
  });

  /// Marks a message as \Seen. Best effort — failure is non-fatal to the caller.
  ///
  /// With [expectedUidValidity], nothing is changed unless the selected
  /// mailbox still reports that UIDVALIDITY; otherwise this throws
  /// [MailFailureKind.mailboxChanged].
  Future<void> markSeen(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
    int? expectedUidValidity,
  });

  /// Moves one message to the server's Trash folder. When the message already
  /// lives in Trash it is permanently removed. Implementations must address it
  /// by IMAP UID, never by the unstable sequence number.
  ///
  /// With [expectedUidValidity], nothing is changed unless the selected
  /// mailbox still reports that UIDVALIDITY; otherwise this throws
  /// [MailFailureKind.mailboxChanged].
  Future<void> deleteMessage(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
    int? expectedUidValidity,
  });

  /// Watches INBOX changes using IMAP IDLE, with a bounded NOOP polling
  /// fallback when the server does not advertise IDLE. Cancelling the stream
  /// must close the authenticated connection.
  Stream<MailLiveSignal> watchInbox(MailCredentials credentials);

  /// Sends a plain-text message via SMTP submission. Throws [MailFailure] if the
  /// send fails. Deliberately does NOT touch the Sent folder: storing a copy is
  /// a separate, slower step (a second IMAP connection) that must not keep the
  /// user waiting on the compose screen after the message has already left.
  Future<void> send(MailCredentials credentials, OutgoingMessage message);

  /// Best-effort copy of an already-sent message into the Sent/Gesendet folder.
  /// Never throws: the send has already succeeded, so any problem here is
  /// reported through [SentCopyResult], not by failing.
  Future<SentCopyResult> appendToSent(
    MailCredentials credentials,
    OutgoingMessage message,
  );
}
