// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// A structurally broken response must never replace the last good list
/// (AGENTS.md §4, G-03).
///
/// Every list endpoint of the contract delivers `data` as a JSON array — an
/// empty one when there is nothing to show. The tolerant JSON readers turn
/// anything else (`null`, an object, a string) into an empty list, which used
/// to be cached over the last successful canteen list, news feed, contact
/// list or room catalogue.
library;

import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/network/api_failure.dart';
import 'package:campus_koethen/core/network/cached_endpoint.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/features/canteen/data/canteen_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';

const String _cacheKey = 'canteens.de';

Map<String, dynamic> _canteen(String slug) => <String, dynamic>{
  'slug': slug,
  'displayName': 'Demo-Mensa $slug',
};

/// Serves whatever [body] currently holds, or fails when it is `null`.
class _Server {
  Object? body;
  bool fail = false;

  FakeHttpAdapter get adapter => FakeHttpAdapter((RequestOptions options) {
    if (fail) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return FakeHttpResponse(body);
  });
}

Future<Loaded<List<Canteen>>> _load(_Server server, ContentCache cache) =>
    CachedEndpoint(
      client: fakeApiClient(server.adapter),
      cache: cache,
    ).load<List<Canteen>>(
      path: '/canteens',
      cacheKey: _cacheKey,
      locale: 'de',
      parse: Canteen.listFromJson,
    );

void main() {
  late _Server server;
  late MemoryContentCache cache;

  setUp(() async {
    server = _Server();
    cache = MemoryContentCache();
    // A previous, successful load.
    server.body = envelope(<Object>[_canteen('a'), _canteen('b')]);
    final Loaded<List<Canteen>> first = await _load(server, cache);
    expect(first.value, hasLength(2));
  });

  for (final MapEntry<String, Object?> broken in <String, Object?>{
    'missing': _missing,
    'null': null,
    'an object': <String, dynamic>{'slug': 'a'},
    'a string': 'kaputt',
  }.entries) {
    test(
      '`data` that is ${broken.key} does not overwrite the cached list',
      () async {
        server.body = broken.value == _missing
            ? <String, dynamic>{
                'meta': <String, dynamic>{'resolvedLocale': 'de'},
              }
            : envelope(broken.value);

        final Loaded<List<Canteen>> loaded = await _load(server, cache);

        expect(loaded.fromCache, isTrue);
        expect(loaded.value.map((Canteen c) => c.slug), <String>['a', 'b']);
        final CacheEntry? stored = await cache.read(_cacheKey);
        expect(stored!.payload['data'], hasLength(2));
      },
    );
  }

  test(
    'without a cached list a broken response is an error, not "empty"',
    () async {
      server.body = envelope(null);

      await expectLater(
        _load(server, MemoryContentCache()),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('a legitimately empty list is still accepted and cached', () async {
    server.body = envelope(<Object>[]);

    final Loaded<List<Canteen>> loaded = await _load(server, cache);

    expect(loaded.fromCache, isFalse);
    expect(loaded.value, isEmpty);
    final CacheEntry? stored = await cache.read(_cacheKey);
    expect(stored!.payload['data'], isEmpty);
  });

  test('a broken cached envelope is not served as an empty list', () async {
    // Written before the check existed.
    await cache.write(_cacheKey, <String, dynamic>{
      'data': null,
      'meta': <String, dynamic>{},
    });
    server.fail = true;

    await expectLater(_load(server, cache), throwsA(isA<ApiFailure>()));
  });
}

/// Marks the case where the envelope has no `data` key at all.
const Object _missing = Object();
