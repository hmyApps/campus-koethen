// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/links/linkified_text.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/mail_account_controller.dart';
import '../application/mail_folders.dart';
import '../application/mail_inbox_controller.dart';
import '../domain/mail_failure.dart';
import '../domain/mail_message.dart';
import 'compose_draft.dart';
import 'mail_attachment_view.dart';
import 'mail_error_messages.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// Reads one message. The body is already reduced to safe plain text by the
/// gateway (text/plain preferred, HTML sanitised): there is no WebView, no
/// JavaScript and no remote image loading here.
class MailMessageScreen extends ConsumerStatefulWidget {
  const MailMessageScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<MailMessageScreen> createState() => _MailMessageScreenState();
}

class _MailMessageScreenState extends ConsumerState<MailMessageScreen> {
  bool _deleting = false;

  /// Opens the compose screen pre-filled as a reply (or reply-all) to [detail].
  void _reply(
    BuildContext context,
    MailMessageDetail detail, {
    required bool all,
  }) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final String sender = detail.from.display.trim().isEmpty
        ? detail.from.email
        : detail.from.display;
    final String date = detail.date != null
        ? AppDateFormats.dateTime(detail.date!, locale)
        : '';
    final String attribution = l10n.mailReplyAttribution(date, sender);
    final String self =
        ref.read(mailAccountControllerProvider).value?.emailAddress ?? '';

    final ComposeDraft draft = all
        ? ComposeDraft.replyAll(
            detail,
            selfEmail: self,
            attribution: attribution,
          )
        : ComposeDraft.reply(detail, attribution: attribution);
    context.push(AppRoutes.mailCompose, extra: draft);
  }

  Future<void> _delete(MailMessageRef messageRef) async {
    final AppLocalizations l10n = context.l10n;
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
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(mailInboxControllerProvider.notifier)
          .deleteMessage(messageRef);
      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.mailDeleteSuccess)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mailFailureMessage(l10n, error))));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final MailMessageRef messageRef = (
      mailboxPath: ref.watch(selectedMailboxProvider).path,
      id: widget.id,
    );
    final AsyncValue<MailMessageDetail> message = ref.watch(
      mailMessageProvider(messageRef),
    );
    final MailMessageDetail? detail = message.value;

    return ScreenScaffold(
      title: l10n.mailTitle,
      actions: detail == null
          ? null
          : <Widget>[
              IconButton(
                onPressed: _deleting
                    ? null
                    : () => _reply(context, detail, all: false),
                tooltip: l10n.mailReply,
                icon: const Icon(AppIcons.reply),
              ),
              IconButton(
                onPressed: _deleting
                    ? null
                    : () => _reply(context, detail, all: true),
                tooltip: l10n.mailReplyAll,
                icon: const Icon(AppIcons.reply_all),
              ),
              IconButton(
                onPressed: _deleting ? null : () => _delete(messageRef),
                tooltip: l10n.mailDelete,
                icon: _deleting
                    ? const SizedBox.square(
                        dimension: AppSizes.icon,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.delete_outline),
              ),
            ],
      body: message.when(
        loading: () => const LoadingView(),
        error: (Object error, _) => EmptyView(
          icon: AppIcons.error_outline,
          message: mailFailureMessage(l10n, error),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(mailMessageProvider(messageRef)),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.mailRetry),
          ),
        ),
        data: (MailMessageDetail detail) => _MessageBody(
          detail: detail,
          locale: locale,
          messageRef: messageRef,
        ),
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.detail,
    required this.locale,
    required this.messageRef,
  });

  final MailMessageDetail detail;
  final String locale;
  final MailMessageRef messageRef;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final String subject = detail.subject.trim().isEmpty
        ? l10n.mailNoSubject
        : detail.subject;
    final String sender = detail.from.display.trim().isEmpty
        ? l10n.mailUnknownSender
        : detail.from.display;

    return ListView(
      padding: EdgeInsets.all(context.metrics.screenPadding),
      children: <Widget>[
        Text(subject, style: text.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Text(
          sender,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (detail.from.name != null &&
            detail.from.name!.trim().isNotEmpty &&
            detail.from.email.trim().isNotEmpty)
          Text(detail.from.email, style: text.bodySmall),
        if (detail.date != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppDateFormats.dateTime(detail.date!, locale),
            style: text.bodySmall,
          ),
        ],
        const Divider(height: AppSpacing.xl),
        LinkifiedText(detail.body, style: text.bodyLarge),
        if (detail.hasAttachments) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Semantics(
            header: true,
            child: Text(l10n.mailAttachmentsTitle, style: text.titleMedium),
          ),
          const SizedBox(height: AppSpacing.sm),
          _AttachmentList(
            messageRef: messageRef,
            attachments: detail.attachments,
          ),
        ],
      ],
    );
  }
}

class _AttachmentList extends ConsumerStatefulWidget {
  const _AttachmentList({required this.messageRef, required this.attachments});

  final MailMessageRef messageRef;
  final List<MailAttachment> attachments;

  @override
  ConsumerState<_AttachmentList> createState() => _AttachmentListState();
}

class _AttachmentListState extends ConsumerState<_AttachmentList> {
  late List<MailAttachment> _attachments = widget.attachments;
  Future<MailMessageDetail>? _activeDownload;

  @override
  void didUpdateWidget(_AttachmentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachments != widget.attachments) {
      _attachments = widget.attachments;
    }
  }

  Future<MailAttachment> _download(int index) async {
    final Future<MailMessageDetail> request = _activeDownload ??= ref
        .read(mailInboxControllerProvider.notifier)
        .downloadAttachments(widget.messageRef);
    try {
      final MailMessageDetail detail = await request;
      if (index >= detail.attachments.length) {
        throw const MailFailure(MailFailureKind.protocol);
      }
      if (mounted) setState(() => _attachments = detail.attachments);
      return detail.attachments[index];
    } finally {
      if (identical(_activeDownload, request)) _activeDownload = null;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (final (int index, MailAttachment attachment) in _attachments.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: MailAttachmentView(
            key: ValueKey<String>(
              '${widget.messageRef.mailboxPath}/${widget.messageRef.id}/$index',
            ),
            attachment: attachment,
            onDownload: () => _download(index),
          ),
        ),
    ],
  );
}
