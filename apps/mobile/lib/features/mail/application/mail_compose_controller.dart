// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mail_gateway.dart';
import '../domain/mail_failure.dart';
import '../domain/mail_message.dart';
import 'mail_account_controller.dart';
import 'mail_providers.dart';

/// Drives a single send. Guards against double submission and never retries
/// automatically when the outcome is unclear.
///
/// The state (`true` while sending) covers ONLY the SMTP submission — the part
/// the user is waiting on. Storing a copy in the Sent folder is a separate,
/// best-effort step ([appendSentCopy]) so the compose screen can close the
/// instant the message has actually left, instead of lingering on a spinner
/// through a second IMAP round trip.
class MailComposeController extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(mailSessionGenerationProvider);
    return false; // false = idle, true = sending
  }

  /// SMTP-submits [message]. Returns `true` on success, `false` if a send was
  /// already in flight (the second trigger is ignored). Throws [MailFailure]
  /// if the submission fails — the caller must not treat that as sent.
  Future<bool> send(OutgoingMessage message) async {
    if (state) return false; // already sending — ignore the second trigger
    if (mailAttachmentBudgetIssue(message.attachments) != null) {
      throw const MailFailure(MailFailureKind.attachmentLimitExceeded);
    }
    state = true;
    try {
      final credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      await ref.read(mailGatewayProvider).send(credentials, message);
      return true;
    } finally {
      state = false;
    }
  }

  /// Best-effort copy of an already-sent [message] into the Sent folder. Never
  /// throws; returns what became of the copy so the UI can hint if it failed.
  Future<SentCopyResult> appendSentCopy(OutgoingMessage message) async {
    try {
      final credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      return await ref
          .read(mailGatewayProvider)
          .appendToSent(credentials, message);
    } catch (_) {
      return SentCopyResult.appendFailed;
    }
  }
}

final NotifierProvider<MailComposeController, bool>
mailComposeControllerProvider = NotifierProvider<MailComposeController, bool>(
  MailComposeController.new,
);
