// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/hsa_ki_account_controller.dart';
import '../application/hsa_ki_chat_controller.dart';
import '../domain/hsa_ki_account.dart';
import '../domain/hsa_ki_chat.dart';
import '../domain/hsa_ki_failure.dart';
import 'hsa_ki_connect_flow.dart';
import 'hsa_ki_messages.dart';

/// HSA-GPT's own module screen: a pure gate, same shape as `GradesScreen` —
/// not connected shows the dedicated consent flow, connected shows the chat.
class HsaKiChatScreen extends ConsumerWidget {
  const HsaKiChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<HsaKiAccount?> account = ref.watch(
      hsaKiAccountControllerProvider,
    );

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.hsaKiTitle,
      body: account.when(
        loading: () => const LoadingView(),
        error: (Object error, _) => EmptyView(
          icon: AppIcons.error_outline,
          message: hsaKiFailureMessage(l10n, error),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(hsaKiAccountControllerProvider),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.actionRetry),
          ),
        ),
        data: (HsaKiAccount? current) => current == null
            ? const _HsaKiConnectPrompt()
            : const _HsaKiChatContent(),
      ),
    );
  }
}

class _HsaKiConnectPrompt extends ConsumerStatefulWidget {
  const _HsaKiConnectPrompt();

  @override
  ConsumerState<_HsaKiConnectPrompt> createState() =>
      _HsaKiConnectPromptState();
}

class _HsaKiConnectPromptState extends ConsumerState<_HsaKiConnectPrompt> {
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await connectHsaKiWithOnboarding(context, ref);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = hsaKiFailureMessage(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return EmptyView(
      icon: AppIcons.message_2,
      message: _error ?? l10n.hsaKiSignedOutBody,
      action: FilledButton.icon(
        onPressed: _busy ? null : _connect,
        icon: _busy
            ? const SizedBox.square(
                dimension: AppSizes.icon,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(AppIcons.add_circle_outline),
        label: Text(l10n.universityAccountConnectService(l10n.hsaKiTitle)),
      ),
    );
  }
}

class _HsaKiChatContent extends ConsumerStatefulWidget {
  const _HsaKiChatContent();

  @override
  ConsumerState<_HsaKiChatContent> createState() => _HsaKiChatContentState();
}

class _HsaKiChatContentState extends ConsumerState<_HsaKiChatContent> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final String text = _composer.text;
    if (text.trim().isEmpty) return;
    _composer.clear();
    await ref.read(hsaKiChatControllerProvider.notifier).send(text);
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AsyncValue<HsaKiChatState> chat = ref.watch(
      hsaKiChatControllerProvider,
    );
    final HsaKiChatState? state = chat.value;

    ref.listen<AsyncValue<HsaKiChatState>>(hsaKiChatControllerProvider, (
      AsyncValue<HsaKiChatState>? previous,
      AsyncValue<HsaKiChatState> next,
    ) {
      final int previousLength = previous?.value?.messages.length ?? 0;
      final int nextLength = next.value?.messages.length ?? 0;
      if (nextLength > previousLength) _scrollToEnd();
    });

    final bool sending = state?.isSending ?? false;

    return Column(
      children: <Widget>[
        if (state != null && state.models.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: DropdownButton<String>(
                value: state.selectedModelId,
                underline: const SizedBox.shrink(),
                items: state.models
                    .map(
                      (HsaKiModel model) => DropdownMenuItem<String>(
                        value: model.modelId,
                        child: Text(model.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (String? modelId) {
                  if (modelId != null) {
                    ref
                        .read(hsaKiChatControllerProvider.notifier)
                        .selectModel(modelId);
                  }
                },
              ),
            ),
          ),
        Expanded(
          child: state == null || state.messages.isEmpty
              ? EmptyView(icon: AppIcons.message_2, message: l10n.hsaKiEmptyState)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: state.messages.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _MessageBubble(message: state.messages[index]),
                ),
        ),
        if (state?.lastError case final HsaKiFailureKind kind)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                hsaKiFailureMessage(l10n, HsaKiFailure(kind)),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !sending,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(hintText: l10n.hsaKiComposerHint),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: sending ? null : _send,
                tooltip: l10n.hsaKiSend,
                icon: sending
                    ? const SizedBox.square(
                        dimension: AppSizes.icon,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.send_outlined),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text(
            l10n.hsaKiDisclaimerFooter,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final HsaKiMessage message;

  static const double _maxWidth = 320;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == HsaKiMessageRole.user;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.md),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
