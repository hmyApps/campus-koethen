// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/translation_fallback_notice.dart';
import '../../../l10n/l10n.dart';
import '../../notifications/presentation/pre_permission_sheet.dart';
import '../application/timetable_providers.dart';
import '../data/timetable_models.dart';
import '../data/timetable_repository.dart';

/// Opens the course picker as a modal bottom sheet.
///
/// The sheet is scroll controlled and pages through server-side search results.
///
/// Choosing a group for the first time is contextual entry point C of the UX
/// spec (§ 2.2): it is the moment somebody says which lectures are theirs, and
/// therefore the moment the daily overview at 08:00 becomes worth offering.
/// The offer runs from the **caller's** context, after the sheet has closed —
/// a sheet cannot open another one on top of its own disposal — and asks only
/// under the conditions [maybeOfferNotificationOptIn] guards, so a reader who
/// has already answered is never asked again.
Future<void> showTimetableGroupPickerSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final String? before = ref.read(selectedTimetableGroupIdProvider);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // A modal bottom sheet is not resized for the keyboard on its own — the
    // sheet's own height factor is computed against the full screen height
    // regardless of how much of it the keyboard covers. Without this padding
    // a large keyboard simply sits on top of the sheet, hiding the search
    // field it was meant to be typed into.
    builder: (BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: const SafeArea(child: TimetableGroupPickerList()),
      ),
    ),
  );

  if (!context.mounted) return;
  final String? after = ref.read(selectedTimetableGroupIdProvider);
  if (after == null || after == before) return;
  await maybeOfferNotificationOptIn(context, ref);
}

/// Searchable list of all study groups. Exactly one group can be selected.
class TimetableGroupPickerList extends ConsumerStatefulWidget {
  const TimetableGroupPickerList({this.dismissOnSelection = true, super.key});

  final bool dismissOnSelection;

  @override
  ConsumerState<TimetableGroupPickerList> createState() =>
      _TimetableGroupPickerListState();
}

class _TimetableGroupPickerListState
    extends ConsumerState<TimetableGroupPickerList> {
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<TimetableGroupSearchState> groups = ref.watch(
      timetableGroupSearchProvider(_query),
    );
    final String? selected = ref.watch(selectedTimetableGroupIdProvider);

    // A CustomScrollView rather than a fixed header plus an `Expanded` list:
    // on a small viewport with a large keyboard and scaled-up text, the
    // title and search field alone can already exceed the sheet's height, and
    // an `Expanded` cannot give them less than they ask for — it overflows
    // instead. Slivers let the header scroll away with the list rather than
    // forcing space it does not have.
    // The RadioGroup wraps the whole scroll view rather than just the list
    // sliver: it renders a `Semantics` node of its own, which — like any
    // other box widget — cannot take a sliver as its child. Wrapping the
    // CustomScrollView keeps it a plain box widget; the RadioListTiles below
    // still find it through the element tree regardless of the sliver
    // nesting in between.
    final NavigatorState navigator = Navigator.of(context);
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (String? value) async {
        final TimetableGroupSearchState? current = groups.value;
        final TimetableGroup? group = current?.groups
            .where((TimetableGroup candidate) => candidate.id == value)
            .firstOrNull;
        if (group != null) {
          await ref
              .read(timetableRepositoryProvider)
              .rememberGroup(
                locale: ref.read(localeCodeProvider),
                group: group,
                meta: current!.meta,
              );
        }
        await ref.read(settingsProvider.notifier).setTimetableGroup(value);
        if (mounted && widget.dismissOnSelection) await navigator.maybePop();
      },
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.timetableGroupPickerTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _scheduleSearch,
                decoration: InputDecoration(
                  labelText: l10n.timetableGroupSearchLabel,
                  hintText: l10n.timetableGroupSearchHint,
                  prefixIcon: const Icon(AppIcons.search),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
          switch (groups) {
            AsyncLoading<TimetableGroupSearchState>() when !groups.hasValue =>
              const SliverFillRemaining(child: LoadingView()),
            AsyncError<TimetableGroupSearchState>(:final Object error) =>
              SliverFillRemaining(
                child: ErrorView(
                  failure: error,
                  onRetry: () =>
                      ref.invalidate(timetableGroupSearchProvider(_query)),
                ),
              ),
            _ => _buildList(l10n, groups.requireValue),
          },
        ],
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n, TimetableGroupSearchState state) {
    final List<TimetableGroup> groups = state.groups;
    if (groups.isEmpty) {
      return SliverFillRemaining(
        child: EmptyView(
          icon: _query.isEmpty
              ? AppIcons.school_outlined
              : AppIcons.search_off_outlined,
          title: _query.isEmpty
              ? l10n.timetableNoGroupsTitle
              : l10n.timetableGroupSearchEmptyTitle,
          message: _query.isEmpty
              ? l10n.timetableNoGroupsMessage
              : l10n.timetableGroupSearchEmptyMessage,
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: <Widget>[
        if (state.meta.translationFallback)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(child: TranslationFallbackNotice()),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          sliver: SliverList.builder(
            itemCount:
                groups.length + (state.hasMore || state.loadMoreFailed ? 1 : 0),
            itemBuilder: (BuildContext context, int index) {
              if (index == groups.length) {
                return _TimetableGroupLoadMoreFooter(
                  page: state.page,
                  hasMore: state.hasMore,
                  isLoadingMore: state.isLoadingMore,
                  loadMoreFailed: state.loadMoreFailed,
                  onLoadMore: () => ref
                      .read(timetableGroupSearchProvider(_query).notifier)
                      .loadMore(),
                );
              }
              final TimetableGroup group = groups[index];
              return RadioListTile<String>.adaptive(
                value: group.id,
                title: Text(group.shortName),
                subtitle: _subtitle(group),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Long name and department, both verbatim from the source system.
  Widget? _subtitle(TimetableGroup group) {
    final List<String> parts = <String?>[
      group.longName,
      group.department,
    ].whereType<String>().toList(growable: false);
    if (parts.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[for (final String part in parts) Text(part)],
    );
  }
}

class _TimetableGroupLoadMoreFooter extends StatefulWidget {
  const _TimetableGroupLoadMoreFooter({
    required this.page,
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadMoreFailed,
    required this.onLoadMore,
  });

  final int page;
  final bool hasMore;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final VoidCallback onLoadMore;

  @override
  State<_TimetableGroupLoadMoreFooter> createState() =>
      _TimetableGroupLoadMoreFooterState();
}

class _TimetableGroupLoadMoreFooterState
    extends State<_TimetableGroupLoadMoreFooter> {
  int? _requestedAfterPage;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant _TimetableGroupLoadMoreFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeLoad();
  }

  void _maybeLoad() {
    if (!widget.hasMore ||
        widget.isLoadingMore ||
        widget.loadMoreFailed ||
        _requestedAfterPage == widget.page) {
      return;
    }
    _requestedAfterPage = widget.page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLoadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          children: <Widget>[
            Text(
              context.l10n.timetableGroupLoadMoreFailed,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () {
                _requestedAfterPage = null;
                widget.onLoadMore();
              },
              icon: const Icon(AppIcons.refresh),
              label: Text(context.l10n.actionRetry),
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: LinearProgressIndicator(),
    );
  }
}
