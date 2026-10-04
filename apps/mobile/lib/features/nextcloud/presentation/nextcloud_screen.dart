// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/documents/app_document.dart';
import '../../../core/documents/document_viewer_screen.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/nextcloud_account_controller.dart';
import '../application/nextcloud_providers.dart';
import '../domain/nextcloud_account.dart';
import '../domain/nextcloud_entry.dart';
import 'nextcloud_messages.dart';

class NextcloudScreen extends ConsumerStatefulWidget {
  const NextcloudScreen({super.key});

  @override
  ConsumerState<NextcloudScreen> createState() => _NextcloudScreenState();
}

class _NextcloudScreenState extends ConsumerState<NextcloudScreen> {
  String _path = '/';
  String? _downloadingPath;

  Future<void> _refresh() async {
    ref.invalidate(nextcloudFolderProvider(_path));
    try {
      await ref.read(nextcloudFolderProvider(_path).future);
    } catch (_) {
      // The provider renders the classified error in the body.
    }
  }

  void _openFolder(NextcloudEntry entry) {
    setState(() => _path = entry.path);
  }

  void _openPath(String path) {
    if (path == _path) return;
    setState(() => _path = path);
  }

  Future<void> _openFile(NextcloudEntry entry) async {
    if (_downloadingPath != null) return;
    setState(() => _downloadingPath = entry.path);
    try {
      final AppDocument document = await ref
          .read(nextcloudFileServiceProvider)
          .download(entry);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => DocumentViewerScreen(document: document),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextcloudFailureMessage(context.l10n, error))),
      );
    } finally {
      if (mounted) setState(() => _downloadingPath = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<NextcloudAccount?> account = ref.watch(
      nextcloudAccountControllerProvider,
    );
    final bool loginPending = ref
        .read(nextcloudAccountControllerProvider.notifier)
        .loginPending;

    if (account.isLoading) {
      return ScreenScaffold(
        title: l10n.nextcloudTitle,
        body: loginPending
            ? _LoginPending(
                onCancel: () => ref
                    .read(nextcloudAccountControllerProvider.notifier)
                    .cancelPendingLogin(),
              )
            : const LoadingView(),
      );
    }

    final NextcloudAccount? value = account.value;
    if (value == null) {
      return ScreenScaffold(
        title: l10n.nextcloudTitle,
        body: _SignedOut(
          error: account.error,
          onConnect: () =>
              ref.read(nextcloudAccountControllerProvider.notifier).connect(),
        ),
      );
    }

    final AsyncValue<List<NextcloudEntry>> folder = ref.watch(
      nextcloudFolderProvider(_path),
    );
    return ScreenScaffold(
      title: l10n.nextcloudTitle,
      actions: <Widget>[
        IconButton(
          onPressed: folder.isLoading ? null : _refresh,
          tooltip: l10n.nextcloudRefresh,
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTouchTarget,
            minHeight: AppSizes.minTouchTarget,
          ),
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              l10n.nextcloudConnectedAs(value.loginName),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _Breadcrumbs(path: _path, onSelected: _openPath),
        ],
      ),
      body: folder.when(
        loading: () => const LoadingView(),
        error: (Object error, _) => EmptyView(
          icon: AppIcons.cloud_off_outlined,
          message: nextcloudFailureMessage(l10n, error),
          action: FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.nextcloudRetry),
          ),
        ),
        data: (List<NextcloudEntry> entries) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              if (_path != '/')
                ListTile(
                  leading: const Icon(AppIcons.arrow_back),
                  title: Text(l10n.nextcloudGoUp),
                  minTileHeight: AppSizes.minTouchTarget,
                  onTap: () => _openPath(_parentPath(_path)),
                ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.nextcloudFolderEmpty,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              for (final NextcloudEntry entry in entries)
                _EntryTile(
                  entry: entry,
                  downloading: _downloadingPath == entry.path,
                  disabled: _downloadingPath != null,
                  onTap: entry.isDirectory
                      ? () => _openFolder(entry)
                      : () => _openFile(entry),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.error, required this.onConnect});

  final Object? error;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return EmptyView(
      icon: error == null
          ? AppIcons.cloud_outlined
          : AppIcons.cloud_off_outlined,
      title: error == null ? l10n.nextcloudTitle : null,
      message: error == null
          ? l10n.nextcloudSignedOutBody
          : nextcloudFailureMessage(l10n, error!),
      action: FilledButton.icon(
        onPressed: onConnect,
        icon: const Icon(AppIcons.login),
        label: Text(
          error == null ? l10n.nextcloudConnect : l10n.nextcloudRetry,
        ),
      ),
    );
  }
}

class _LoginPending extends StatelessWidget {
  const _LoginPending({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Semantics(
      liveRegion: true,
      label: l10n.nextcloudConnecting,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 96,
                child: LinearProgressIndicator(minHeight: AppSizes.beam),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.nextcloudConnecting, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(AppIcons.cancel_outlined),
                label: Text(l10n.nextcloudCancelLogin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.path, required this.onSelected});

  final String path;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<String> segments = path == '/'
        ? const <String>[]
        : path.substring(1).split('/');
    final List<Widget> children = <Widget>[
      TextButton(
        onPressed: path == '/' ? null : () => onSelected('/'),
        child: Text(context.l10n.nextcloudFilesRoot),
      ),
    ];
    for (var index = 0; index < segments.length; index++) {
      final String segment = segments[index];
      final String target = '/${segments.take(index + 1).join('/')}';
      children
        ..add(const Icon(AppIcons.chevron_right, size: AppSizes.iconSmall))
        ..add(
          TextButton(
            onPressed: target == path ? null : () => onSelected(target),
            child: Text(segment),
          ),
        );
    }
    return SizedBox(
      height: AppSizes.minTouchTarget,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(children: children),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.downloading,
    required this.disabled,
    required this.onTap,
  });

  final NextcloudEntry entry;
  final bool downloading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String actionLabel = entry.isDirectory
        ? l10n.nextcloudOpenFolder(entry.name)
        : l10n.nextcloudDownloadFile(entry.name);
    final String semanticsLabel = downloading
        ? '${entry.name}: ${l10n.nextcloudDownloading}'
        : actionLabel;
    final List<String> details = <String>[
      if (entry.sizeBytes case final int bytes)
        humanFileSize(
          bytes,
          locale: Localizations.localeOf(context).toLanguageTag(),
        ),
      if (entry.modifiedAt case final DateTime modified)
        DateFormat.yMd(
          Localizations.localeOf(context).toLanguageTag(),
        ).add_Hm().format(modified.toLocal()),
    ];
    return Semantics(
      button: !disabled,
      enabled: !disabled,
      liveRegion: downloading,
      label: semanticsLabel,
      child: ListTile(
        enabled: !disabled,
        minTileHeight: AppSizes.minTouchTarget,
        leading: Icon(
          entry.isDirectory
              ? AppIcons.folder_outlined
              : AppIcons.insert_drive_file_outlined,
        ),
        title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: details.isEmpty ? null : Text(details.join(' · ')),
        trailing: downloading
            ? const SizedBox.square(
                dimension: AppSizes.icon,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                entry.isDirectory
                    ? AppIcons.chevron_right
                    : AppIcons.download_outlined,
              ),
        onTap: disabled ? null : onTap,
      ),
    );
  }
}

String _parentPath(String path) {
  final List<String> segments = path.substring(1).split('/');
  if (segments.length <= 1) return '/';
  return '/${segments.take(segments.length - 1).join('/')}';
}
