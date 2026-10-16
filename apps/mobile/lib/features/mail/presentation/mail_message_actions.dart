// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../application/mail_folders.dart';
import '../application/mail_inbox_controller.dart';
import '../domain/mail_folder.dart';
import '../domain/mail_message.dart';
import 'mail_delete_flow.dart';
import 'mail_error_messages.dart';
import 'mail_folder_labels.dart';

enum _MailAction { move, delete }

/// The options a long press on a message offers: move it or delete it.
Future<void> showMailMessageActions(
  BuildContext context,
  WidgetRef ref,
  MailMessageHeader header,
) async {
  final AppLocalizations l10n = context.l10n;
  final _MailAction? action = await showModalBottomSheet<_MailAction>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(AppIcons.folder_outlined),
            title: Text(l10n.mailMove),
            onTap: () => Navigator.of(sheetContext).pop(_MailAction.move),
          ),
          ListTile(
            leading: const Icon(AppIcons.delete_outline),
            title: Text(l10n.mailDelete),
            onTap: () => Navigator.of(sheetContext).pop(_MailAction.delete),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _MailAction.delete:
      await confirmAndDeleteMail(context, ref, header);
    case _MailAction.move:
      await chooseFolderAndMoveMail(context, ref, header);
  }
}

/// Lets the user pick a destination folder, then moves [header] there.
///
/// Like deleting, the message leaves the list only after the server confirmed.
Future<bool> chooseFolderAndMoveMail(
  BuildContext context,
  WidgetRef ref,
  MailMessageHeader header,
) async {
  final AppLocalizations l10n = context.l10n;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String currentPath = ref.read(selectedMailboxProvider).path;
  final MailFolder? target = await showModalBottomSheet<MailFolder>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) =>
        _FolderChoice(currentPath: currentPath),
  );
  if (target == null) return false;
  try {
    await ref.read(mailInboxControllerProvider.notifier).moveMessage((
      mailboxPath: currentPath,
      id: header.id,
    ), target.path);
    messenger.showSnackBar(SnackBar(content: Text(l10n.mailMoveSuccess)));
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(mailFailureMessage(l10n, error))),
    );
    return false;
  }
}

class _FolderChoice extends ConsumerWidget {
  const _FolderChoice({required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<MailFolder>> folders = ref.watch(mailFoldersProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.mailMoveTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            Flexible(
              child: folders.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, _) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(mailFailureMessage(l10n, error)),
                      TextButton(
                        onPressed: () => ref.invalidate(mailFoldersProvider),
                        child: Text(l10n.mailFoldersRetry),
                      ),
                    ],
                  ),
                ),
                data: (List<MailFolder> all) {
                  final List<MailFolder> targets = all
                      .where(
                        (MailFolder f) =>
                            f.isSelectable && f.path != currentPath,
                      )
                      .toList(growable: false);
                  if (targets.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: Text(l10n.mailMoveNoFolders),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final MailFolder folder in targets)
                        ListTile(
                          leading: Icon(folderIcon(folder.role)),
                          title: Text(folderLabel(l10n, folder)),
                          onTap: () => Navigator.of(context).pop(folder),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
