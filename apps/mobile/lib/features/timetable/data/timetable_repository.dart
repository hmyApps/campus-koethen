// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_keys.dart';
import '../../../core/cache/cache_providers.dart';
import '../../../core/cache/content_cache.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_meta.dart';
import '../../../core/network/cached_endpoint.dart';
import '../../../core/network/loaded.dart';
import '../../../core/network/network_providers.dart';
import 'timetable_models.dart';

/// Reads timetable data from the Campus API with a transparent offline cache.
///
/// The app talks **exclusively** to `/v1` of the Campus API. It knows no
/// upstream address, no upstream header and no upstream identifier; the group
/// id used here is the Campus UUID from the contract.
class TimetableRepository {
  TimetableRepository({required ApiClient client, required ContentCache cache})
    : _cache = cache,
      _endpoint = CachedEndpoint(client: client, cache: cache);

  final ContentCache _cache;
  final CachedEndpoint _endpoint;

  static const int groupPageSize = 50;

  /// Loads one bounded picker page. Search is evaluated by the server so the
  /// result remains complete even when the catalogue grows beyond one page.
  Future<Loaded<List<TimetableGroup>>> fetchGroups({
    required String locale,
    String query = '',
    int page = 1,
    int pageSize = groupPageSize,
  }) {
    final String normalizedQuery = query.trim();
    final bool cacheable = page == 1 && normalizedQuery.isEmpty;
    return _endpoint.load<List<TimetableGroup>>(
      path: '/timetable/groups',
      cacheKey: cacheable
          ? CacheKeys.timetableGroups(locale)
          : 'timetable.groups.uncached',
      locale: locale,
      query: <String, Object?>{
        'page': page,
        'pageSize': pageSize,
        if (normalizedQuery.isNotEmpty) 'query': normalizedQuery,
      },
      parse: TimetableGroup.listFromJson,
      allowCacheFallback: cacheable,
      writeToCache: cacheable,
    );
  }

  /// Resolves exactly one persisted Campus UUID without loading the catalogue.
  Future<Loaded<TimetableGroup>> fetchGroup({
    required String locale,
    required String groupId,
  }) => _endpoint.load<TimetableGroup>(
    path: '/timetable/groups/$groupId',
    cacheKey: CacheKeys.timetableGroup(locale, groupId),
    locale: locale,
    parse: (Object? data) {
      final TimetableGroup? group = TimetableGroup.fromJson(data);
      if (group == null) {
        throw const FormatException('Malformed timetable group payload');
      }
      return group;
    },
  );

  Future<Loaded<TimetableStatus>> fetchStatus({required String locale}) =>
      _endpoint.load<TimetableStatus>(
        path: '/timetable/status',
        cacheKey: CacheKeys.timetableStatus(locale),
        locale: locale,
        parse: TimetableStatus.fromJson,
      );

  /// Persists a group selected from a non-cacheable search result immediately.
  Future<void> rememberGroup({
    required String locale,
    required TimetableGroup group,
    required ApiMeta meta,
  }) => _cache.write(
    CacheKeys.timetableGroup(locale, group.id),
    <String, dynamic>{'data': group.toJson(), 'meta': meta.toJson()},
  );

  Future<Loaded<TimetableLessonInfoOptions>> fetchLessonInfo({
    required String locale,
    required String groupId,
  }) => _endpoint.load<TimetableLessonInfoOptions>(
    path: '/timetable/lesson-info',
    cacheKey: CacheKeys.timetableLessonInfo(locale, groupId),
    locale: locale,
    query: <String, Object?>{'groupId': groupId},
    parse: TimetableLessonInfoOptions.fromJson,
  );

  /// Loads one closed date range. [from] and [to] are inclusive calendar days.
  Future<Loaded<Timetable>> fetchEntries({
    required String locale,
    required String groupId,
    required DateTime from,
    required DateTime to,
  }) {
    final String fromIso = AppDateFormats.isoDate(from);
    final String toIso = AppDateFormats.isoDate(to);
    return _endpoint.load<Timetable>(
      path: '/timetable/entries',
      cacheKey: CacheKeys.timetableEntries(
        locale: locale,
        groupId: groupId,
        from: fromIso,
        to: toIso,
      ),
      locale: locale,
      query: <String, Object?>{
        'groupId': groupId,
        'from': fromIso,
        'to': toIso,
      },
      parse: (Object? data) {
        final Timetable? timetable = Timetable.fromJson(data);
        if (timetable == null) {
          throw const FormatException('Malformed timetable payload');
        }
        return timetable;
      },
    );
  }
}

final Provider<TimetableRepository> timetableRepositoryProvider =
    Provider<TimetableRepository>(
      (Ref ref) => TimetableRepository(
        client: ref.watch(apiClientProvider),
        cache: ref.watch(contentCacheProvider),
      ),
    );
