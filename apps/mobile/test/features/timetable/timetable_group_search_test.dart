// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/cache_providers.dart';
import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerFor(FakeHttpAdapter adapter) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        contentCacheProvider.overrideWithValue(
          SafeContentCache(MemoryContentCache()),
        ),
        apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('server search appends every page without repeating a group', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
      final int page = options.queryParameters['page'] as int;
      return FakeHttpResponse(
        envelope(
          <Object>[
            <String, dynamic>{
              'id': page == 1 ? 'group-1' : 'group-2',
              'shortName': page == 1 ? 'INF 24' : 'INF 25',
            },
          ],
          meta: <String, dynamic>{
            'pagination': <String, dynamic>{
              'page': page,
              'pageSize': 50,
              'total': 2,
              'totalPages': 2,
            },
          },
        ),
      );
    });
    final ProviderContainer container = containerFor(adapter);
    final provider = timetableGroupSearchProvider(' inf ');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(provider.future);
    await container.read(provider.notifier).loadMore();

    expect(
      container.read(provider).requireValue.groups.map((group) => group.id),
      <String>['group-1', 'group-2'],
    );
    expect(adapter.queries, hasLength(2));
    expect(
      adapter.queries.every((query) => query.contains('query=inf')),
      isTrue,
    );
    expect(adapter.queries.last, contains('page=2'));
  });

  test(
    'a failed next page keeps the first page and exposes retry state',
    () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        final int page = options.queryParameters['page'] as int;
        if (page == 2) throw Exception('offline');
        return FakeHttpResponse(
          envelope(
            <Object>[
              <String, dynamic>{'id': 'group-1', 'shortName': 'INF 24'},
            ],
            meta: <String, dynamic>{
              'pagination': <String, dynamic>{
                'page': 1,
                'pageSize': 50,
                'total': 2,
                'totalPages': 2,
              },
            },
          ),
        );
      });
      final ProviderContainer container = containerFor(adapter);
      final provider = timetableGroupSearchProvider('');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      await container.read(provider.future);
      await container.read(provider.notifier).loadMore();

      final TimetableGroupSearchState state = container
          .read(provider)
          .requireValue;
      expect(state.groups.single.id, 'group-1');
      expect(state.loadMoreFailed, isTrue);
      expect(state.isLoadingMore, isFalse);
    },
  );

  test(
    'cold refresh without a selection requests status, not catalogue',
    () async {
      final List<String> paths = <String>[];
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        paths.add(options.path);
        return FakeHttpResponse(
          envelope(<String, dynamic>{
            'featureEnabled': true,
            'groupCount': 503,
            'coveredFrom': '2026-10-01',
            'coveredTo': '2027-04-01',
          }),
        );
      });
      final ProviderContainer container = containerFor(adapter);

      await container.read(timetableForegroundRefreshProvider)();

      expect(paths, <String>['/timetable/status']);
    },
  );
}
