// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../domain/mail_message.dart';
import 'mail_delete_flow.dart';
import 'mail_message_actions.dart';

/// One row in a message list (inbox or search results): sender, subject, date
/// and an attachment marker. Tapping opens the message in the selected mailbox.
class MailHeaderTile extends ConsumerWidget {
  const MailHeaderTile({required this.header, required this.locale, super.key});

  final MailMessageHeader header;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final FontWeight weight = header.isSeen
        ? FontWeight.normal
        : FontWeight.w700;
    final String sender = header.from.display.trim().isEmpty
        ? l10n.mailUnknownSender
        : header.from.display;
    final String subject = header.subject.trim().isEmpty
        ? l10n.mailNoSubject
        : header.subject;

    // Read and unread are doubly coded for the eye — glyph plus weight — but
    // both of those are invisible to a screen reader, which heard two rows
    // that sounded exactly alike. The state goes into the row's own label.
    final List<String> states = <String>[
      header.isSeen ? l10n.mailReadSemantic : l10n.mailUnreadSemantic,
      if (header.hasAttachments) l10n.mailHasAttachmentSemantic,
    ];

    // Long press (and the matching screen reader action) deletes: the delete
    // button otherwise exists only inside the opened message.
    final String deleteLabel = l10n.mailDelete;
    return Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: deleteLabel): () =>
            confirmAndDeleteMail(context, ref, header),
        CustomSemanticsAction(label: l10n.mailMove): () =>
            chooseFolderAndMoveMail(context, ref, header),
      },
      child: ListTile(
        leading: Semantics(
          label: states.join(', '),
          child: Icon(
            header.isSeen ? AppIcons.mail_outline : AppIcons.markunread,
          ),
        ),
        title: Text(
          sender,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodyLarge?.copyWith(fontWeight: weight),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(fontWeight: weight),
            ),
            if (header.date != null)
              Text(
                AppDateFormats.dateTime(header.date!, locale),
                style: text.bodySmall,
              ),
          ],
        ),
        // The marker is already named in the leading node's label; repeating it
        // here would make every attachment row say it twice.
        trailing: header.hasAttachments
            ? const ExcludeSemantics(
                child: Icon(AppIcons.attach_file, size: AppSizes.icon),
              )
            : null,
        isThreeLine: header.date != null,
        onTap: () => context.pushNamed(
          AppRoutes.mailMessageName,
          pathParameters: <String, String>{'id': header.id},
        ),
        onLongPress: () => showMailMessageActions(context, ref, header),
      ),
    );
  }
}
