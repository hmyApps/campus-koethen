// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../network/json.dart';
import 'cache_keys.dart';
import 'content_cache.dart';

/// `hive_ce` backed [ContentCache].
///
/// Documents are stored as JSON strings. That keeps the box free of custom
/// type adapters (no build_runner, no generated files) and makes a corrupted
/// entry a local, recoverable problem: it is dropped on read.
class HiveContentCache implements ContentCache {
  HiveContentCache(
    this._box, {
    DateTime Function()? now,
    this.budget = const ContentCacheBudget(),
  }) : _now = now ?? DateTime.now,
       assert(budget.maxEntries > 0 && budget.maxBytes > 0);

  static const String boxName = 'campus_content_cache_v1';
  static const String _payloadKey = 'payload';
  static const String _cachedAtKey = 'cachedAt';
  static const String _accessedAtKey = 'accessedAt';
  static const String _namespaceKey = 'namespace';
  static const String _accessMetadataKey = '__access.v1';

  final Box<String> _box;
  final DateTime Function() _now;
  final ContentCacheBudget budget;

  /// Opens the cache box. Returns a [MemoryContentCache] when Hive is not
  /// usable on this device, so the app keeps working without persistence.
  static Future<ContentCache> open() async {
    try {
      await Hive.initFlutter();
      final Box<String> box = await Hive.openBox<String>(boxName);
      await _deleteLegacyNewsKeys(box);
      final HiveContentCache cache = HiveContentCache(box);
      await cache.prune();
      return SafeContentCache(cache);
    } catch (_) {
      return SafeContentCache(MemoryContentCache());
    }
  }

  /// One-time, idempotent cleanup of every `news.*` entry left over from the
  /// News → Posts rename. Only entries with that prefix are touched — every
  /// other module's cache entries in this shared box are left alone. Safe to
  /// run on every open: after the first successful run there is nothing left
  /// to delete.
  static Future<void> _deleteLegacyNewsKeys(Box<String> box) async {
    final List<String> legacyKeys = box.keys
        .whereType<String>()
        .where(CacheKeys.isLegacyNewsKey)
        .toList(growable: false);
    if (legacyKeys.isNotEmpty) await box.deleteAll(legacyKeys);
  }

  @override
  Future<CacheEntry?> read(String key) async {
    final String? raw = _box.get(key);
    if (raw == null) return null;
    final Map<String, dynamic>? envelope = asJsonMap(
      await decodeCacheDocument(raw),
    );
    if (envelope == null) return null;
    final Map<String, dynamic>? payload = asJsonMap(envelope[_payloadKey]);
    final DateTime? cachedAt = asDateTime(envelope[_cachedAtKey]);
    if (payload == null || cachedAt == null) {
      await _box.delete(key);
      return null;
    }
    await _touch(key, _now().toUtc());
    return CacheEntry(payload: payload, cachedAt: cachedAt);
  }

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {
    final DateTime now = _now().toUtc();
    final String raw = jsonEncode(<String, dynamic>{
      _cachedAtKey: now.toIso8601String(),
      _accessedAtKey: now.toIso8601String(),
      _namespaceKey: CacheKeys.namespaceOf(key),
      _payloadKey: payload,
    });
    // An entry that cannot fit must not evict a previously useful successful
    // response only to be deleted itself by the same budget pass.
    if (_byteLength(raw) > budget.maxBytes) return;
    await _box.put(key, raw);
    await _touch(key, now);
    await prune();
  }

  @override
  Future<void> delete(String key) async {
    await _box.delete(key);
    final Map<String, String> access = _readAccessMetadata();
    if (access.remove(key) != null) await _writeAccessMetadata(access);
  }

  Future<ContentCacheStats> stats() async {
    int bytes = 0;
    int entries = 0;
    for (final MapEntry<dynamic, String> entry in _box.toMap().entries) {
      if (entry.key == _accessMetadataKey) continue;
      entries++;
      bytes += _byteLength(entry.value);
    }
    return ContentCacheStats(entryCount: entries, byteCount: bytes);
  }

  Future<void> prune() async {
    final DateTime now = _now().toUtc();
    final Map<String, String> access = _readAccessMetadata();
    final List<_CacheRecord> records = <_CacheRecord>[];
    final List<String> invalid = <String>[];
    for (final String key in _box.keys.whereType<String>()) {
      if (key == _accessMetadataKey) continue;
      final String? raw = _box.get(key);
      if (raw == null) continue;
      final Map<String, dynamic>? envelope = asJsonMap(
        await decodeCacheDocument(raw),
      );
      final DateTime? cachedAt = envelope == null
          ? null
          : asDateTime(envelope[_cachedAtKey]);
      if (envelope == null ||
          cachedAt == null ||
          asJsonMap(envelope[_payloadKey]) == null) {
        invalid.add(key);
        continue;
      }
      final DateTime accessedAt =
          DateTime.tryParse(access[key] ?? '') ??
          asDateTime(envelope[_accessedAtKey]) ??
          cachedAt;
      final String namespace =
          (envelope[_namespaceKey] as String?) ?? CacheKeys.namespaceOf(key);
      records.add(
        _CacheRecord(
          key: key,
          byteCount: _byteLength(raw),
          cachedAt: cachedAt,
          accessedAt: accessedAt,
          namespace: namespace,
        ),
      );
    }
    if (invalid.isNotEmpty) {
      await _box.deleteAll(invalid);
      for (final String key in invalid) {
        access.remove(key);
      }
    }

    final Set<String> remove = <String>{};
    final List<_CacheRecord> ranges = records
        .where(
          (_CacheRecord record) => CacheKeys.isRangeNamespace(record.namespace),
        )
        .toList();
    final Map<String, _CacheRecord> newestByScope = <String, _CacheRecord>{};
    for (final _CacheRecord record in ranges) {
      final String scope = CacheKeys.rangeScopeOf(record.key);
      final _CacheRecord? current = newestByScope[scope];
      if (current == null || record.cachedAt.isAfter(current.cachedAt)) {
        newestByScope[scope] = record;
      }
    }
    for (final _CacheRecord record in ranges) {
      final bool isNewest = identical(
        newestByScope[CacheKeys.rangeScopeOf(record.key)],
        record,
      );
      if (!isNewest &&
          now.difference(record.cachedAt) > budget.rangeRetention) {
        remove.add(record.key);
      }
    }

    final List<_CacheRecord> liveRanges =
        ranges
            .where((_CacheRecord record) => !remove.contains(record.key))
            .toList()
          ..sort(_leastRecentlyUsedFirst);
    while (liveRanges.length > budget.maxRangeEntries) {
      remove.add(liveRanges.removeAt(0).key);
    }

    final List<_CacheRecord> live =
        records
            .where((_CacheRecord record) => !remove.contains(record.key))
            .toList()
          ..sort(_leastRecentlyUsedFirst);
    int bytes = live.fold<int>(
      0,
      (int total, _CacheRecord record) => total + record.byteCount,
    );
    while (live.length > budget.maxEntries || bytes > budget.maxBytes) {
      final _CacheRecord evicted = live.removeAt(0);
      remove.add(evicted.key);
      bytes -= evicted.byteCount;
    }
    if (remove.isNotEmpty) {
      await _box.deleteAll(remove);
      for (final String key in remove) {
        access.remove(key);
      }
    }
    await _writeAccessMetadata(access);
  }

  Future<void> _touch(String key, DateTime at) async {
    final Map<String, String> access = _readAccessMetadata();
    access[key] = at.toUtc().toIso8601String();
    await _writeAccessMetadata(access);
  }

  Map<String, String> _readAccessMetadata() {
    final String? raw = _box.get(_accessMetadataKey);
    if (raw == null) return <String, String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeAccessMetadata(Map<String, String> access) async {
    if (access.isEmpty) {
      await _box.delete(_accessMetadataKey);
    } else {
      await _box.put(_accessMetadataKey, jsonEncode(access));
    }
  }

  static int _byteLength(String value) => utf8.encode(value).length;

  static int _leastRecentlyUsedFirst(_CacheRecord a, _CacheRecord b) {
    final int access = a.accessedAt.compareTo(b.accessedAt);
    return access != 0 ? access : a.key.compareTo(b.key);
  }
}

class _CacheRecord {
  const _CacheRecord({
    required this.key,
    required this.byteCount,
    required this.cachedAt,
    required this.accessedAt,
    required this.namespace,
  });

  final String key;
  final int byteCount;
  final DateTime cachedAt;
  final DateTime accessedAt;
  final String namespace;
}

/// Above this many characters a cached document is decoded in its own isolate.
///
/// The network path already works this way: dio's default transformer moves
/// any JSON response past 50 KB off the UI isolate, because below that the
/// decode is a couple of milliseconds and above it the frame is gone. The
/// cache carries exactly the same documents — the news page with every
/// article's content blocks, a calendar month, a canteen plan — but decoded
/// them on the UI isolate, on the one path where it matters most: the cold
/// start and the offline read, immediately before the first frame.
///
/// Writing keeps the direct path. Handing the payload to an isolate would copy
/// the whole map there and the encoded string back, which costs about as much
/// as the encode itself, and there is no cheap way to know the size before
/// encoding.
@visibleForTesting
const int kCacheDecodeIsolateThreshold = 50 * 1024;

/// Decodes one cached document, off the UI isolate when it is large enough to
/// be worth it.
///
/// A malformed entry yields `null` rather than throwing — the same contract
/// [ContentCache] states: a cache is an optimisation and degrades to a plain
/// network fetch, it never takes down a screen.
@visibleForTesting
Future<Object?> decodeCacheDocument(String raw) async {
  try {
    if (raw.length < kCacheDecodeIsolateThreshold) return jsonDecode(raw);
    return await compute(jsonDecode, raw);
  } catch (_) {
    return null;
  }
}
