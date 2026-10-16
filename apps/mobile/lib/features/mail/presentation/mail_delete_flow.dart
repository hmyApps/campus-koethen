// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../application/mail_folders.dart';
import '../application/mail_inbox_controller.dart';
import '../domain/mail_message.dart';
import 'mail_error_messages.dart';

/// Asks, then deletes [header] on the server and in the offline copy.
///
/// The message disappears from the list only after the server confirmed: a
/// failure leaves it where it is and says why. Returns whether it was deleted.
Future<bool> confirmAndDeleteMail(
  BuildContext context,
  WidgetRef ref,
  MailMessageHeader header,
) async {
  final AppLocalizations l10n = context.l10n;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool confirmed =
      await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(l10n.mailDeleteConfirmTitle),
          content: Text(l10n.mailDeleteConfirmBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.mailCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.mailDeleteConfirm),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed) return false;
  try {
    await ref.read(mailInboxControllerProvider.notifier).deleteMessage((
      mailboxPath: ref.read(selectedMailboxProvider).path,
      id: header.id,
    ));
    messenger.showSnackBar(SnackBar(content: Text(l10n.mailDeleteSuccess)));
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(mailFailureMessage(l10n, error))),
    );
    return false;
  }
}
