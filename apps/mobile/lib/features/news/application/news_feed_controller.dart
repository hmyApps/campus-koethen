// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/loaded.dart';
import '../data/news_models.dart';
import '../data/news_repository.dart';
import 'channel_subscriptions.dart';
import 'news_providers.dart';
import 'tag_filter.dart';

/// Everything the feed screen needs to draw itself.
@immutable
class NewsFeedState {
  const NewsFeedState({
    required this.articles,
    required this.page,
    required this.totalPages,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.fromCache = false,
    this.cachedAt,
    this.translationFallback = false,
  });

  /// Every article loaded so far, in server order, without repeats.
  final List<NewsArticle> articles;

  /// The highest page that has been merged in.
  final int page;
  final int totalPages;

  final bool isLoadingMore;

  /// The last attempt to append a page failed.
  ///
  /// A flag rather than the error object: the footer offers a retry, and the
  /// exact upstream failure is not something to put in front of a reader.
  final bool loadMoreFailed;

  /// The first page came from the offline cache.
  final bool fromCache;
  final DateTime? cachedAt;

  /// At least one article is shown in German because no translation exists.
  ///
  /// Read from the first page only: the locale contract is a property of the
  /// request, and a reader is told once, not once per page.
  final bool translationFallback;

  bool get hasMore => page < totalPages;

  NewsFeedState copyWith({
    List<NewsArticle>? articles,
    int? page,
    int? totalPages,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => NewsFeedState(
    articles: articles ?? this.articles,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    fromCache: fromCache,
    cachedAt: cachedAt,
    translationFallback: translationFallback,
  );
}

/// The endlessly scrolling feed.
///
/// Pages are appended, never replaced, and merged by **slug**: the server sorts
/// pinned articles first, so an article pinned between two requests can appear
/// on two pages, and a feed that showed it twice would look broken.
///
/// A failed page does **not** discard what is already on screen. Losing a
/// screenful of articles because the next request timed out is a far worse
/// outcome than a retry button at the bottom.
///
/// The channel selection, the tag filter and the locale are watched, so
/// changing any of them rebuilds this notifier and the feed starts again at
/// page one — which is the required behaviour and costs no extra code. The
/// two filters combine by AND, never OR, per the API contract: a tag never
/// widens what the channel subscription already excludes.
class NewsFeedController extends AsyncNotifier<NewsFeedState> {
  NewsRepository get _repository => ref.read(newsRepositoryProvider);

  int _generation = 0;
  _NewsFeedScope? _activeScope;

  @override
  Future<NewsFeedState> build() async {
    final int generation = ++_generation;
    _activeScope = null;
    final String locale = ref.watch(localeCodeProvider);
    // Both catalogues are requested before either is awaited: they are separate
    // endpoints that do not depend on one another, and awaiting the first
    // before asking for the second put two full round trips in front of the
    // first article on a cold start.
    //
    // `Future.wait` rather than two awaits in a row so that a failure of one
    // never leaves the other's error unobserved, and rather than the record
    // `.wait` because that reports failures as a `ParallelWaitError` — the
    // error view needs the original `ApiFailure` to name what went wrong.
    // Both are complete before the tag filter is read below, which is what a
    // stale, meanwhile-removed tag selection needs to be reconciled first.
    final List<Object?> catalogues = await Future.wait<Object?>(
      <Future<Object?>>[
        ref.watch(newsChannelsProvider.future),
        ref.watch(newsTagsProvider.future),
      ],
    );
    final Loaded<List<NewsChannel>> channels =
        catalogues[0]! as Loaded<List<NewsChannel>>;
    final ChannelSubscriptionState subscriptions = ref.watch(
      channelSubscriptionProvider,
    );
    final String? tagsParameter = ref.watch(newsTagFilterProvider);

    if (channels.value.isEmpty) {
      if (generation == _generation) {
        _activeScope = _NewsFeedScope(
          generation: generation,
          locale: locale,
          channelsParameter: '',
          tagsParameter: tagsParameter,
        );
      }
      return const NewsFeedState(
        articles: <NewsArticle>[],
        page: 1,
        totalPages: 1,
      );
    }

    final String? channelsParameter = ChannelSubscriptionRules.queryValue(
      available: channels.value,
      selected: subscriptions.selectedSlugs,
    );
    final _NewsFeedScope scope = _NewsFeedScope(
      generation: generation,
      locale: locale,
      channelsParameter: channelsParameter,
      tagsParameter: tagsParameter,
    );

    final Loaded<NewsPage> first = await _repository.fetchArticles(
      locale: scope.locale,
      channelsParameter: scope.channelsParameter,
      tagsParameter: scope.tagsParameter,
    );
    if (generation == _generation) _activeScope = scope;

    return NewsFeedState(
      articles: List<NewsArticle>.unmodifiable(first.value.articles),
      page: first.value.page,
      totalPages: first.value.totalPages,
      fromCache: first.fromCache,
      cachedAt: first.cachedAt,
      translationFallback: first.meta.translationFallback,
    );
  }

  /// Appends the next page.
  ///
  /// Does nothing while one is already in flight or when the last page has been
  /// reached, so scrolling near the end cannot fire a burst of requests.
  Future<void> loadMore() async {
    final NewsFeedState? current = state.value;
    final _NewsFeedScope? scope = _activeScope;
    if (current == null ||
        scope == null ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }

    state = AsyncData<NewsFeedState>(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );

    try {
      final Loaded<NewsPage> next = await _repository.fetchArticles(
        locale: scope.locale,
        channelsParameter: scope.channelsParameter,
        tagsParameter: scope.tagsParameter,
        page: current.page + 1,
      );
      if (!_isCurrent(scope)) return;
      // The state may have been replaced while the request was in flight.
      final NewsFeedState base = state.value ?? current;
      state = AsyncData<NewsFeedState>(
        base.copyWith(
          articles: _merge(base.articles, next.value.articles),
          page: next.value.page,
          totalPages: next.value.totalPages,
          isLoadingMore: false,
          loadMoreFailed: false,
        ),
      );
    } on Object {
      if (!_isCurrent(scope)) return;
      final NewsFeedState base = state.value ?? current;
      // Everything already loaded stays. Only the footer changes.
      state = AsyncData<NewsFeedState>(
        base.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }

  bool _isCurrent(_NewsFeedScope scope) =>
      identical(_activeScope, scope) && scope.generation == _generation;

  /// Pull-to-refresh: back to page one for the current selection.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Appends what is genuinely new, keeping the order of both pages.
  static List<NewsArticle> _merge(
    List<NewsArticle> existing,
    List<NewsArticle> incoming,
  ) {
    final Set<String> seen = existing.map((NewsArticle a) => a.slug).toSet();
    final List<NewsArticle> merged = List<NewsArticle>.of(existing);
    for (final NewsArticle article in incoming) {
      if (seen.add(article.slug)) merged.add(article);
    }
    return List<NewsArticle>.unmodifiable(merged);
  }
}

@immutable
class _NewsFeedScope {
  const _NewsFeedScope({
    required this.generation,
    required this.locale,
    required this.channelsParameter,
    required this.tagsParameter,
  });

  final int generation;
  final String locale;
  final String? channelsParameter;
  final String? tagsParameter;
}

final AsyncNotifierProvider<NewsFeedController, NewsFeedState>
newsFeedControllerProvider =
    AsyncNotifierProvider<NewsFeedController, NewsFeedState>(
      NewsFeedController.new,
    );
