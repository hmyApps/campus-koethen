// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Server-facing compose budget.
///
/// SMTP base64 expands binary data by roughly one third. The 20 MiB binary
/// ceiling therefore stays below a common 25 MiB message limit while headers
/// and text still have room. Builds can align all three values with the real
/// server policy through `--dart-define` without changing source code.
abstract final class MailAttachmentLimits {
  static const int maxCount = int.fromEnvironment(
    'MAIL_ATTACHMENT_MAX_COUNT',
    defaultValue: 10,
  );
  static const int maxFileBytes = int.fromEnvironment(
    'MAIL_ATTACHMENT_MAX_FILE_BYTES',
    defaultValue: 20 * 1024 * 1024,
  );
  static const int maxTotalBytes = int.fromEnvironment(
    'MAIL_ATTACHMENT_MAX_TOTAL_BYTES',
    defaultValue: 20 * 1024 * 1024,
  );
}

enum MailAttachmentBudgetIssue { tooMany, fileTooLarge, totalTooLarge }

MailAttachmentBudgetIssue? mailAttachmentBudgetIssue(
  Iterable<OutgoingAttachment> attachments,
) {
  int count = 0;
  int total = 0;
  for (final OutgoingAttachment attachment in attachments) {
    count++;
    if (count > MailAttachmentLimits.maxCount) {
      return MailAttachmentBudgetIssue.tooMany;
    }
    final int size = attachment.bytes.length;
    if (size > MailAttachmentLimits.maxFileBytes) {
      return MailAttachmentBudgetIssue.fileTooLarge;
    }
    total += size;
    if (total > MailAttachmentLimits.maxTotalBytes) {
      return MailAttachmentBudgetIssue.totalTooLarge;
    }
  }
  return null;
}

class MailAttachmentLimitException implements Exception {
  const MailAttachmentLimitException(this.issue);

  final MailAttachmentBudgetIssue issue;
}

/// A single mailbox address as shown in the UI.
@immutable
class MailAddress {
  const MailAddress({required this.email, this.name});

  final String email;
  final String? name;

  /// What the list and detail views show: the name if present, else the email.
  String get display =>
      (name != null && name!.trim().isNotEmpty) ? name! : email;
}

/// Lightweight header for the inbox list. No body, no attachments downloaded.
@immutable
class MailMessageHeader {
  const MailMessageHeader({
    required this.id,
    required this.subject,
    required this.from,
    required this.date,
    required this.isSeen,
    required this.hasAttachments,
  });

  /// Stable per-mailbox identifier (the IMAP UID as a string). Opaque to the UI.
  final String id;
  final String subject;
  final MailAddress from;
  final DateTime? date;
  final bool isSeen;
  final bool hasAttachments;

  MailMessageHeader copyWith({bool? isSeen}) => MailMessageHeader(
    id: id,
    subject: subject,
    from: from,
    date: date,
    isSeen: isSeen ?? this.isSeen,
    hasAttachments: hasAttachments,
  );
}

/// Full message for the detail view.
@immutable
class MailMessageDetail {
  const MailMessageDetail({
    required this.id,
    required this.subject,
    required this.from,
    required this.to,
    required this.date,
    required this.body,
    this.cc = const <MailAddress>[],
    this.attachments = const <MailAttachment>[],
  });

  final String id;
  final String subject;
  final MailAddress from;
  final List<MailAddress> to;

  /// Carbon-copy recipients. Needed so "reply all" can address everyone.
  final List<MailAddress> cc;
  final DateTime? date;

  /// Already reduced to safe plain text by the gateway: text/plain preferred,
  /// HTML sanitised to text. Never HTML, never a WebView payload.
  final String body;

  /// The message's attachments (metadata always; bytes only for images, for an
  /// inline preview). Empty when the message has none.
  final List<MailAttachment> attachments;

  bool get hasAttachments => attachments.isNotEmpty;
}

/// One attachment of a message.
///
/// [bytes] holds the decoded content: images always carry it (for the inline
/// preview from memory — no file written, nothing fetched from the network),
/// and other types carry it only once downloaded (the offline setting). When
/// [bytes] is null only metadata is known.
@immutable
class MailAttachment {
  const MailAttachment({
    required this.filename,
    required this.mediaType,
    this.sizeBytes,
    this.bytes,
  });

  final String filename;

  /// e.g. `image/png`, `application/pdf`.
  final String mediaType;
  final int? sizeBytes;
  final Uint8List? bytes;

  bool get isImage => mediaType.toLowerCase().startsWith('image/');

  /// True when the content is on the device (previewable / shareable offline).
  bool get isDownloaded => bytes != null;
}

/// A file attached to an outgoing message.
///
/// [bytes] holds the exact content to send — read once when the user picked
/// the file (or freshly re-read at send time by the caller), never a file
/// path. Nothing platform-specific (no `File`, no picker type) crosses the
/// domain boundary, and nothing here forces re-reading a file that might have
/// vanished by send time; that decision belongs to the caller. This mirrors
/// [MailAttachment], which already holds incoming attachment bytes in memory
/// the same way.
@immutable
class OutgoingAttachment {
  const OutgoingAttachment({
    required this.filename,
    required this.mediaType,
    required this.bytes,
  });

  final String filename;

  /// e.g. `image/png`, `application/pdf`.
  final String mediaType;
  final Uint8List bytes;
}

/// An outgoing plain-text message, optionally with file attachments.
///
/// [to] and [cc] are lists so a normal message, a reply and a "reply all" all
/// use the same shape. The sender is never part of this object — it is always
/// the signed-in account address, set by the gateway.
@immutable
class OutgoingMessage {
  const OutgoingMessage({
    required this.to,
    required this.subject,
    required this.text,
    this.cc = const <String>[],
    this.attachments = const <OutgoingAttachment>[],
  });

  final List<String> to;
  final List<String> cc;
  final String subject;
  final String text;
  final List<OutgoingAttachment> attachments;
}
