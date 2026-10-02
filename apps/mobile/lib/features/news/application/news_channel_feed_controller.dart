// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/loaded.dart';
import '../data/news_models.dart';
import '../data/news_repository.dart';

/// Everything the channel screen needs to draw its article list.
///
/// The channel-scoped twin of `NewsFeedState`: same shape, same pagination
/// semantics, but for exactly one channel slug rather than the reader's whole
/// subscription. Kept as its own type instead of reusing `NewsFeedState`
/// because the two states are read from different providers and mixing them
/// would let a channel screen accidentally observe the main feed's paging.
@immutable
class NewsChannelFeedState {
  const NewsChannelFeedState({
    required this.articles,
    required this.page,
    required this.totalPages,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.fromCache = false,
    this.cachedAt,
    this.translationFallback = false,
  });

  final List<NewsArticle> articles;
  final int page;
  final int totalPages;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final bool fromCache;
  final DateTime? cachedAt;
  final bool translationFallback;

  bool get hasMore => page < totalPages;

  NewsChannelFeedState copyWith({
    List<NewsArticle>? articles,
    int? page,
    int? totalPages,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => NewsChannelFeedState(
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

/// The endless article list of exactly one channel.
///
/// Mirrors `NewsFeedController`'s pagination and merge behaviour — pages
/// appended and merged by slug, a failed page never discards what is already
/// on screen — but scoped from the start with `channelsParameter: slug`
/// (`GET /v1/posts?channels=<slug>`), reusing `NewsRepository.fetchArticles`
/// exactly as the main feed does rather than adding a new endpoint.
class NewsChannelFeedController extends AsyncNotifier<NewsChannelFeedState> {
  NewsChannelFeedController(this.slug);

  final String slug;

  NewsRepository get _repository => ref.read(newsRepositoryProvider);
  int _generation = 0;
  _NewsChannelFeedScope? _activeScope;

  @override
  Future<NewsChannelFeedState> build() async {
    final int generation = ++_generation;
    _activeScope = null;
    final _NewsChannelFeedScope scope = _NewsChannelFeedScope(
      generation: generation,
      locale: ref.watch(localeCodeProvider),
      channelSlug: slug,
    );

    final Loaded<NewsPage> first = await _repository.fetchArticles(
      locale: scope.locale,
      channelsParameter: scope.channelSlug,
    );
    if (generation == _generation) _activeScope = scope;

    return NewsChannelFeedState(
      articles: List<NewsArticle>.unmodifiable(first.value.articles),
      page: first.value.page,
      totalPages: first.value.totalPages,
      fromCache: first.fromCache,
      cachedAt: first.cachedAt,
      translationFallback: first.meta.translationFallback,
    );
  }

  /// Appends the next page. See `NewsFeedController.loadMore` for the guard
  /// rationale — identical here.
  Future<void> loadMore() async {
    final NewsChannelFeedState? current = state.value;
    final _NewsChannelFeedScope? scope = _activeScope;
    if (current == null ||
        scope == null ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }

    state = AsyncData<NewsChannelFeedState>(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );

    try {
      final Loaded<NewsPage> next = await _repository.fetchArticles(
        locale: scope.locale,
        channelsParameter: scope.channelSlug,
        page: current.page + 1,
      );
      if (!_isCurrent(scope)) return;
      final NewsChannelFeedState base = state.value ?? current;
      state = AsyncData<NewsChannelFeedState>(
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
      final NewsChannelFeedState base = state.value ?? current;
      state = AsyncData<NewsChannelFeedState>(
        base.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }

  bool _isCurrent(_NewsChannelFeedScope scope) =>
      identical(_activeScope, scope) && scope.generation == _generation;

  /// Pull-to-refresh: back to page one for this channel.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

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
class _NewsChannelFeedScope {
  const _NewsChannelFeedScope({
    required this.generation,
    required this.locale,
    required this.channelSlug,
  });

  final int generation;
  final String locale;
  final String channelSlug;
}

final newsChannelFeedControllerProvider =
    AsyncNotifierProvider.family<
      NewsChannelFeedController,
      NewsChannelFeedState,
      String
    >(NewsChannelFeedController.new);
