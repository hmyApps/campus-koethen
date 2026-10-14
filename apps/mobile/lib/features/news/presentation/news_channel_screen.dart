// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../core/network/loaded.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/news_channel_feed_controller.dart';
import '../application/news_feed_view_options.dart';
import '../application/news_providers.dart';
import '../data/news_models.dart';
import '../domain/news_feed_arrangement.dart';
import 'article_block.dart';
import 'news_ended_events.dart';
import 'news_list_screen.dart'
    show NewsLoadMoreFooter, newsFeedNotices, scrollableState;

/// One channel's profile: its name and description, followed by its own
/// articles, newest first.
///
/// Pushed as a nested route **under** the news branch (see `app_router.dart`)
/// rather than replacing it, so popping back returns to the feed exactly as
/// it was — same scroll position, same expanded/collapsed cards — without this
/// screen having to do anything special to preserve that.
///
/// Resolves the tapped slug against the same dynamic channel list the feed's
/// filter uses (`newsChannelsProvider` → `GET /v1/posts/channels`) rather than
/// trusting the route parameter: a channel can be renamed, deactivated or
/// removed entirely, and a stale deep link must say so clearly instead of
/// rendering a title-only screen with nothing behind it.
class NewsChannelScreen extends ConsumerWidget {
  const NewsChannelScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Loaded<List<NewsChannel>>> channelsAsync = ref.watch(
      newsChannelsProvider,
    );

    return switch (channelsAsync) {
      AsyncLoading<Loaded<List<NewsChannel>>>() when !channelsAsync.hasValue =>
        ScreenScaffold(
          eyebrow: ModuleCategory.campus.label(l10n),
          title: l10n.newsFeedTitle,
          body: const LoadingView(),
        ),
      AsyncError<Loaded<List<NewsChannel>>>(:final Object error) =>
        ScreenScaffold(
          eyebrow: ModuleCategory.campus.label(l10n),
          title: l10n.newsFeedTitle,
          body: ErrorView(
            failure: error,
            onRetry: () => ref.invalidate(newsChannelsProvider),
          ),
        ),
      _ => _ResolvedChannelScreen(
        slug: slug,
        channels: channelsAsync.requireValue.value,
      ),
    };
  }
}

/// Looks the slug up in the resolved channel list and branches into the
/// "not available" state or the real content.
class _ResolvedChannelScreen extends StatelessWidget {
  const _ResolvedChannelScreen({required this.slug, required this.channels});

  final String slug;
  final List<NewsChannel> channels;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    NewsChannel? channel;
    for (final NewsChannel candidate in channels) {
      if (candidate.slug == slug) {
        channel = candidate;
        break;
      }
    }

    if (channel == null) {
      // Distinct from the "this channel has no articles yet" state below: an
      // unknown or inactive slug is not a channel with nothing in it, it is
      // not a channel at all as far as this reader can tell. The screen title
      // stays the generic feed title rather than repeating "not available" —
      // that message belongs to the body, said once.
      return ScreenScaffold(
        eyebrow: ModuleCategory.campus.label(l10n),
        title: l10n.newsFeedTitle,
        body: EmptyView(
          icon: AppIcons.link_off,
          title: l10n.newsChannelNotAvailableTitle,
          message: l10n.newsChannelNotAvailableMessage,
        ),
      );
    }

    return _ChannelContent(channel: channel);
  }
}

class _ChannelContent extends ConsumerStatefulWidget {
  const _ChannelContent({required this.channel});

  final NewsChannel channel;

  @override
  ConsumerState<_ChannelContent> createState() => _ChannelContentState();
}

class _ChannelContentState extends ConsumerState<_ChannelContent>
    with WidgetsBindingObserver, NewsEndedEventsRefresh<_ChannelContent> {
  Future<void> _refresh() async {
    await ref
        .read(newsChannelFeedControllerProvider(widget.channel.slug).notifier)
        .refresh();
  }

  /// A channel keeps its own newest-first order — the sort choice lives in
  /// the main feed's filter sheet, which this screen does not offer — but
  /// hides ended event posts by the same rule as the feed.
  Widget _buildArticles(NewsChannelFeedState state) {
    final DateTime now = feedNow();
    syncEndedEventsTimer(state.articles, now);
    final String scope = NewsFeedScopeKey.channel(widget.channel.slug);
    final NewsFeedArrangement arrangement = arrangeNewsFeed(
      state.articles,
      now: now,
      sort: NewsFeedSort.newest,
      showEnded: ref.watch(newsShowEndedEventsProvider(scope)),
    );
    return _ChannelArticles(
      channel: widget.channel,
      state: state,
      arrangement: arrangement,
      scope: scope,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<NewsChannelFeedState> feed = ref.watch(
      newsChannelFeedControllerProvider(widget.channel.slug),
    );

    return ScreenScaffold(
      eyebrow: ModuleCategory.campus.label(l10n),
      title: widget.channel.name,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: switch (feed) {
          AsyncLoading<NewsChannelFeedState>() when !feed.hasValue =>
            scrollableState(
              header: _ChannelHeader(channel: widget.channel),
              child: const LoadingView(),
            ),
          AsyncError<NewsChannelFeedState>(:final Object error) =>
            scrollableState(
              header: _ChannelHeader(channel: widget.channel),
              child: ErrorView(
                failure: error,
                onRetry: () => ref.invalidate(
                  newsChannelFeedControllerProvider(widget.channel.slug),
                ),
              ),
            ),
          _ => _buildArticles(feed.requireValue),
        },
      ),
    );
  }
}

/// Optional channel context below the screen title.
///
/// The title already names the channel, so this area contains only its
/// description. The editorial colour stays in the data model for future event
/// colouring but is deliberately not rendered on the channel page.
class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.channel});

  final NewsChannel channel;

  @override
  Widget build(BuildContext context) {
    final String? description = channel.description;
    if (description == null) return const SizedBox.shrink();
    final AppMetrics metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.screenPadding,
        AppSpacing.md,
        metrics.screenPadding,
        AppSpacing.lg,
      ),
      child: Text(description, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

/// The channel's own articles: same notices, same footer-triggered pagination
/// and the same "no articles" wording pattern as the main feed, just scoped.
class _ChannelArticles extends ConsumerWidget {
  const _ChannelArticles({
    required this.channel,
    required this.state,
    required this.arrangement,
    required this.scope,
  });

  final NewsChannel channel;
  final NewsChannelFeedState state;
  final NewsFeedArrangement arrangement;
  final String scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppMetrics metrics = context.metrics;
    final List<NewsArticle> articles = arrangement.articles;
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
      onLoadMore: () => ref
          .read(newsChannelFeedControllerProvider(channel.slug).notifier)
          .loadMore(),
    );

    if (articles.isEmpty) {
      final bool allEnded = state.articles.isNotEmpty;
      return scrollableState(
        header: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ChannelHeader(channel: channel),
            if (notices.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.screenPadding,
                  0,
                  metrics.screenPadding,
                  metrics.cardGap,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: notices,
                ),
              ),
          ],
        ),
        // Distinct from "channel not available": this channel exists, it just
        // has nothing published in it right now.
        child: allEnded
            ? newsAllEventsEndedView(
                context,
                toggle: NewsEndedEventsToggle(
                  scope: scope,
                  arrangement: arrangement,
                ),
                footer: showFooter ? footer() : null,
              )
            : EmptyView(
                title: l10n.newsChannelEmptyTitle,
                message: l10n.newsChannelEmptyMessage,
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
      separatorBuilder: (BuildContext context, int index) {
        if (index == 0) return SizedBox(height: metrics.cardGap);
        return SizedBox(height: metrics.sectionGap);
      },
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) return _ChannelHeader(channel: channel);
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
