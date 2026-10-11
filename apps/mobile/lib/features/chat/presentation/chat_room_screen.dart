// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/chat_providers.dart';
import '../domain/chat_models.dart';
import '../domain/matrix_failure.dart';
import '../domain/matrix_gateway.dart';
import 'chat_messages.dart';

/// One conversation: its messages, newest at the bottom, and the composer.
///
/// [roomId] arrives as route `extra`, never in the location. Without it (a
/// restored route, say) the screen says the conversation is unavailable.
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({required this.roomId, super.key});

  final String? roomId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final TextEditingController _composer = TextEditingController();
  late final MatrixGateway _gateway;
  ChatRoomTimeline? _timeline;
  StreamSubscription<void>? _changes;
  Object? _openError;
  MatrixFailure? _sendError;
  bool _sending = false;
  bool _loadingOlder = false;

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(matrixGatewayProvider);
    unawaited(_open());
  }

  Future<void> _open() async {
    final String? roomId = widget.roomId;
    if (roomId == null) {
      setState(
        () =>
            _openError = const MatrixFailure(MatrixFailureKind.roomUnavailable),
      );
      return;
    }
    try {
      final ChatRoomTimeline timeline = await _gateway.openTimeline(roomId);
      if (!mounted) {
        timeline.close();
        return;
      }
      _changes = timeline.changes.listen((_) {
        if (!mounted) return;
        setState(() {});
        unawaited(_markRead());
      });
      setState(() => _timeline = timeline);
      unawaited(_markRead());
    } catch (error) {
      if (mounted) setState(() => _openError = error);
    }
  }

  Future<void> _markRead() async {
    try {
      await _timeline?.markRead();
    } catch (_) {
      // A read marker is a courtesy; the next one catches up.
    }
  }

  Future<void> _loadOlder() async {
    final ChatRoomTimeline? timeline = _timeline;
    if (timeline == null || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      await timeline.loadMore();
    } catch (_) {
      // Stays offered; the next tap tries again.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final String? roomId = widget.roomId;
    final String text = _composer.text;
    if (roomId == null || text.trim().isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    _composer.clear();
    try {
      await _gateway.sendText(roomId, text);
    } on MatrixFailure catch (failure) {
      if (!mounted) return;
      // Hand the text back for an explicit retry.
      if (_composer.text.isEmpty) _composer.text = text;
      setState(() => _sendError = failure);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _timeline?.close();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String? roomId = widget.roomId;
    final ChatRoomSummary? room = ref.watch(
      chatRoomsProvider.select(
        (AsyncValue<List<ChatRoomSummary>> rooms) => rooms.value
            ?.where((ChatRoomSummary r) => r.id == roomId)
            .firstOrNull,
      ),
    );
    final ChatRoomTimeline? timeline = _timeline;
    final Object? openError = _openError;

    final Widget body;
    if (openError != null) {
      body = EmptyView(
        icon: AppIcons.error_outline,
        message: chatFailureMessage(l10n, openError),
      );
    } else if (timeline == null) {
      body = const LoadingView();
    } else {
      body = Column(
        children: <Widget>[
          if (room != null) _EncryptionNotice(encrypted: room.isEncrypted),
          Expanded(child: _messageList(context, timeline, room)),
          if (_sendError case final MatrixFailure failure)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  chatFailureMessage(l10n, failure),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          _composerRow(context),
        ],
      );
    }

    return ScreenScaffold(
      title: room?.title ?? l10n.chatUntitledRoom,
      showBack: true,
      singleLineTitle: true,
      body: body,
    );
  }

  Widget _messageList(
    BuildContext context,
    ChatRoomTimeline timeline,
    ChatRoomSummary? room,
  ) {
    final AppLocalizations l10n = context.l10n;
    final List<ChatMessage> messages = timeline.messages;
    final bool canLoadMore = timeline.canLoadMore;
    if (messages.isEmpty && !canLoadMore) {
      return EmptyView(
        icon: AppIcons.chat_bubble_outline,
        message: l10n.chatTimelineEmpty,
      );
    }
    final bool showSenders = !(room?.isDirect ?? false);
    return ListView.builder(
      // Newest first in the data, newest at the bottom on screen.
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: messages.length + (canLoadMore ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index == messages.length) {
          return Center(
            child: TextButton.icon(
              onPressed: _loadingOlder ? null : _loadOlder,
              icon: _loadingOlder
                  ? const SizedBox.square(
                      dimension: AppSizes.icon,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.keyboard_arrow_up),
              label: Text(l10n.chatLoadOlder),
            ),
          );
        }
        return _MessageBubble(
          message: messages[index],
          showSender: showSenders,
        );
      },
    );
  }

  Widget _composerRow(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Padding(
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
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: l10n.chatComposerHint),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              tooltip: l10n.chatSend,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: AppSizes.icon,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.send_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether the room is end-to-end encrypted — said in words and with an
/// icon, never by colour alone.
class _EncryptionNotice extends StatelessWidget {
  const _EncryptionNotice({required this.encrypted});

  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            encrypted ? AppIcons.lock_outline : AppIcons.lock_open_outline,
            size: AppSizes.icon,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              encrypted ? l10n.chatEncrypted : l10n.chatNotEncrypted,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.showSender});

  final ChatMessage message;
  final bool showSender;

  static const double _maxWidth = 320;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool mine = message.isMine;
    final bool hasText =
        message.kind == ChatMessageKind.text ||
        message.kind == ChatMessageKind.notice ||
        message.kind == ChatMessageKind.emote;
    final Color foreground = mine
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    final String? status = switch (message.status) {
      ChatMessageStatus.sending => l10n.chatMessageSending,
      ChatMessageStatus.failed => l10n.chatMessageFailed,
      ChatMessageStatus.sent => null,
    };

    return Align(
      alignment: mine
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
          color: mine
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showSender && !mine && message.senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text(
                  message.senderName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              chatMessageText(l10n, message),
              style: TextStyle(
                color: foreground,
                fontStyle: hasText && message.kind != ChatMessageKind.emote
                    ? null
                    : FontStyle.italic,
              ),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      message.status == ChatMessageStatus.failed
                          ? AppIcons.error_outline
                          : AppIcons.schedule_outlined,
                      size: AppSpacing.lg,
                      color: message.status == ChatMessageStatus.failed
                          ? colors.error
                          : foreground,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      status,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: message.status == ChatMessageStatus.failed
                            ? colors.error
                            : foreground,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
