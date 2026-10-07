// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_keys.dart';
import '../../../core/cache/cache_providers.dart';
import '../../../core/cache/content_cache.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/network/api_client.dart';
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
    : _endpoint = CachedEndpoint(client: client, cache: cache);

  final CachedEndpoint _endpoint;

  /// The whole active group list arrives in one response, so the search runs
  /// locally and keeps working offline.
  Future<Loaded<List<TimetableGroup>>> fetchGroups({required String locale}) {
    return _endpoint.load<List<TimetableGroup>>(
      path: '/timetable/groups',
      cacheKey: CacheKeys.timetableGroups(locale),
      locale: locale,
      parse: TimetableGroup.listFromJson,
    );
  }

  Future<Loaded<List<TimetablePeriod>>> fetchPeriods({
    required String locale,
  }) => _endpoint.load<List<TimetablePeriod>>(
    path: '/timetable/periods',
    cacheKey: CacheKeys.timetablePeriods(locale),
    locale: locale,
    parse: TimetablePeriod.listFromJson,
  );

  Future<Loaded<List<TimetableModule>>> fetchModules({
    required String locale,
    required String groupId,
  }) => _endpoint.load<List<TimetableModule>>(
    path: '/timetable/modules',
    cacheKey: CacheKeys.timetableModules(locale, groupId),
    locale: locale,
    query: <String, Object?>{'groupId': groupId},
    parse: TimetableModule.listFromJson,
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
