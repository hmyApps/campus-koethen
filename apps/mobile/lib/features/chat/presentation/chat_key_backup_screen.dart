// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/chat_providers.dart';
import '../domain/chat_key_backup.dart';
import '../domain/matrix_failure.dart';
import 'chat_messages.dart';

/// Sets up, unlocks or resets the account's key backup.
///
/// A newly created recovery key is shown exactly once, here, and the screen
/// cannot be left until its safekeeping is confirmed. The app never stores
/// it. The Matrix password is asked for only when the server wants a step
/// confirmed, used for that one request and then cleared.
class ChatKeyBackupScreen extends ConsumerStatefulWidget {
  const ChatKeyBackupScreen({super.key});

  @override
  ConsumerState<ChatKeyBackupScreen> createState() =>
      _ChatKeyBackupScreenState();
}

class _ChatKeyBackupScreenState extends ConsumerState<ChatKeyBackupScreen> {
  final TextEditingController _recoveryKeyInput = TextEditingController();
  final TextEditingController _password = TextEditingController();
  String? _shownRecoveryKey;
  bool _savedConfirmed = false;
  bool _busy = false;
  bool _askPassword = false;
  bool _resetting = false;
  MatrixFailure? _error;

  @override
  void dispose() {
    _recoveryKeyInput.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on MatrixFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure;
        if (failure.kind == MatrixFailureKind.passwordRequired) {
          _askPassword = true;
        }
      });
    } finally {
      // Used for one request at most.
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _typedPassword =>
      _askPassword && _password.text.isNotEmpty ? _password.text : null;

  Future<void> _setUp() => _run(() async {
    final String key = await ref
        .read(chatKeyBackupControllerProvider.notifier)
        .setUp(password: _typedPassword);
    if (mounted) _showOnce(key);
  });

  Future<void> _unlock() => _run(() async {
    await ref
        .read(chatKeyBackupControllerProvider.notifier)
        .unlock(_recoveryKeyInput.text);
    _recoveryKeyInput.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.chatKeyBackupUnlocked)));
  });

  Future<void> _reset() => _run(() async {
    final String? password = _typedPassword;
    if (password == null) {
      throw const MatrixFailure(MatrixFailureKind.passwordRequired);
    }
    final String key = await ref
        .read(chatKeyBackupControllerProvider.notifier)
        .reset(password: password);
    if (mounted) _showOnce(key);
  });

  void _showOnce(String recoveryKey) => setState(() {
    _shownRecoveryKey = recoveryKey;
    _savedConfirmed = false;
    _askPassword = false;
    _resetting = false;
  });

  Future<void> _confirmReset() async {
    final AppLocalizations l10n = context.l10n;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(l10n.chatKeyBackupResetTitle),
            content: Text(l10n.chatKeyBackupResetMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.chatCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.chatKeyBackupResetAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _resetting = true;
      _askPassword = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<ChatKeyBackupState?> backup = ref.watch(
      chatKeyBackupControllerProvider,
    );
    final String? shown = _shownRecoveryKey;

    final Widget body;
    if (shown != null) {
      body = _recoveryKeyView(context, shown);
    } else {
      body = backup.when(
        loading: () => const LoadingView(),
        error: (Object error, _) => EmptyView(
          icon: AppIcons.error_outline,
          message: chatFailureMessage(l10n, error),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(chatKeyBackupControllerProvider),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.actionRetry),
          ),
        ),
        data: (ChatKeyBackupState? state) => switch (state) {
          null || ChatKeyBackupState.unavailable => EmptyView(
            icon: AppIcons.lock_open_outline,
            message: l10n.chatKeyBackupUnavailable,
          ),
          ChatKeyBackupState.ready => EmptyView(
            icon: AppIcons.check_circle_outline,
            message: l10n.chatKeyBackupReady,
          ),
          ChatKeyBackupState.notSetUp => _form(
            context,
            intro: l10n.chatKeyBackupNotSetUpBody,
            action: l10n.chatKeyBackupSetUpAction,
            onAction: _setUp,
          ),
          ChatKeyBackupState.locked =>
            _resetting
                ? _form(
                    context,
                    intro: l10n.chatKeyBackupResetMessage,
                    action: l10n.chatKeyBackupResetAction,
                    onAction: _reset,
                  )
                : _form(
                    context,
                    intro: l10n.chatKeyBackupLockedBody,
                    action: l10n.chatKeyBackupUnlockAction,
                    onAction: _unlock,
                    recoveryKeyInput: true,
                  ),
        },
      );
    }

    return PopScope(
      // A recovery key shown once must not vanish unconfirmed.
      canPop: shown == null || _savedConfirmed,
      child: ScreenScaffold(
        title: l10n.chatKeyBackupTitle,
        showBack: true,
        body: body,
      ),
    );
  }

  Widget _form(
    BuildContext context, {
    required String intro,
    required String action,
    required Future<void> Function() onAction,
    bool recoveryKeyInput = false,
  }) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final MatrixFailure? error = _error;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.lg,
      ),
      children: <Widget>[
        Text(intro, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.lg),
        if (recoveryKeyInput)
          TextField(
            controller: _recoveryKeyInput,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: l10n.chatRecoveryKeyLabel),
          ),
        if (_askPassword) ...<Widget>[
          if (recoveryKeyInput) const SizedBox(height: AppSpacing.md),
          Text(l10n.chatKeyBackupPasswordPrompt),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const <String>[AutofillHints.password],
            decoration: InputDecoration(labelText: l10n.chatPasswordLabel),
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              chatFailureMessage(l10n, error),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _busy ? null : onAction,
          child: _busy
              ? const SizedBox.square(
                  dimension: AppSizes.icon,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(action),
        ),
        if (recoveryKeyInput && !_resetting) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _busy ? null : _confirmReset,
            child: Text(l10n.chatKeyBackupLostKey),
          ),
        ],
      ],
    );
  }

  Widget _recoveryKeyView(BuildContext context, String recoveryKey) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.lg,
      ),
      children: <Widget>[
        Text(l10n.chatRecoveryKeyShownTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.chatRecoveryKeyShownBody, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: SelectableText(
            recoveryKey,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: recoveryKey));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.chatRecoveryKeyCopied)),
              );
            },
            icon: const Icon(AppIcons.content_copy_outlined),
            label: Text(l10n.chatRecoveryKeyCopy),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _savedConfirmed,
          onChanged: (bool? value) =>
              setState(() => _savedConfirmed = value ?? false),
          title: Text(l10n.chatRecoveryKeySavedConfirm),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: _savedConfirmed
              ? () => setState(() => _shownRecoveryKey = null)
              : null,
          child: Text(l10n.chatRecoveryKeyDone),
        ),
      ],
    );
  }
}
