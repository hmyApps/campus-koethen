// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/cache/hive_content_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// A payload comfortably past [kCacheDecodeIsolateThreshold], so the read
/// takes the background path.
Map<String, dynamic> _largePayload() => <String, dynamic>{
  'articles': <Map<String, dynamic>>[
    for (int i = 0; i < 400; i++)
      <String, dynamic>{
        'slug': 'artikel-$i',
        'title': 'Überschrift $i',
        'body':
            'Ein Absatz mit genug Text, um das Dokument wachsen zu lassen. '
                'Wiederholt, damit die Schwelle real überschritten wird. ' *
            2,
      },
  ],
};

void main() {
  late Directory directory;
  late Box<String> box;
  late HiveContentCache cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('content-cache-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<String>('content-cache-test');
    cache = HiveContentCache(box);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('a small document round-trips on the direct path', () async {
    await cache.write('small', <String, dynamic>{
      'data': <String>['a', 'b'],
    });

    final CacheEntry? entry = await cache.read('small');

    expect(entry, isNotNull);
    expect(entry!.payload['data'], <String>['a', 'b']);
    expect(box.get('small')!.length, lessThan(kCacheDecodeIsolateThreshold));
  });

  test('a large document round-trips through the background isolate', () async {
    final Map<String, dynamic> payload = _largePayload();
    await cache.write('large', payload);

    expect(
      box.get('large')!.length,
      greaterThan(kCacheDecodeIsolateThreshold),
      reason: 'the fixture has to cross the threshold to test that path',
    );

    final CacheEntry? entry = await cache.read('large');

    expect(entry, isNotNull);
    expect(
      (entry!.payload['articles'] as List<dynamic>).length,
      (payload['articles'] as List<dynamic>).length,
    );
    expect(
      (entry.payload['articles'] as List<dynamic>).last,
      (payload['articles'] as List<dynamic>).last,
    );
  });

  test('a missing key reads as null', () async {
    expect(await cache.read('nothing'), isNull);
  });

  test('a corrupt entry is dropped rather than thrown', () async {
    await box.put('broken', '{not json');
    expect(await cache.read('broken'), isNull);
  });

  test('an envelope without a payload or a timestamp is dropped', () async {
    await box.put('bare', jsonEncode(<String, dynamic>{'payload': null}));
    expect(await cache.read('bare'), isNull);
  });

  test('evicts the least recently used document at the entry budget', () async {
    DateTime now = DateTime.utc(2026, 10, 1, 12);
    final HiveContentCache bounded = HiveContentCache(
      box,
      now: () => now,
      budget: const ContentCacheBudget(maxEntries: 2, maxBytes: 1024 * 1024),
    );
    await bounded.write('a', <String, dynamic>{'value': 'a'});
    now = now.add(const Duration(minutes: 1));
    await bounded.write('b', <String, dynamic>{'value': 'b'});
    now = now.add(const Duration(minutes: 1));
    expect(await bounded.read('a'), isNotNull);
    now = now.add(const Duration(minutes: 1));

    await bounded.write('c', <String, dynamic>{'value': 'c'});

    expect(await bounded.read('a'), isNotNull);
    expect(await bounded.read('b'), isNull);
    expect(await bounded.read('c'), isNotNull);
    expect((await bounded.stats()).entryCount, 2);
  });

  test('keeps the encrypted-on-disk payload within the byte budget', () async {
    final HiveContentCache bounded = HiveContentCache(
      box,
      budget: const ContentCacheBudget(maxEntries: 20, maxBytes: 900),
    );

    for (int index = 0; index < 8; index++) {
      await bounded.write('entry.$index', <String, dynamic>{
        'value': 'x' * 220,
      });
    }

    final ContentCacheStats stats = await bounded.stats();
    expect(stats.byteCount, lessThanOrEqualTo(900));
    expect(stats.entryCount, lessThan(8));
  });

  test(
    'prunes old range windows but preserves their newest successful entry',
    () async {
      DateTime now = DateTime.utc(2026, 1, 1);
      final HiveContentCache bounded = HiveContentCache(
        box,
        now: () => now,
        budget: const ContentCacheBudget(
          maxEntries: 20,
          maxBytes: 1024 * 1024,
          rangeRetention: Duration(days: 30),
        ),
      );
      const String oldKey = 'timetable.entries.de.group.2025-12-01.2025-12-07';
      const String newestKey =
          'timetable.entries.de.group.2025-12-08.2025-12-14';
      await bounded.write(oldKey, <String, dynamic>{'value': 'old'});
      now = now.add(const Duration(days: 1));
      await bounded.write(newestKey, <String, dynamic>{'value': 'newest'});
      now = now.add(const Duration(days: 40));

      await bounded.prune();

      expect(await bounded.read(oldKey), isNull);
      expect(await bounded.read(newestKey), isNotNull);
    },
  );

  group('decodeCacheDocument', () {
    test('decodes below and above the threshold alike', () async {
      final String small = jsonEncode(<String, dynamic>{'a': 1});
      final String large = jsonEncode(_largePayload());
      expect(large.length, greaterThan(kCacheDecodeIsolateThreshold));

      expect(await decodeCacheDocument(small), <String, dynamic>{'a': 1});
      expect(
        ((await decodeCacheDocument(large))!
            as Map<String, dynamic>)['articles'],
        hasLength(400),
      );
    });

    test('malformed input yields null on both paths', () async {
      expect(await decodeCacheDocument('{nope'), isNull);
      expect(await decodeCacheDocument('{${'"x":1,' * 20000}'), isNull);
    });
  });
}
