// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/sheet_body.dart';
import '../../../l10n/l10n.dart';
import '../application/chat_providers.dart';
import '../domain/matrix_failure.dart';
import '../domain/matrix_gateway.dart';
import 'chat_messages.dart';

/// Asks whom to chat with and creates the conversation. Resolves to the new
/// room's ID, or `null` when closed without creating one.
Future<String?> showNewConversationSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => const _NewConversationSheet(),
    );

enum _Kind { direct, group }

class _NewConversationSheet extends ConsumerStatefulWidget {
  const _NewConversationSheet();

  @override
  ConsumerState<_NewConversationSheet> createState() =>
      _NewConversationSheetState();
}

class _NewConversationSheetState extends ConsumerState<_NewConversationSheet> {
  final TextEditingController _peer = TextEditingController();
  final TextEditingController _groupName = TextEditingController();
  final TextEditingController _invitees = TextEditingController();
  _Kind _kind = _Kind.direct;
  bool _busy = false;
  MatrixFailure? _error;

  @override
  void dispose() {
    _peer.dispose();
    _groupName.dispose();
    _invitees.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final MatrixGateway gateway = ref.read(matrixGatewayProvider);
    try {
      final String roomId = switch (_kind) {
        _Kind.direct => await gateway.startDirectChat(_peer.text),
        _Kind.group => await gateway.createGroupChat(
          name: _groupName.text,
          invite: _invitees.text
              .split(RegExp(r'[,;\s]+'))
              .where((String id) => id.isNotEmpty)
              .toList(growable: false),
        ),
      };
      if (mounted) Navigator.of(context).pop(roomId);
    } on MatrixFailure catch (failure) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final MatrixFailure? error = _error;
    return SheetBody(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l10n.chatNewChat, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<_Kind>(
                segments: <ButtonSegment<_Kind>>[
                  ButtonSegment<_Kind>(
                    value: _Kind.direct,
                    icon: const Icon(AppIcons.person_outline),
                    label: Text(l10n.chatNewDirect),
                  ),
                  ButtonSegment<_Kind>(
                    value: _Kind.group,
                    icon: const Icon(AppIcons.group_outlined),
                    label: Text(l10n.chatNewGroup),
                  ),
                ],
                selected: <_Kind>{_kind},
                onSelectionChanged: _busy
                    ? null
                    : (Set<_Kind> kinds) => setState(() {
                        _kind = kinds.single;
                        _error = null;
                      }),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_kind == _Kind.direct)
                TextField(
                  controller: _peer,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                  decoration: InputDecoration(
                    labelText: l10n.chatPeerLabel,
                    hintText: l10n.chatPeerHint,
                  ),
                )
              else ...<Widget>[
                TextField(
                  controller: _groupName,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.chatGroupNameLabel,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _invitees,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.chatGroupInviteesLabel,
                    hintText: l10n.chatPeerHint,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Icon(
                    AppIcons.lock_outline,
                    size: AppSizes.icon,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.chatNewChatEncrypted,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
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
              FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: AppSizes.icon,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.chat_bubble_outline),
                label: Text(
                  _kind == _Kind.direct
                      ? l10n.chatStartAction
                      : l10n.chatCreateGroupAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
