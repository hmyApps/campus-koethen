// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:flutter/material.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/documents/app_document.dart';
import '../../../core/documents/document_share_service.dart';
import '../../../core/documents/document_viewer_screen.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../document_wallet/presentation/wallet_save_action.dart';
import '../domain/mail_failure.dart';
import '../domain/mail_message.dart';
import 'mail_error_messages.dart';

const DocumentShareService _shareService = DocumentShareService();

AppDocument _asDocument(MailAttachment a) => AppDocument(
  filename: a.filename,
  mediaType: a.mediaType,
  bytes: a.bytes!,
  sizeBytes: a.sizeBytes,
);

/// One attachment in the message detail.
///
/// Downloaded image attachments preview inline automatically; tapping any
/// downloaded attachment opens it in the shared [DocumentViewerScreen].
class MailAttachmentView extends StatefulWidget {
  const MailAttachmentView({
    required this.attachment,
    this.onDownload,
    super.key,
  });

  final MailAttachment attachment;
  final Future<MailAttachment> Function()? onDownload;

  @override
  State<MailAttachmentView> createState() => _MailAttachmentViewState();
}

class _MailAttachmentViewState extends State<MailAttachmentView> {
  late MailAttachment _attachment = widget.attachment;
  bool _downloading = false;

  @override
  void didUpdateWidget(MailAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment != widget.attachment) {
      _attachment = widget.attachment;
    }
  }

  Future<void> _open() async {
    final AppLocalizations l10n = context.l10n;
    if (_attachment.bytes == null) {
      final Future<MailAttachment> Function()? download = widget.onDownload;
      if (download == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.mailAttachmentDownloadFailed)),
        );
        return;
      }
      if (_downloading) return;
      setState(() => _downloading = true);
      try {
        final MailAttachment loaded = await download();
        if (loaded.bytes == null) {
          throw const MailFailure(MailFailureKind.protocol);
        }
        if (!mounted) return;
        setState(() => _attachment = loaded);
      } catch (error) {
        if (!mounted) return;
        final String message = error is MailFailure
            ? mailFailureMessage(l10n, error)
            : l10n.mailAttachmentDownloadFailed;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      } finally {
        if (mounted) setState(() => _downloading = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) =>
            DocumentViewerScreen(document: _asDocument(_attachment)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final int? size = _attachment.sizeBytes;
    final String subtitle = <String>[
      _attachment.mediaType,
      if (size != null)
        humanFileSize(
          size,
          locale: Localizations.localeOf(context).languageCode,
        ),
    ].join(' · ');

    final Widget tile = ListTile(
      leading: Icon(
        _attachment.isImage
            ? AppIcons.image_outlined
            : AppIcons.insert_drive_file_outlined,
      ),
      title: Text(
        _attachment.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, style: text.bodySmall),
      onTap: _downloading ? null : _open,
      trailing: _attachment.bytes == null
          ? _downloading
                ? const SizedBox(
                    width: AppSizes.icon,
                    height: AppSizes.icon,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    onPressed: _open,
                    tooltip: l10n.mailAttachmentDownload,
                    icon: const Icon(AppIcons.download_outlined),
                  )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                WalletSaveAction(document: _asDocument(_attachment)),
                IconButton(
                  onPressed: () =>
                      _shareService.share(_asDocument(_attachment)),
                  tooltip: l10n.mailAttachmentShare,
                  icon: const Icon(AppIcons.ios_share),
                ),
              ],
            ),
    );

    final Uint8List? imageBytes = _attachment.isImage
        ? _attachment.bytes
        : null;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (imageBytes != null)
            // The preview opens the same attachment as the tile below it. Left
            // in the tree it was a second, unlabelled tap target announcing
            // only "image" — so it is excluded and the tile stays the one way
            // in.
            ExcludeSemantics(
              child: InkWell(
                onTap: _open,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.contain,
                    errorBuilder:
                        (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) => const _ImageErrorPlaceholder(),
                  ),
                ),
              ),
            ),
          tile,
        ],
      ),
    );
  }
}

class _ImageErrorPlaceholder extends StatelessWidget {
  const _ImageErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return ColoredBox(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg,
          horizontal: AppSpacing.md,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              AppIcons.broken_image_outlined,
              size: AppSizes.icon,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                l10n.mailAttachmentPreviewUnavailable,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
