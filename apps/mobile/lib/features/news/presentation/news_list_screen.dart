// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../app/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/offline_notice.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/channel_subscriptions.dart';
import '../application/news_feed_controller.dart';
import '../application/news_feed_view_options.dart';
import '../application/news_providers.dart';
import '../data/news_models.dart';
import '../domain/news_feed_arrangement.dart';
import 'article_block.dart';
import 'news_ended_events.dart';
import 'news_filter_sheet.dart';

/// The news feed: a masthead, one filter button and an endless run of articles
/// that are read in place.
///
/// There is no article detail page. The list endpoint delivers the sanitised
/// content of every article, so a block expands inline instead of navigating —
/// which also means the feed never makes one request per visible article.
///
/// The masthead scrolls **with** the feed rather than staying pinned. A
/// newspaper does not repeat its own name down the page, and on a phone the
/// ninety pixels it would cost are a headline and a half.
class NewsListScreen extends ConsumerStatefulWidget {
  const NewsListScreen({super.key});

  @override
  ConsumerState<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends ConsumerState<NewsListScreen>
    with WidgetsBindingObserver, NewsEndedEventsRefresh<NewsListScreen> {
  Future<void> _refresh() async {
    ref.invalidate(newsChannelsProvider);
    await ref.read(newsFeedControllerProvider.future);
  }

  Widget _buildBody(NewsFeedState state) {
    final DateTime now = feedNow();
    syncEndedEventsTimer(state.articles, now);
    final NewsFeedArrangement arrangement = arrangeNewsFeed(
      state.articles,
      now: now,
      sort: ref.watch(newsFeedSortProvider),
      showEnded: ref.watch(
        newsShowEndedEventsProvider(NewsFeedScopeKey.mainFeed),
      ),
    );
    return _FeedBody(state: state, arrangement: arrangement);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<NewsFeedState> feed = ref.watch(
      newsFeedControllerProvider,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: switch (feed) {
            AsyncLoading<NewsFeedState>() when !feed.hasValue =>
              scrollableState(
                header: const _FeedMasthead(),
                child: const LoadingView(),
              ),
            AsyncError<NewsFeedState>(:final Object error) => scrollableState(
              header: const _FeedMasthead(),
              child: ErrorView(
                failure: error,
                onRetry: () {
                  ref.invalidate(newsChannelsProvider);
                  ref.invalidate(newsFeedControllerProvider);
                },
              ),
            ),
            _ => _buildBody(feed.requireValue),
          },
        ),
      ),
    );
  }
}

/// Empty, loading and error states must stay pull-to-refreshable.
///
/// `hasScrollBody: true` (the default) hands the child a BOUNDED, TIGHT
/// height equal to the remaining viewport without ever querying its
/// intrinsic height — required because [LoadingView] and [EmptyView] scroll
/// internally when that height is too small for their content (a large
/// Android keyboard on a small screen), and a scrollable child cannot report
/// a natural intrinsic size. `hasScrollBody: false` would ask for exactly
/// that and throw. The scroll view itself keeps pull-to-refresh working.
Widget scrollableState({required Widget child, Widget? header}) {
  return CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: <Widget>[
      if (header != null) SliverToBoxAdapter(child: header),
      SliverFillRemaining(child: child),
    ],
  );
}

/// The feed's masthead — the same header every other screen wears, with the
/// channel filter as its one action, plus the labelled entry into the event
/// view directly underneath.
class _FeedMasthead extends ConsumerWidget {
  const _FeedMasthead();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;

    final List<NewsChannel> channels =
        ref.watch(newsChannelsProvider).value?.value ?? const <NewsChannel>[];
    final ChannelSubscriptionState subscriptions = ref.watch(
      channelSubscriptionProvider,
    );
    // "Some channels are switched off" is a filter the reader should be able to
    // see from the outside — otherwise a missing article looks like a bug.
    final bool filtered =
        channels.isNotEmpty &&
        subscriptions.selectedSlugs.length < channels.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ScreenHeader(
          eyebrow: ModuleCategory.campus.label(l10n),
          title: l10n.newsFeedTitle,
          actions: <Widget>[
            IconButton(
              tooltip: l10n.newsFilterTooltip,
              onPressed: () => showNewsFilterSheet(context),
              // A different icon, not just a different colour.
              isSelected: filtered,
              icon: const Icon(AppIcons.filter_alt_outlined),
              selectedIcon: const Icon(AppIcons.filter_alt),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const _EventsEntry(),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

/// The one visibly labelled entry into the dedicated event view.
///
/// `ScreenHeader.actions` is icon buttons only, so this sits as its own row
/// under the masthead instead — a real word ("Events"), not just a glyph a
/// reader has to guess at. A distinct destination, not a preset of the tag
/// filter, so it stays reachable no matter which tag or "Alle" is selected.
class _EventsEntry extends StatelessWidget {
  const _EventsEntry();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.metrics.screenPadding,
        ),
        child: OutlinedButton.icon(
          onPressed: () => context.pushNamed(AppRoutes.newsEventsName),
          icon: const Icon(AppIcons.event_outlined),
          label: Text(l10n.newsEventsEntryLabel),
        ),
      ),
    );
  }
}

/// What a news list has to say about itself before the first article.
///
/// Both notices are about the response as a whole, not about one article: the
/// content is from the offline cache, or it is shown in German because no
/// translation exists. Shared by the main feed and every channel-scoped
/// screen, which carry the same two flags on their own state.
List<Widget> newsFeedNotices(
  BuildContext context, {
  required bool fromCache,
  DateTime? cachedAt,
  required bool translationFallback,
}) => <Widget>[
  if (fromCache) OfflineNotice(cachedAt: cachedAt),
  if (translationFallback)
    StatusBanner(
      icon: AppIcons.translate_outlined,
      title: context.l10n.newsTranslationFallbackHint,
    ),
];

class _FeedBody extends ConsumerWidget {
  const _FeedBody({required this.state, required this.arrangement});

  final NewsFeedState state;
  final NewsFeedArrangement arrangement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppMetrics metrics = context.metrics;
    final List<NewsArticle> articles = arrangement.articles;

    if (state.articles.isEmpty) return _EmptyFeed(state: state);

    final List<Widget> notices = newsFeedNotices(
      context,
      fromCache: state.fromCache,
      cachedAt: state.cachedAt,
      translationFallback: state.translationFallback,
    );
    final bool showFooter = state.hasMore || state.loadMoreFailed;
    Widget footer() => NewsLoadMoreFooter(
      page: state.page,
      hasMore: state.hasMore,
      isLoadingMore: state.isLoadingMore,
      loadMoreFailed: state.loadMoreFailed,
      onLoadMore: () =>
          ref.read(newsFeedControllerProvider.notifier).loadMore(),
    );
    const String scope = NewsFeedScopeKey.mainFeed;

    // Every loaded post is an ended event: say so, offer to reveal them, and
    // keep the footer so the next page still loads on its own.
    if (articles.isEmpty) {
      return scrollableState(
        header: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _FeedMasthead(),
            if (notices.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.screenPadding,
                  metrics.cardGap,
                  metrics.screenPadding,
                  0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: notices,
                ),
              ),
          ],
        ),
        child: newsAllEventsEndedView(
          context,
          toggle: NewsEndedEventsToggle(scope: scope, arrangement: arrangement),
          footer: showFooter ? footer() : null,
        ),
      );
    }

    final bool showToggle = arrangement.endedCount > 0;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: metrics.sectionGap),
      itemCount:
          1 +
          notices.length +
          articles.length +
          (showToggle ? 1 : 0) +
          (showFooter ? 1 : 0),
      // A plain gap, not a rule: every article already draws its own card
      // border, so a hairline between two of them would just double the edge.
      separatorBuilder: (BuildContext context, int index) =>
          SizedBox(height: metrics.cardGap),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) return const _FeedMasthead();
        final int afterHeader = index - 1;
        if (afterHeader < notices.length) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.screenPadding),
            child: notices[afterHeader],
          );
        }
        final int articleIndex = afterHeader - notices.length;
        if (articleIndex >= articles.length) {
          if (showToggle && articleIndex == articles.length) {
            return NewsEndedEventsToggle(
              scope: scope,
              arrangement: arrangement,
            );
          }
          return footer();
        }

        final NewsArticle article = articles[articleIndex];
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.screenPadding),
          child: ArticleBlock(
            key: ValueKey<String>(article.slug),
            article: article,
            eventEnded: arrangement.isEnded(article),
          ),
        );
      },
    );
  }
}

/// Why the feed is empty — the answers are genuinely different.
class _EmptyFeed extends ConsumerWidget {
  const _EmptyFeed({required this.state});

  final NewsFeedState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppMetrics metrics = context.metrics;
    final List<NewsChannel> channels =
        ref.watch(newsChannelsProvider).value?.value ?? const <NewsChannel>[];
    final ChannelSubscriptionState subscriptions = ref.watch(
      channelSubscriptionProvider,
    );

    final Widget empty;
    if (channels.isEmpty) {
      empty = EmptyView(
        icon: AppIcons.rss_feed_outlined,
        title: l10n.newsNoChannelsAvailableTitle,
        message: l10n.newsNoChannelsAvailableMessage,
      );
    } else if (subscriptions.selectedSlugs.isEmpty) {
      empty = EmptyView(
        icon: AppIcons.filter_list_off,
        title: l10n.newsNoChannelsSelectedTitle,
        message: l10n.newsNoChannelsSelectedMessage,
        action: FilledButton.icon(
          onPressed: () => showNewsFilterSheet(context),
          icon: const Icon(AppIcons.filter_alt_outlined),
          label: Text(l10n.newsChannelPickerTitle),
        ),
      );
    } else {
      empty = EmptyView(
        title: l10n.newsEmptyTitle,
        message: l10n.newsEmptyMessage,
      );
    }

    final List<Widget> notices = newsFeedNotices(
      context,
      fromCache: state.fromCache,
      cachedAt: state.cachedAt,
      translationFallback: state.translationFallback,
    );
    return scrollableState(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _FeedMasthead(),
          if (notices.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                metrics.screenPadding,
                metrics.cardGap,
                metrics.screenPadding,
                0,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: notices),
            ),
        ],
      ),
      child: empty,
    );
  }
}

/// The end of an endless news list: loads the next page, or explains why it
/// could not.
///
/// Shared by the main feed and every channel-scoped screen so both follow
/// exactly the same pagination contract — same footer-triggered load, same
/// failure and retry affordance — instead of growing a second copy per
/// screen. Takes primitives rather than a whole feed state so it does not
/// care which provider is behind [onLoadMore].
///
/// Requesting the page here rather than from a scroll offset is what makes a
/// list load *shortly before* the end: it builds its items a little ahead of
/// the viewport, so this footer exists before the reader reaches it.
class NewsLoadMoreFooter extends StatefulWidget {
  const NewsLoadMoreFooter({
    required this.page,
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadMoreFailed,
    required this.onLoadMore,
    super.key,
  });

  /// The highest page already merged in — used only to avoid asking twice.
  final int page;
  final bool hasMore;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final VoidCallback onLoadMore;

  @override
  State<NewsLoadMoreFooter> createState() => _NewsLoadMoreFooterState();
}

class _NewsLoadMoreFooterState extends State<NewsLoadMoreFooter> {
  /// The page this footer has already asked to follow.
  ///
  /// Without it a rebuild during the request would queue a second one.
  int? _requested;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant NewsLoadMoreFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeLoad();
  }

  void _maybeLoad() {
    if (!widget.hasMore || widget.isLoadingMore) return;
    // A failed page waits for the reader to press retry. Retrying by itself
    // would hammer an endpoint that has just said no.
    if (widget.loadMoreFailed || _requested == widget.page) return;
    _requested = widget.page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onLoadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final AppMetrics metrics = context.metrics;

    if (widget.loadMoreFailed) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.screenPadding),
        child: Column(
          children: <Widget>[
            Text(
              l10n.newsLoadMoreFailed,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () {
                _requested = null;
                widget.onLoadMore();
              },
              icon: const Icon(AppIcons.refresh),
              label: Text(l10n.newsLoadMoreRetry),
            ),
          ],
        ),
      );
    }

    // The feed reaching for its next page, in the same marker sweep the app
    // uses for every other kind of waiting.
    return Center(
      child: SizedBox(
        width: AppSpacing.xxxl * 2,
        child: LinearProgressIndicator(
          minHeight: AppSizes.beam,
          color: colors.accent,
          backgroundColor: colors.surfaceVariant,
        ),
      ),
    );
  }
}
