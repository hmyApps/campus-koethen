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
import 'canteen_models.dart';

/// Reads canteen data from the Campus API with a transparent offline cache.
///
/// The cached window is the current plus the upcoming week (14 days), which is
/// exactly the API's default range.
class CanteenRepository {
  CanteenRepository({required ApiClient client, required ContentCache cache})
    : _endpoint = CachedEndpoint(client: client, cache: cache);

  /// Number of days the app requests and caches, starting today.
  static const int cachedWindowDays = 14;

  final CachedEndpoint _endpoint;

  Future<Loaded<List<Canteen>>> fetchCanteens({required String locale}) {
    return _endpoint.load<List<Canteen>>(
      path: '/canteens',
      cacheKey: CacheKeys.canteens(locale),
      locale: locale,
      parse: Canteen.listFromJson,
    );
  }

  Future<Loaded<CanteenMenu>> fetchMenu({
    required String locale,
    required String slug,
    DateTime? from,
  }) {
    final DateTime start = _atMidnight(from ?? DateTime.now());
    // Calendar days, not 24-hour blocks: across the end of daylight saving
    // time `add(Duration(days: 13))` lands at 23:00 on the 13th day and the
    // window lost its last day (G-05). The constructor normalises overflow.
    final DateTime end = DateTime(
      start.year,
      start.month,
      start.day + cachedWindowDays - 1,
    );
    return _endpoint.load<CanteenMenu>(
      path: '/canteens/$slug/menu',
      cacheKey: CacheKeys.canteenMenu(locale, slug),
      locale: locale,
      query: <String, Object?>{
        'from': AppDateFormats.isoDate(start),
        'to': AppDateFormats.isoDate(end),
      },
      parse: (Object? data) {
        final CanteenMenu? menu = CanteenMenu.fromJson(data);
        if (menu == null) {
          throw const FormatException('Malformed canteen menu payload');
        }
        return menu;
      },
    );
  }

  static DateTime _atMidnight(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

final Provider<CanteenRepository> canteenRepositoryProvider =
    Provider<CanteenRepository>(
      (Ref ref) => CanteenRepository(
        client: ref.watch(apiClientProvider),
        cache: ref.watch(contentCacheProvider),
      ),
    );
