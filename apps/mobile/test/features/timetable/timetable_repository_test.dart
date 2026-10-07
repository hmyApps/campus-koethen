// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/network/api_failure.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:campus_koethen/features/timetable/data/timetable_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/fixtures.dart';

final DateTime _monday = DateTime(2026, 7, 20);
final DateTime _sunday = DateTime(2026, 7, 26);

TimetableRepository buildRepository(
  FakeHttpAdapter adapter, {
  ContentCache? cache,
}) {
  return TimetableRepository(
    client: fakeApiClient(adapter),
    cache: cache ?? SafeContentCache(MemoryContentCache()),
  );
}

FakeHttpAdapter workingApi({DateTime? monday, Map<String, dynamic>? meta}) {
  return FakeHttpAdapter((RequestOptions options) {
    if (options.path.endsWith('/timetable/groups')) {
      return FakeHttpResponse(envelope(timetableGroupsFixture));
    }
    if (options.path.endsWith('/timetable/periods')) {
      return FakeHttpResponse(
        envelope(<Object>[
          <String, Object>{
            'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'name': '2026/2027',
            'validFrom': '2026-10-05',
            'validTo': '2027-03-31',
            'groups': timetableGroupsFixture,
          },
        ]),
      );
    }
    if (options.path.endsWith('/timetable/modules')) {
      return FakeHttpResponse(
        envelope(<Object>[
          <String, Object?>{'subjectCode': 'MATH2', 'title': 'Mathematik 2'},
        ]),
      );
    }
    return FakeHttpResponse(
      envelope(
        timetableWeekFixture(monday ?? _monday),
        meta: meta ?? timetableMeta(),
      ),
    );
  });
}

void main() {
  group('fetchGroups', () {
    test('reads the group list and sends the locale', () async {
      final FakeHttpAdapter adapter = workingApi();

      final Loaded<List<TimetableGroup>> loaded = await buildRepository(
        adapter,
      ).fetchGroups(locale: 'en');

      expect(loaded.value, hasLength(3));
      expect(loaded.fromCache, isFalse);
      expect(adapter.requests.single.path, '/timetable/groups');
      expect(adapter.queries.single, contains('locale=en'));
    });

    test('never sends an upstream identifier', () async {
      final FakeHttpAdapter adapter = workingApi();

      await buildRepository(adapter).fetchGroups(locale: 'de');

      expect(adapter.queries.single, isNot(contains('school')));
      expect(adapter.queries.single, isNot(contains('untis')));
    });
  });

  group('fetchPeriods', () {
    test('reads semester dates and Campus groups', () async {
      final FakeHttpAdapter adapter = workingApi();
      final Loaded<List<TimetablePeriod>> loaded = await buildRepository(
        adapter,
      ).fetchPeriods(locale: 'de');

      expect(loaded.value.single.name, '2026/2027');
      expect(loaded.value.single.validFrom, DateTime(2026, 10, 5));
      expect(loaded.value.single.groups, hasLength(3));
      expect(adapter.requests.single.path, '/timetable/periods');
    });
  });

  group('fetchModules', () {
    test('reads modules for exactly one Campus group', () async {
      final FakeHttpAdapter adapter = workingApi();
      final Loaded<List<TimetableModule>> loaded = await buildRepository(
        adapter,
      ).fetchModules(locale: 'de', groupId: timetableGroupIdFixture);

      expect(loaded.value.single.moduleKey, 'code:MATH2');
      expect(adapter.requests.single.path, '/timetable/modules');
      expect(
        adapter.queries.single,
        contains('groupId=$timetableGroupIdFixture'),
      );
    });
  });

  group('fetchEntries', () {
    test(
      'sends groupId, from and to exactly as the contract requires',
      () async {
        final FakeHttpAdapter adapter = workingApi();

        await buildRepository(adapter).fetchEntries(
          locale: 'de',
          groupId: timetableGroupIdFixture,
          from: _monday,
          to: _sunday,
        );

        final String query = adapter.queries.single;
        expect(adapter.requests.single.path, '/timetable/entries');
        expect(
          Uri.decodeQueryComponent(
            RegExp(r'groupId=([^&]*)').firstMatch(query)!.group(1)!,
          ),
          timetableGroupIdFixture,
        );
        expect(query, contains('from=2026-07-20'));
        expect(query, contains('to=2026-07-26'));
        expect(query, contains('locale=de'));
      },
    );

    test('exposes featureEnabled and dataState from the meta block', () async {
      final Loaded<Timetable> loaded =
          await buildRepository(
            workingApi(meta: timetableMeta(dataState: 'pending')),
          ).fetchEntries(
            locale: 'de',
            groupId: timetableGroupIdFixture,
            from: _monday,
            to: _sunday,
          );

      expect(loaded.meta.featureEnabled, isTrue);
      expect(
        TimetableDataState.fromWire(loaded.meta.dataState),
        TimetableDataState.pending,
      );
    });

    test('reports a disabled feature without failing', () async {
      final Loaded<Timetable> loaded =
          await buildRepository(
            workingApi(
              meta: timetableMeta(
                featureEnabled: false,
                dataState: 'unavailable',
                lastSuccessfulSyncAt: null,
              ),
            ),
          ).fetchEntries(
            locale: 'de',
            groupId: timetableGroupIdFixture,
            from: _monday,
            to: _sunday,
          );

      expect(loaded.meta.featureEnabled, isFalse);
      expect(
        TimetableDataState.fromWire(loaded.meta.dataState),
        TimetableDataState.unavailable,
      );
      expect(loaded.meta.lastSuccessfulSyncAt, isNull);
    });

    test('maps an unknown group to a not-found failure', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions _) => const FakeHttpResponse(<String, dynamic>{
          'error': <String, dynamic>{
            'status': 404,
            'code': 'TIMETABLE_GROUP_NOT_FOUND',
            'message': 'nicht gefunden',
          },
        }, statusCode: 404),
      );

      await expectLater(
        buildRepository(adapter).fetchEntries(
          locale: 'de',
          groupId: 'missing',
          from: _monday,
          to: _sunday,
        ),
        throwsA(
          isA<ApiFailure>()
              .having(
                (ApiFailure failure) => failure.kind,
                'kind',
                ApiFailureKind.notFound,
              )
              .having(
                (ApiFailure failure) => failure.code,
                'code',
                'TIMETABLE_GROUP_NOT_FOUND',
              ),
        ),
      );
    });
  });

  group('offline cache', () {
    test('serves the last successful week when the network fails', () async {
      bool offline = false;
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        if (offline) throw Exception('offline');
        return FakeHttpResponse(
          envelope(timetableWeekFixture(_monday), meta: timetableMeta()),
        );
      });
      final TimetableRepository repository = buildRepository(adapter);

      final Loaded<Timetable> live = await repository.fetchEntries(
        locale: 'de',
        groupId: timetableGroupIdFixture,
        from: _monday,
        to: _sunday,
      );
      expect(live.fromCache, isFalse);

      offline = true;
      final Loaded<Timetable> cached = await repository.fetchEntries(
        locale: 'de',
        groupId: timetableGroupIdFixture,
        from: _monday,
        to: _sunday,
      );

      expect(cached.fromCache, isTrue);
      expect(cached.cachedAt, isNotNull);
      expect(cached.value.days.first.entries.first.title, 'Mathematik 2');
      expect(
        cached.meta.featureEnabled,
        isTrue,
        reason: 'the cached envelope keeps its meta block',
      );
    });

    test('rethrows when neither network nor cache can serve', () async {
      final TimetableRepository repository = buildRepository(
        FakeHttpAdapter((RequestOptions _) => throw Exception('offline')),
      );

      await expectLater(
        repository.fetchEntries(
          locale: 'de',
          groupId: timetableGroupIdFixture,
          from: _monday,
          to: _sunday,
        ),
        throwsA(isA<ApiFailure>()),
      );
    });

    test('keeps a separate cache entry per group', () async {
      bool offline = false;
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions _) {
        if (offline) throw Exception('offline');
        return FakeHttpResponse(
          envelope(timetableWeekFixture(_monday), meta: timetableMeta()),
        );
      });
      final TimetableRepository repository = buildRepository(adapter);

      await repository.fetchEntries(
        locale: 'de',
        groupId: timetableGroupIdFixture,
        from: _monday,
        to: _sunday,
      );
      offline = true;

      await expectLater(
        repository.fetchEntries(
          locale: 'de',
          groupId: '22222222-2222-4222-8222-222222222222',
          from: _monday,
          to: _sunday,
        ),
        throwsA(isA<ApiFailure>()),
        reason: 'another group must never be served from a foreign cache entry',
      );
    });

    test('keeps a separate cache entry per week', () async {
      bool offline = false;
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions _) {
        if (offline) throw Exception('offline');
        return FakeHttpResponse(
          envelope(timetableWeekFixture(_monday), meta: timetableMeta()),
        );
      });
      final TimetableRepository repository = buildRepository(adapter);

      await repository.fetchEntries(
        locale: 'de',
        groupId: timetableGroupIdFixture,
        from: _monday,
        to: _sunday,
      );
      offline = true;

      await expectLater(
        repository.fetchEntries(
          locale: 'de',
          groupId: timetableGroupIdFixture,
          from: _monday.add(const Duration(days: 7)),
          to: _sunday.add(const Duration(days: 7)),
        ),
        throwsA(isA<ApiFailure>()),
        reason: 'the next week must not be served from this week\'s cache',
      );
    });

    test('keeps a separate cache entry per locale', () async {
      bool offline = false;
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions _) {
        if (offline) throw Exception('offline');
        return FakeHttpResponse(
          envelope(timetableWeekFixture(_monday), meta: timetableMeta()),
        );
      });
      final TimetableRepository repository = buildRepository(adapter);

      await repository.fetchEntries(
        locale: 'de',
        groupId: timetableGroupIdFixture,
        from: _monday,
        to: _sunday,
      );
      offline = true;

      await expectLater(
        repository.fetchEntries(
          locale: 'en',
          groupId: timetableGroupIdFixture,
          from: _monday,
          to: _sunday,
        ),
        throwsA(isA<ApiFailure>()),
        reason: 'a language switch must never show the other language',
      );
    });

    test('serves the group list from cache when the network fails', () async {
      bool offline = false;
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions _) {
        if (offline) throw Exception('offline');
        return FakeHttpResponse(envelope(timetableGroupsFixture));
      });
      final TimetableRepository repository = buildRepository(adapter);

      await repository.fetchGroups(locale: 'de');
      offline = true;
      final Loaded<List<TimetableGroup>> cached = await repository.fetchGroups(
        locale: 'de',
      );

      expect(cached.fromCache, isTrue);
      expect(cached.value, hasLength(3));
    });
  });
}
