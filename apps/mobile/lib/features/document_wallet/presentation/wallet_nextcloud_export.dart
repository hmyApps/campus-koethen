// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/documents/app_document.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../nextcloud/application/nextcloud_account_controller.dart';
import '../../nextcloud/application/nextcloud_providers.dart';
import '../../nextcloud/domain/nextcloud_account.dart';
import '../../nextcloud/domain/nextcloud_entry.dart';
import '../../nextcloud/domain/nextcloud_gateway.dart';
import '../../nextcloud/presentation/nextcloud_messages.dart';

/// Exports one wallet file to the user's Nextcloud, unencrypted.
///
/// A deliberate, confirmed action: the file leaves the encrypted wallet. The
/// upload never overwrites an existing file (the gateway refuses a clash).
Future<void> exportWalletDocumentToNextcloud(
  BuildContext context,
  WidgetRef ref,
  AppDocument document,
) async {
  final AppLocalizations l10n = context.l10n;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final NextcloudAccount? account = await ref.read(
    nextcloudAccountControllerProvider.future,
  );
  if (!context.mounted) return;
  if (account == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.documentWalletExportNotConnected)),
    );
    return;
  }
  final bool confirmed =
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(l10n.documentWalletExportWarningTitle),
          content: Text(l10n.documentWalletExportWarningMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.documentWalletCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.documentWalletExportContinue),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return;
  final String? folder = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const _FolderPicker(),
  );
  if (folder == null) return;
  try {
    final Uint8List bytes = document.bytes;
    await ref
        .read(nextcloudFileServiceProvider)
        .upload(
          folder,
          NextcloudUploadFile(
            filename: document.filename,
            mediaType: document.mediaType,
            length: bytes.length,
            openRead: () => Stream<Uint8List>.value(bytes),
          ),
        );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.documentWalletExported)),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(nextcloudFailureMessage(l10n, error))),
    );
  }
}

class _FolderPicker extends ConsumerStatefulWidget {
  const _FolderPicker();

  @override
  ConsumerState<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends ConsumerState<_FolderPicker> {
  String _path = '/';

  String get _parent {
    final List<String> parts = _path
        .split('/')
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 1) return '/';
    return '/${parts.sublist(0, parts.length - 1).join('/')}';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<NextcloudEntry>> folder = ref.watch(
      nextcloudFolderProvider(_path),
    );
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
                  l10n.documentWalletExportPickFolder,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                _path == '/' ? AppIcons.folder_outlined : AppIcons.arrow_back,
              ),
              title: Text(
                _path == '/' ? l10n.documentWalletExportRoot : _path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _path == '/'
                  ? null
                  : () => setState(() => _path = _parent),
            ),
            Flexible(
              child: folder.when(
                loading: () => const LoadingView(),
                error: (Object error, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(nextcloudFailureMessage(l10n, error)),
                ),
                data: (List<NextcloudEntry> entries) {
                  final List<NextcloudEntry> directories = entries
                      .where((NextcloudEntry e) => e.isDirectory)
                      .toList();
                  if (directories.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(l10n.documentWalletExportNoFolders),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final NextcloudEntry entry in directories)
                        ListTile(
                          leading: const Icon(AppIcons.folder_outlined),
                          title: Text(entry.name),
                          trailing: const Icon(AppIcons.chevron_right),
                          onTap: () => setState(() => _path = entry.path),
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_path),
                  child: Text(l10n.documentWalletExportHere),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
