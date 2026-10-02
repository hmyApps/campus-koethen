// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// A cached JSON document together with the time it was stored.
class CacheEntry {
  const CacheEntry({required this.payload, required this.cachedAt});

  final Map<String, dynamic> payload;
  final DateTime cachedAt;
}

class ContentCacheBudget {
  const ContentCacheBudget({
    this.maxEntries = 128,
    this.maxBytes = 20 * 1024 * 1024,
    this.maxRangeEntries = 24,
    this.rangeRetention = const Duration(days: 90),
  });

  final int maxEntries;
  final int maxBytes;
  final int maxRangeEntries;
  final Duration rangeRetention;
}

class ContentCacheStats {
  const ContentCacheStats({required this.entryCount, required this.byteCount});

  final int entryCount;
  final int byteCount;
}

/// Persistent cache for content documents.
///
/// Implementations **must not** throw. A cache is an optimisation: when it
/// fails the app degrades to a plain network fetch, it never crashes. The
/// [SafeContentCache] decorator enforces that contract for any implementation.
abstract interface class ContentCache {
  Future<CacheEntry?> read(String key);

  Future<void> write(String key, Map<String, dynamic> payload);

  Future<void> delete(String key);
}

/// Wraps any [ContentCache] and swallows every error.
///
/// This is the single place where cache resilience is guaranteed, so no
/// repository needs its own try/catch.
class SafeContentCache implements ContentCache {
  const SafeContentCache(this._inner);

  final ContentCache _inner;

  @override
  Future<CacheEntry?> read(String key) async {
    try {
      return await _inner.read(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {
    try {
      await _inner.write(key, payload);
    } catch (_) {
      // Losing a cache write is acceptable; losing the screen is not.
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _inner.delete(key);
    } catch (_) {
      // See write.
    }
  }
}

/// In-memory cache. Used as the fallback when hive_ce cannot be opened and in
/// tests that do not care about persistence.
class MemoryContentCache implements ContentCache {
  final Map<String, CacheEntry> _entries = <String, CacheEntry>{};

  @override
  Future<CacheEntry?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {
    _entries[key] = CacheEntry(payload: payload, cachedAt: DateTime.now());
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }
}
