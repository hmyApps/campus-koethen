// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/mail_search_controller.dart';
import '../domain/mail_message.dart';
import 'mail_error_messages.dart';
import 'mail_header_tile.dart';

/// Mail search, local first.
///
/// Submitting searches what is already on the device — instant and available
/// offline. The server (IMAP SEARCH) is a second, explicit step for everything
/// not cached; its hits are appended without duplicates, and neither its
/// failure nor its emptiness ever removes a local hit from the screen.
class MailSearchScreen extends ConsumerStatefulWidget {
  const MailSearchScreen({super.key});

  @override
  ConsumerState<MailSearchScreen> createState() => _MailSearchScreenState();
}

class _MailSearchScreenState extends ConsumerState<MailSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) =>
      ref.read(mailSearchControllerProvider.notifier).run(value);

  void _searchServer() =>
      ref.read(mailSearchControllerProvider.notifier).searchServer();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final MailSearchState search = ref.watch(mailSearchControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: l10n.mailSearchHint,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.actionClose,
                    icon: const Icon(AppIcons.clear),
                    onPressed: () {
                      _controller.clear();
                      ref.read(mailSearchControllerProvider.notifier).clear();
                      setState(() => _hasText = false);
                    },
                  ),
          ),
          // Only rebuild when the field crosses between empty and non-empty —
          // that is the sole thing the view derives from the live text (the
          // clear button). The results list changes on submit, not on every
          // keystroke, so rebuilding it per character was wasted work.
          onChanged: (String value) {
            final bool hasText = value.isNotEmpty;
            if (hasText != _hasText) setState(() => _hasText = hasText);
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (search.hasSearched) ...<Widget>[
              _ServerSearchBar(search: search, onSearchServer: _searchServer),
              const HairRule(),
            ],
            Expanded(child: _results(context, l10n, locale, search)),
          ],
        ),
      ),
    );
  }

  Widget _results(
    BuildContext context,
    AppLocalizations l10n,
    String locale,
    MailSearchState search,
  ) {
    if (!search.hasSearched) {
      return EmptyView(
        icon: AppIcons.search,
        title: l10n.mailSearchTooltip,
        message: l10n.mailSearchPrompt,
      );
    }
    if (search.isSearchingLocally) return const LoadingView();
    if (!search.hasResults) {
      return EmptyView(
        icon: AppIcons.search_off,
        title: l10n.mailSearchEmptyTitle,
        // Before the server has been asked, "no matches" is only a statement
        // about this device — say so, and keep the server step in view.
        message: switch (search.serverStatus) {
          MailServerSearchStatus.done => l10n.mailSearchEmpty,
          _ when !search.localAvailable => l10n.mailSearchLocalUnavailable,
          _ => l10n.mailSearchLocalEmpty,
        },
      );
    }

    final bool hasBothSections =
        search.local.isNotEmpty && search.server.isNotEmpty;
    return CustomScrollView(
      slivers: <Widget>[
        if (hasBothSections)
          SliverToBoxAdapter(
            child: SectionHeader(label: l10n.mailSearchLocalSection),
          ),
        _tiles(search.local, locale),
        if (hasBothSections)
          SliverToBoxAdapter(
            child: SectionHeader(label: l10n.mailSearchServerSection),
          ),
        _tiles(search.server, locale),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }

  Widget _tiles(List<MailMessageHeader> headers, String locale) =>
      SliverList.builder(
        itemCount: headers.length,
        itemBuilder: (BuildContext context, int index) {
          final MailMessageHeader header = headers[index];
          return MailHeaderTile(
            key: ValueKey<String>(header.id),
            header: header,
            locale: locale,
          );
        },
      );
}

/// The second half of the search: everything the device does not have.
///
/// Deliberately an explicit action rather than an automatic follow-up query —
/// the local answer is already on screen, and an IMAP SEARCH over a slow or
/// unreachable connection is a cost the reader gets to choose. A failure is
/// reported here, next to its retry, so the results list below stays intact.
class _ServerSearchBar extends StatelessWidget {
  const _ServerSearchBar({required this.search, required this.onSearchServer});

  final MailSearchState search;
  final VoidCallback onSearchServer;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!search.localAvailable) ...<Widget>[
            Text(
              l10n.mailSearchLocalUnavailable,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (search.serverStatus == MailServerSearchStatus.running)
            Semantics(
              liveRegion: true,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: AppSizes.iconSmall,
                    height: AppSizes.iconSmall,
                    child: CircularProgressIndicator(
                      strokeWidth: AppSizes.rule,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      l10n.mailSearchServerRunning,
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else if (search.serverStatus == MailServerSearchStatus.failed)
            StatusBanner(
              title: l10n.mailSearchServerFailedTitle,
              message: mailFailureMessage(l10n, search.serverError),
              tone: StatusTone.warning,
              icon: AppIcons.cloud_off_outlined,
              action: TextButton.icon(
                onPressed: onSearchServer,
                icon: const Icon(AppIcons.refresh, size: AppSizes.iconSmall),
                label: Text(l10n.mailRetry),
              ),
            )
          else ...<Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: search.canSearchServer ? onSearchServer : null,
                icon: const Icon(AppIcons.search, size: AppSizes.iconSmall),
                label: Text(l10n.mailSearchServerAction),
              ),
            ),
            if (search.serverStatus == MailServerSearchStatus.done &&
                search.server.isEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.mailSearchServerEmpty,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
