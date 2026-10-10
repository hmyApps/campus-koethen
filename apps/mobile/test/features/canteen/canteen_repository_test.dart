// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/features/canteen/data/canteen_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';

void main() {
  group('the requested menu window (G-05)', () {
    late FakeHttpAdapter adapter;

    setUp(() {
      adapter = FakeHttpAdapter(
        (RequestOptions options) => FakeHttpResponse(
          envelope(<String, dynamic>{
            'canteen': <String, dynamic>{
              'slug': 'demo-mensa',
              'displayName': 'Demo-Mensa',
            },
            'days': <Object>[],
          }),
        ),
      );
    });

    Future<Map<String, dynamic>> windowFrom(DateTime from) async {
      await CanteenRepository(
        client: fakeApiClient(adapter),
        cache: SafeContentCache(MemoryContentCache()),
      ).fetchMenu(locale: 'de', slug: 'demo-mensa', from: from);
      return adapter.requests.last.queryParameters;
    }

    test('spans 14 calendar days', () async {
      final Map<String, dynamic> query = await windowFrom(DateTime(2026, 6, 8));

      expect(query['from'], '2026-06-08');
      expect(query['to'], '2026-06-21');
    });

    test('keeps its 14th day across the end of daylight saving time', () async {
      // 25 October 2026 is a 25-hour day in Central Europe. Thirteen times
      // 24 hours from a local midnight before it ends at 23:00 on the 13th
      // day, so the request used to stop one day short. (Only observable when
      // the test runs in a time zone with daylight saving time.)
      final Map<String, dynamic> query = await windowFrom(
        DateTime(2026, 10, 20),
      );

      expect(query['from'], '2026-10-20');
      expect(query['to'], '2026-11-02');
    });

    test('also across the start of daylight saving time', () async {
      final Map<String, dynamic> query = await windowFrom(
        DateTime(2026, 3, 22),
      );

      expect(query['from'], '2026-03-22');
      expect(query['to'], '2026-04-04');
    });
  });
}
