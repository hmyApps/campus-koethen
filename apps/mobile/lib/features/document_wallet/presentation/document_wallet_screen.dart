// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_modules.dart';
import '../../../core/documents/document_viewer_screen.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/document_wallet_controller.dart';
import '../domain/wallet_document.dart';

class DocumentWalletScreen extends ConsumerWidget {
  const DocumentWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<WalletDocument>> wallet = ref.watch(
      documentWalletControllerProvider,
    );
    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.documentWalletTitle,
      body: wallet.when(
        loading: () => const LoadingView(),
        error: (_, _) => ErrorView(
          failure: const DocumentWalletFailure(
            DocumentWalletFailureKind.storageUnavailable,
          ),
          onRetry: () => ref.invalidate(documentWalletControllerProvider),
        ),
        data: (List<WalletDocument> documents) => documents.isEmpty
            ? EmptyView(
                icon: AppIcons.folder_outlined,
                title: l10n.documentWalletEmptyTitle,
                message: l10n.documentWalletEmptyMessage,
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: <Widget>[
                  StatusBanner(
                    title: l10n.documentWalletOfflineTitle,
                    message: l10n.documentWalletOfflineMessage,
                    icon: AppIcons.lock_outline,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final WalletDocument document in documents)
                    _WalletDocumentTile(document: document),
                ],
              ),
      ),
    );
  }
}

class _WalletDocumentTile extends ConsumerWidget {
  const _WalletDocumentTile({required this.document});

  final WalletDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final String title = switch (document.kind) {
      WalletDocumentKind.enrollmentCertificate =>
        l10n.documentWalletEnrollmentCertificate,
      WalletDocumentKind.transcript => l10n.documentWalletTranscript,
    };
    return Card(
      child: ListTile(
        minVerticalPadding: AppSpacing.md,
        leading: const Icon(AppIcons.description_outlined),
        title: Text(title),
        subtitle: Text(
          '${document.filename}\n'
          '${l10n.documentWalletSavedAt(AppDateFormats.dateTime(document.savedAt, locale))}',
        ),
        isThreeLine: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) =>
                DocumentViewerScreen(document: document.toAppDocument()),
          ),
        ),
        trailing: IconButton(
          tooltip: l10n.documentWalletDelete,
          icon: const Icon(AppIcons.delete_outline),
          onPressed: () async {
            final bool confirmed =
                await showDialog<bool>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(l10n.documentWalletDeleteTitle),
                    content: Text(l10n.documentWalletDeleteMessage(title)),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l10n.documentWalletCancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(l10n.documentWalletDelete),
                      ),
                    ],
                  ),
                ) ??
                false;
            if (!confirmed) return;
            try {
              await ref
                  .read(documentWalletControllerProvider.notifier)
                  .delete(document.kind);
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.documentWalletDeleteFailed)),
              );
            }
          },
        ),
      ),
    );
  }
}
