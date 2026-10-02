// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../cache/content_cache.dart';
import 'api_client.dart';
import 'api_meta.dart';
import 'json.dart';
import 'loaded.dart';

/// Fetches an endpoint and keeps its raw envelope in the content cache.
///
/// The cache stores the untouched `{ data, meta }` envelope, so a cached read
/// goes through exactly the same parser as a live read. Cache access is
/// wrapped in [SafeContentCache] by construction, therefore a broken cache
/// degrades this call to a plain network fetch instead of failing.
class CachedEndpoint {
  const CachedEndpoint({required this.client, required this.cache});

  final ApiClient client;
  final ContentCache cache;

  Future<Loaded<T>> load<T>({
    required String path,
    required String cacheKey,
    required T Function(Object? data) parse,
    Map<String, Object?> query = const <String, Object?>{},
    String? locale,

    /// Whether a network failure may read the document stored at [cacheKey].
    bool allowCacheFallback = true,

    /// Whether a successful network response may replace [cacheKey].
    ///
    /// This is intentionally independent from [allowCacheFallback]: callers
    /// such as paginated feeds can disable both for every page after page one.
    bool writeToCache = true,
    Duration? freshFor,
  }) async {
    if (freshFor != null) {
      final Loaded<T>? cached = await _readCache<T>(
        cacheKey,
        parse,
        fromCache: false,
      );
      final DateTime? cachedAt = cached?.cachedAt;
      if (cached != null &&
          cachedAt != null &&
          DateTime.now().difference(cachedAt) < freshFor) {
        return cached;
      }
    }

    try {
      final ApiResponse<Object?> response = await client.get<Object?>(
        path,
        parse: (Object? data) => data,
        query: query,
        locale: locale,
      );
      final Loaded<T> loaded = Loaded<T>(
        value: parse(response.data),
        meta: response.meta,
      );
      // Storing is best effort and happens *after* the value was parsed, so a
      // failing cache can never turn a good network response into an error.
      if (writeToCache) await _writeCache(cacheKey, response);
      return loaded;
    } catch (error) {
      if (!allowCacheFallback) rethrow;
      final Loaded<T>? cached = await _readCache<T>(cacheKey, parse);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<void> _writeCache(
    String cacheKey,
    ApiResponse<Object?> response,
  ) async {
    try {
      await cache.write(cacheKey, <String, dynamic>{
        'data': response.data,
        'meta': response.meta.toJson(),
      });
    } catch (_) {
      // A cache that refuses to store is an optimisation that is unavailable,
      // never a user visible error.
    }
  }

  Future<Loaded<T>?> _readCache<T>(
    String cacheKey,
    T Function(Object? data) parse, {
    bool fromCache = true,
  }) async {
    try {
      final CacheEntry? entry = await cache.read(cacheKey);
      if (entry == null) return null;
      return Loaded<T>(
        value: parse(entry.payload['data']),
        meta: ApiMeta.fromJson(asJsonMap(entry.payload['meta'])),
        // A document inside an explicit freshness window is the current value
        // according to that endpoint's refresh policy, not an offline
        // fallback. Older documents are still marked as cached when the
        // network request fails, so the UI keeps its stale/offline notice.
        fromCache: fromCache,
        cachedAt: entry.cachedAt,
      );
    } catch (_) {
      // An unreadable or no longer parseable cache entry is simply ignored;
      // the caller falls back to the original network error.
      return null;
    }
  }
}
