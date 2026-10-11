// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../app/app_routes.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/chat_providers.dart';
import '../domain/chat_models.dart';
import '../domain/matrix_failure.dart';
import '../domain/matrix_homeserver.dart';
import 'chat_messages.dart';
import 'chat_new_conversation_sheet.dart';

/// The chat module: a gate like the other direct services. Not configured in
/// this build, signed out (login), or signed in (rooms).
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final MatrixHomeserver? homeserver = ref.watch(matrixHomeserverProvider);
    final AsyncValue<MatrixAccount?> session = homeserver == null
        ? const AsyncData<MatrixAccount?>(null)
        : ref.watch(chatSessionControllerProvider);
    final MatrixAccount? account = chatAccountOf(session);

    final Widget body;
    if (homeserver == null) {
      body = EmptyView(
        icon: AppIcons.chat_bubble_outline,
        message: l10n.chatNotConfigured,
      );
    } else if (session.isLoading) {
      body = const LoadingView();
    } else if (account != null) {
      body = const _ChatRoomList();
    } else {
      body = _ChatLoginView(homeserver: homeserver, error: session.error);
    }

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.chatTitle,
      actions: account == null
          ? null
          : <Widget>[_ChatAccountButton(account: account)],
      floatingActionButton: account == null || session.isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _newConversation(context),
              icon: const Icon(AppIcons.add),
              label: Text(l10n.chatNewChat),
            ),
      body: body,
    );
  }

  Future<void> _newConversation(BuildContext context) async {
    final String? roomId = await showNewConversationSheet(context);
    if (roomId == null || !context.mounted) return;
    await context.push(AppRoutes.chatRoom, extra: roomId);
  }
}

class _ChatLoginView extends ConsumerStatefulWidget {
  const _ChatLoginView({required this.homeserver, this.error});

  final MatrixHomeserver homeserver;
  final Object? error;

  @override
  ConsumerState<_ChatLoginView> createState() => _ChatLoginViewState();
}

class _ChatLoginViewState extends ConsumerState<_ChatLoginView> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _missingFields = false;
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    final String username = _username.text.trim();
    final String password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _missingFields = true);
      return;
    }
    setState(() {
      _busy = true;
      _missingFields = false;
    });
    try {
      await ref
          .read(chatSessionControllerProvider.notifier)
          .login(username: username, password: password);
    } finally {
      // The password is only needed for this one request.
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    try {
      await ref.read(chatSessionControllerProvider.notifier).logout();
    } catch (_) {
      // The controller keeps the failure as its state; shown above.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final Object? error = widget.error;
    final String? message = _missingFields
        ? l10n.chatLoginMissingFields
        : error == null
        ? null
        : chatFailureMessage(l10n, error);

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.lg,
      ),
      children: <Widget>[
        Text(
          l10n.chatLoginIntro(widget.homeserver.host),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.chatLoginPrivacy, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Icon(
              AppIcons.info_outline,
              size: AppSizes.icon,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.chatLoginTestNotice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        AutofillGroup(
          child: Column(
            children: <Widget>[
              TextField(
                controller: _username,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l10n.chatUsernameLabel),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: l10n.chatPasswordLabel,
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? l10n.chatShowPassword
                        : l10n.chatHidePassword,
                    icon: Icon(
                      _obscure
                          ? AppIcons.visibility_outlined
                          : AppIcons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (message != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  AppIcons.error_outline,
                  size: AppSizes.icon,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _busy ? null : _login,
          icon: _busy
              ? const SizedBox.square(
                  dimension: AppSizes.icon,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(AppIcons.login),
          label: Text(l10n.chatLoginAction),
        ),
        if (chatFailureNeedsReset(error)) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reset,
            icon: const Icon(AppIcons.delete_outline),
            label: Text(l10n.chatResetLocalData),
          ),
        ],
      ],
    );
  }
}

class _ChatRoomList extends ConsumerWidget {
  const _ChatRoomList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<ChatRoomSummary>> rooms = ref.watch(
      chatRoomsProvider,
    );
    return rooms.when(
      loading: () => const LoadingView(),
      error: (Object error, _) => EmptyView(
        icon: AppIcons.error_outline,
        message: chatFailureMessage(l10n, error),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(chatRoomsProvider),
          icon: const Icon(AppIcons.refresh),
          label: Text(l10n.actionRetry),
        ),
      ),
      data: (List<ChatRoomSummary> all) {
        if (all.isEmpty) {
          return EmptyView(
            icon: AppIcons.chat_bubble_outline,
            message: l10n.chatRoomsEmpty,
          );
        }
        final List<ChatRoomSummary> invites = all
            .where((ChatRoomSummary r) => r.isInvite)
            .toList(growable: false);
        final List<ChatRoomSummary> joined = all
            .where((ChatRoomSummary r) => !r.isInvite)
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: <Widget>[
            if (invites.isNotEmpty) ...<Widget>[
              SectionHeader(label: l10n.chatInvitesHeader),
              for (final ChatRoomSummary room in invites)
                _ChatInviteTile(room: room),
            ],
            if (joined.isNotEmpty) ...<Widget>[
              if (invites.isNotEmpty)
                SectionHeader(label: l10n.chatRoomsHeader),
              for (final ChatRoomSummary room in joined)
                _ChatRoomTile(room: room),
            ],
          ],
        );
      },
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  const _ChatRoomTile({required this.room});

  final ChatRoomSummary room;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ChatMessage? last = room.lastMessage;
    final bool unread = room.unreadCount > 0;
    return ListTile(
      minTileHeight: AppSizes.minTouchTarget,
      leading: Icon(
        room.isDirect ? AppIcons.person_outline : AppIcons.group_outlined,
      ),
      title: Text(
        room.title ?? l10n.chatUntitledRoom,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: last == null
          ? null
          : Text(
              chatPreviewText(l10n, last),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      // The count is spelled out for screen readers and shown as a number,
      // never as a coloured dot alone.
      trailing: unread
          ? Semantics(
              label: l10n.chatUnreadCount(room.unreadCount),
              excludeSemantics: true,
              child: Badge.count(count: room.unreadCount),
            )
          : null,
      onTap: () => context.push(AppRoutes.chatRoom, extra: room.id),
    );
  }
}

class _ChatInviteTile extends ConsumerStatefulWidget {
  const _ChatInviteTile({required this.room});

  final ChatRoomSummary room;

  @override
  ConsumerState<_ChatInviteTile> createState() => _ChatInviteTileState();
}

class _ChatInviteTileState extends ConsumerState<_ChatInviteTile> {
  bool _busy = false;

  Future<void> _answer({required bool accept}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final gateway = ref.read(matrixGatewayProvider);
      if (accept) {
        await gateway.acceptInvite(widget.room.id);
      } else {
        await gateway.declineInvite(widget.room.id);
      }
    } on MatrixFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(chatFailureMessage(context.l10n, failure))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.chat_bubble_outline),
            title: Text(widget.room.title ?? l10n.chatUntitledRoom),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            children: <Widget>[
              OutlinedButton(
                onPressed: _busy ? null : () => _answer(accept: false),
                child: Text(l10n.chatInviteDecline),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _answer(accept: true),
                child: Text(l10n.chatInviteAccept),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _ChatAccountButton extends ConsumerWidget {
  const _ChatAccountButton({required this.account});

  final MatrixAccount account;

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(l10n.chatLogoutConfirmTitle),
            content: Text(l10n.chatLogoutConfirmMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.chatCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.chatLogoutConfirmAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatSessionControllerProvider.notifier).logout();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatLogoutFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    return PopupMenuButton<void>(
      tooltip: l10n.chatAccountMenu,
      icon: const Icon(AppIcons.account_circle_outlined),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          enabled: false,
          child: Text(l10n.chatSignedInAs(account.userId)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          onTap: () => _logout(context, ref),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.logout),
            title: Text(l10n.chatLogout),
          ),
        ),
      ],
    );
  }
}
