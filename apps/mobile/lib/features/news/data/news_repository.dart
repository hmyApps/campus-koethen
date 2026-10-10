// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_keys.dart';
import '../../../core/cache/cache_providers.dart';
import '../../../core/cache/content_cache.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/cached_endpoint.dart';
import '../../../core/network/loaded.dart';
import '../../../core/network/network_providers.dart';
import 'news_models.dart';

/// Reads post content (news articles and event posts) from the Campus API
/// with a transparent offline cache.
class NewsRepository {
  NewsRepository({required ApiClient client, required ContentCache cache})
    : _endpoint = CachedEndpoint(client: client, cache: cache);

  final CachedEndpoint _endpoint;

  Future<Loaded<List<NewsChannel>>> fetchChannels({
    required String locale,
  }) async {
    return _endpoint.load<List<NewsChannel>>(
      path: '/posts/channels',
      cacheKey: CacheKeys.postsChannels(locale),
      locale: locale,
      parse: NewsChannel.listFromJson,
    );
  }

  Future<Loaded<List<NewsTag>>> fetchTags({required String locale}) async {
    return _endpoint.load<List<NewsTag>>(
      path: '/posts/tags',
      cacheKey: CacheKeys.postsTags(locale),
      locale: locale,
      parse: NewsTag.listFromJson,
    );
  }

  /// Loads a page of the news list.
  ///
  /// [channelsParameter] follows the API contract exactly:
  /// `null` omits the parameter (all channels), `''` sends it empty
  /// (deliberately no channels), otherwise a CSV of slugs.
  ///
  /// [tagsParameter] follows the same shape but a different meaning, per the
  /// API contract: `null` omits the parameter (no tag filter at all), `''`
  /// sends it empty (deliberately zero tags — an empty result), otherwise a
  /// CSV of slugs. It combines with [channelsParameter] by AND, never OR: a
  /// tag is a content filter, not a second subscription gate.
  Future<Loaded<NewsPage>> fetchArticles({
    required String locale,
    required String? channelsParameter,
    String? tagsParameter,
    int page = 1,
    int pageSize = 20,
  }) async {
    final Loaded<List<NewsArticle>>
    loaded = await _endpoint.load<List<NewsArticle>>(
      path: '/posts',
      cacheKey: CacheKeys.postsFirstPage(
        locale,
        channelsParameter == null || channelsParameter.isEmpty
            ? const <String>[]
            : channelsParameter.split(','),
        tagsParameter == null || tagsParameter.isEmpty
            ? const <String>[]
            : tagsParameter.split(','),
      ),
      locale: locale,
      query: <String, Object?>{
        'channels': channelsParameter,
        'tags': tagsParameter,
        'page': page,
        'pageSize': pageSize,
      },
      parse: NewsArticle.listFromJson,
      // Only the first page is cached; deeper pages always need the network.
      allowCacheFallback: page == 1,
      writeToCache: page == 1,
    );

    return loaded.map(
      (List<NewsArticle> articles) => NewsPage(
        articles: articles,
        page: loaded.meta.pagination?.page ?? page,
        totalPages: loaded.meta.pagination?.totalPages ?? page,
      ),
    );
  }

  /// Loads one page of `GET /v1/posts/events`.
  ///
  /// The client never sends its own default `from`/`to`: when both are
  /// omitted the server resolves its own environment-configured window, and
  /// the caller reads it back from [NewsPage.from]/[NewsPage.to] (sourced
  /// from `meta.from`/`meta.to`) to build the cache key and reconcile the
  /// saved list — never from the request it sent.
  Future<Loaded<NewsPage>> fetchEventPosts({
    required String locale,
    String? channelsParameter,
    String? from,
    String? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    final Loaded<List<NewsArticle>> loaded = await _endpoint
        .load<List<NewsArticle>>(
          path: '/posts/events',
          // The window bounds are not known before the first response, so
          // page 1 is keyed by the request bounds (both null on the common
          // path) — a later page reads the resolved bounds via [from]/[to].
          cacheKey: CacheKeys.postEvents(
            locale: locale,
            channels: channelsParameter == null || channelsParameter.isEmpty
                ? const <String>[]
                : channelsParameter.split(','),
            page: page,
            from: from ?? '-',
            to: to ?? '-',
          ),
          locale: locale,
          query: <String, Object?>{
            'channels': channelsParameter,
            'from': from,
            'to': to,
            'page': page,
            'pageSize': pageSize,
          },
          parse: NewsArticle.listFromJson,
          // Only page 1 has a cache fallback, so only page 1 is stored: a
          // later page would never be read back and would merely take a slot
          // in the range budget it shares with timetable and calendar weeks
          // (VG-N02).
          allowCacheFallback: page == 1,
          writeToCache: page == 1,
        );

    return loaded.map(
      (List<NewsArticle> articles) => NewsPage(
        articles: articles,
        page: loaded.meta.pagination?.page ?? page,
        totalPages: loaded.meta.pagination?.totalPages ?? page,
        from: loaded.meta.from,
        to: loaded.meta.to,
      ),
    );
  }
}

final Provider<NewsRepository> newsRepositoryProvider =
    Provider<NewsRepository>(
      (Ref ref) => NewsRepository(
        client: ref.watch(apiClientProvider),
        cache: ref.watch(contentCacheProvider),
      ),
    );
