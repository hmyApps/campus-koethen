// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:enough_mail/enough_mail.dart';

import '../domain/mail_credentials.dart' as domain;
import '../domain/mail_message.dart' as model;

/// Builds the MIME message for an outgoing message, including attachments.
///
/// Pure and network-free — the single place both the SMTP send and the
/// best-effort Sent-folder copy get their bytes from, so the two are always
/// built from exactly the same [model.OutgoingMessage] the same way. From is
/// ALWAYS the account address; [domain.MailCredentials.displayName], if
/// given, becomes only the friendly label (`"Name" <address>`).
///
/// Mirrors `MessageBuilder.buildSimpleTextMessage`'s exact defaults
/// (`CharacterSet.utf8`, `TransferEncoding.quotedPrintable` for the text
/// part) so switching from the simple builder to the imperative one changes
/// nothing about the plain-text case. Binary attachments are added with
/// `addBinary`, which defaults to `TransferEncoding.base64` — the standard,
/// expected encoding for arbitrary binary content.
MimeMessage buildOutgoingMime(
  domain.MailCredentials credentials,
  model.OutgoingMessage message,
) {
  final model.MailAttachmentBudgetIssue? budgetIssue = model
      .mailAttachmentBudgetIssue(message.attachments);
  if (budgetIssue != null) {
    throw model.MailAttachmentLimitException(budgetIssue);
  }
  final MessageBuilder builder = MessageBuilder()
    ..from = <MailAddress>[
      MailAddress(credentials.displayName ?? '', credentials.emailAddress),
    ]
    ..to = message.to
        .map((String address) => MailAddress('', address))
        .toList(growable: false)
    ..cc = message.cc
        .map((String address) => MailAddress('', address))
        .toList(growable: false)
    ..subject = message.subject
    ..text = message.text
    ..characterSet = CharacterSet.utf8
    ..transferEncoding = TransferEncoding.quotedPrintable;

  for (final model.OutgoingAttachment attachment in message.attachments) {
    builder.addBinary(
      attachment.bytes,
      MediaType.fromText(attachment.mediaType),
      filename: attachment.filename,
    );
  }

  return builder.buildMimeMessage();
}
