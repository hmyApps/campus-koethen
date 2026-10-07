// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/mail_account_controller.dart';
import '../application/mail_folders.dart';
import '../application/mail_inbox_controller.dart';
import '../application/mail_providers.dart';
import '../application/mail_sync_controller.dart';
import '../domain/mail_folder.dart';
import '../domain/mail_message.dart';
import 'mail_error_messages.dart';
import 'mail_folder_labels.dart';
import 'mail_folder_picker.dart';
import 'mail_header_tile.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// Shows the newest headers of the selected mailbox. The INBOX comes from the
/// offline cache and is kept fresh by the background sync; a manual sync button
/// and pull-to-refresh are also available.
class MailInboxScreen extends ConsumerWidget {
  const MailInboxScreen({super.key});

  Future<void> _confirmRemoveAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.mailAccountRemoveConfirmTitle),
        content: Text(l10n.mailAccountRemoveConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.mailCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.mailAccountRemoveConfirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      try {
        await ref.read(mailAccountControllerProvider.notifier).signOut();
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text(mailFailureMessage(l10n, error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final AsyncValue<List<MailMessageHeader>> inbox = ref.watch(
      mailInboxControllerProvider,
    );
    final MailFolder folder = ref.watch(selectedMailboxProvider);
    final String? email = ref
        .watch(mailAccountControllerProvider)
        .value
        ?.emailAddress;
    // Shows sync progress; the periodic/app-start scheduling itself lives in the
    // app shell.
    final MailSyncStatus sync = ref.watch(mailSyncControllerProvider);
    final MailLiveSyncStatus live = ref.watch(mailLiveSyncControllerProvider);
    final MailPaginationStatus pagination = ref.watch(mailPaginationProvider);
    final bool cacheDegraded = ref.watch(mailCacheDegradedProvider);

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: folderLabel(l10n, folder),
      singleLineTitle: true,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.push(AppRoutes.mailSearch),
          tooltip: l10n.mailSearchTooltip,
          icon: const Icon(AppIcons.search),
        ),
        IconButton(
          onPressed: () => showMailFolderPicker(context),
          tooltip: l10n.mailFoldersTooltip,
          icon: const Icon(AppIcons.folder_outlined),
        ),
        PopupMenuButton<String>(
          icon: sync.isSyncing
              ? const SizedBox(
                  height: AppSizes.icon,
                  width: AppSizes.icon,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xs),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
          onSelected: (String value) {
            if (value == 'sync') {
              ref.read(mailInboxControllerProvider.notifier).refresh();
            }
            if (value == 'remove') _confirmRemoveAccount(context, ref);
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'sync',
              enabled: !sync.isSyncing,
              child: Text(l10n.mailSync),
            ),
            PopupMenuItem<String>(
              value: 'remove',
              child: Text(l10n.mailAccountRemove),
            ),
          ],
        ),
      ],
      // Which mailbox this is. Set in the data face and left in its own case —
      // an address is a string that has to be read exactly, not a label.
      controls: email == null
          ? null
          : Padding(
              padding: EdgeInsets.fromLTRB(
                context.metrics.screenPadding,
                AppSpacing.sm,
                context.metrics.screenPadding,
                0,
              ),
              child: Text(
                l10n.mailSignedInAs(email),
                style: context.type.dataSmall,
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.mailCompose),
        tooltip: l10n.mailComposeTooltip,
        child: const Icon(AppIcons.edit_outlined),
      ),
      body: inbox.when(
        loading: () => const LoadingView(),
        error: (Object error, _) => EmptyView(
          icon: AppIcons.error_outline,
          message: mailFailureMessage(l10n, error),
          action: FilledButton.icon(
            onPressed: () =>
                ref.read(mailInboxControllerProvider.notifier).refresh(),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.mailRetry),
          ),
        ),
        data: (List<MailMessageHeader> headers) {
          // The INBOX is served from the cache, so a failed sync never reaches
          // the AsyncValue above — it only lands in `sync.error`. Left
          // unrendered, a refresh in flight mode ended in silence and an empty
          // cache read as an empty mailbox.
          final bool syncFailed = folder.isInbox && sync.error != null;
          final bool showPagination =
              headers.length >= kInboxLimit || pagination.hasAttempted;

          if (headers.isEmpty) {
            // First run: the cache is empty while the initial sync is still
            // fetching. Show progress rather than a misleading "no messages".
            if (folder.isInbox && sync.isSyncing) {
              return const LoadingView();
            }
            if (syncFailed) {
              // Nothing cached *and* the sync failed: this is an error, not an
              // empty mailbox, and saying otherwise is the more damaging lie.
              return EmptyView(
                icon: AppIcons.error_outline,
                title: l10n.mailSyncFailedTitle,
                message: mailFailureMessage(l10n, sync.error),
                action: FilledButton.icon(
                  onPressed: () =>
                      ref.read(mailInboxControllerProvider.notifier).refresh(),
                  icon: const Icon(AppIcons.refresh),
                  label: Text(l10n.mailRetry),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(mailInboxControllerProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  const SizedBox(height: AppSpacing.xxxl),
                  EmptyView(
                    title: folderLabel(l10n, folder),
                    message: l10n.mailInboxEmpty,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(mailInboxControllerProvider.notifier).refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              // One extra leading row for the sync banner and the freshness
              // line, so both scroll with the list instead of stealing height
              // from it.
              itemCount: headers.length + 1 + (showPagination ? 1 : 0),
              separatorBuilder: (_, int index) => index == 0
                  ? const SizedBox.shrink()
                  : const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return _InboxStatusHeader(
                    showError: syncFailed,
                    error: sync.error,
                    cacheDegraded: cacheDegraded,
                    lastSyncedAt: folder.isInbox ? sync.lastSyncedAt : null,
                    liveConnection: folder.isInbox
                        ? live.connection
                        : MailLiveConnection.stopped,
                    onRetry: () => ref
                        .read(mailInboxControllerProvider.notifier)
                        .refresh(),
                  );
                }
                if (showPagination && index == headers.length + 1) {
                  return _OlderMessagesFooter(
                    status: pagination,
                    onLoad: () => ref
                        .read(mailInboxControllerProvider.notifier)
                        .loadOlder(),
                  );
                }
                final MailMessageHeader header = headers[index - 1];
                return MailHeaderTile(header: header, locale: locale);
              },
            ),
          );
        },
      ),
    );
  }
}

class _OlderMessagesFooter extends StatelessWidget {
  const _OlderMessagesFooter({required this.status, required this.onLoad});

  final MailPaginationStatus status;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.metrics.screenPadding,
        AppSpacing.lg,
        context.metrics.screenPadding,
        AppSpacing.xxxl,
      ),
      child: Center(
        child: status.isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    width: AppSizes.icon,
                    height: AppSizes.icon,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(l10n.mailLoadingOlder),
                ],
              )
            : status.error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    mailFailureMessage(l10n, status.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: onLoad,
                    icon: const Icon(AppIcons.refresh),
                    label: Text(l10n.mailRetry),
                  ),
                ],
              )
            : status.hasMore
            ? OutlinedButton.icon(
                onPressed: onLoad,
                icon: const Icon(AppIcons.download_outlined),
                label: Text(l10n.mailLoadOlder),
              )
            : Text(
                l10n.mailNoOlderMessages,
                style: context.type.dataSmall,
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

/// The strip above the message list: what went wrong, and how old this is.
///
/// Both lines answer the question a cached mailbox cannot answer on its own —
/// "is this everything?". Without them a stale inbox looks exactly like a
/// current one, which is how a failing sync can go unnoticed for days.
class _InboxStatusHeader extends StatelessWidget {
  const _InboxStatusHeader({
    required this.showError,
    required this.error,
    required this.cacheDegraded,
    required this.lastSyncedAt,
    required this.liveConnection,
    required this.onRetry,
  });

  final bool showError;
  final Object? error;
  final bool cacheDegraded;
  final DateTime? lastSyncedAt;
  final MailLiveConnection liveConnection;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    if (!showError &&
        !cacheDegraded &&
        lastSyncedAt == null &&
        liveConnection == MailLiveConnection.stopped) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.metrics.screenPadding,
        AppSpacing.sm,
        context.metrics.screenPadding,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showError) ...<Widget>[
            StatusBanner(
              title: l10n.mailSyncFailedTitle,
              message: mailFailureMessage(l10n, error),
              tone: StatusTone.warning,
              action: TextButton(
                onPressed: onRetry,
                child: Text(l10n.mailRetry),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (cacheDegraded) ...<Widget>[
            StatusBanner(
              title: l10n.mailCacheDegradedTitle,
              message: l10n.mailCacheDegradedBody,
              tone: StatusTone.info,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (lastSyncedAt != null)
            Text(
              l10n.mailLastSyncedAt(
                AppDateFormats.dateTime(lastSyncedAt!, locale),
              ),
              style: context.type.dataSmall,
            ),
          if (liveConnection != MailLiveConnection.stopped)
            Semantics(
              liveRegion: true,
              child: Text(switch (liveConnection) {
                MailLiveConnection.stopped => '',
                MailLiveConnection.connecting => l10n.mailLiveConnecting,
                MailLiveConnection.idle => l10n.mailLiveConnected,
                MailLiveConnection.polling => l10n.mailLivePolling,
                MailLiveConnection.retrying => l10n.mailLiveRetrying,
              }, style: context.type.dataSmall),
            ),
        ],
      ),
    );
  }
}
