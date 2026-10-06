// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/documents/app_document.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../l10n/l10n.dart';
import '../application/document_wallet_controller.dart';
import '../domain/wallet_document.dart';

class WalletSaveAction extends ConsumerStatefulWidget {
  const WalletSaveAction({
    required this.kind,
    required this.document,
    super.key,
  });

  final WalletDocumentKind kind;
  final AppDocument document;

  @override
  ConsumerState<WalletSaveAction> createState() => _WalletSaveActionState();
}

class _WalletSaveActionState extends ConsumerState<WalletSaveAction> {
  bool _busy = false;
  bool _saved = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(documentWalletControllerProvider.notifier)
          .save(kind: widget.kind, document: widget.document);
      if (!mounted) return;
      setState(() => _saved = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.documentWalletSaved)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.documentWalletSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: _busy || _saved ? null : _save,
    tooltip: _saved
        ? context.l10n.documentWalletSaved
        : context.l10n.documentWalletSaveAction,
    icon: _busy
        ? const SizedBox.square(
            dimension: AppSizes.icon,
            child: CircularProgressIndicator(strokeWidth: AppSizes.rule),
          )
        : Icon(_saved ? AppIcons.check : AppIcons.download_outlined),
  );
}
