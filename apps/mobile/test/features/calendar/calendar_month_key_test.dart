// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/cache_providers.dart';
import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/time/clock.dart';
import 'package:campus_koethen/features/canteen/application/canteen_providers.dart';
import 'package:campus_koethen/features/calendar/application/calendar_providers.dart';
import 'package:campus_koethen/features/calendar/application/public_calendar_providers.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';

/// The aggregated calendar covers a whole month. Everything below states that
/// the month — not the individual day the caller happens to pass — is what
/// decides how often that month is aggregated and how often its events are
/// fetched. Day-by-day keys made stepping through a week strip repeat both.

Map<String, dynamic> get _calendar => <String, dynamic>{
  'id': 'cal-1',
  'slug': 'campus',
  'name': 'Campus',
  'colorHex': '#5B3FD0',
  'sortOrder': 0,
  'defaultSubscribed': true,
  'dataStale': false,
  'googleOpenUrl': 'https://calendar.google.com/calendar/u/0',
};

void main() {
  // localeCodeProvider reads the platform locale through the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<RequestOptions> requests;

  ProviderContainer container({
    Map<String, dynamic>? catalogueMeta,
    bool lateEvent = false,
    bool truncatedRange = false,
    bool groupEndpointFails = false,
    bool timetableEntry = false,
    KeyValueStore? store,
  }) {
    requests = <RequestOptions>[];
    final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
      requests.add(options);
      if (options.path == '/calendars') {
        return FakeHttpResponse(
          envelope(<Object>[_calendar], meta: catalogueMeta),
        );
      }
      if (options.path == '/timetable/groups/demo-group') {
        if (groupEndpointFails) {
          return const FakeHttpResponse(<String, dynamic>{}, statusCode: 404);
        }
        return FakeHttpResponse(
          envelope(
            <String, dynamic>{'id': 'demo-group', 'shortName': 'Demo'},
            meta: <String, dynamic>{'from': '2026-09-24', 'to': '2026-10-22'},
          ),
        );
      }
      if (options.path == '/timetable/status') {
        return FakeHttpResponse(
          envelope(<String, dynamic>{
            'featureEnabled': true,
            'groupCount': 1,
            'coveredFrom': '2026-09-24',
            'coveredTo': '2026-10-22',
          }),
        );
      }
      if (options.path == '/timetable/entries') {
        return FakeHttpResponse(
          envelope(<String, dynamic>{
            'group': <String, dynamic>{'id': 'demo-group', 'shortName': 'Demo'},
            'days': timetableEntry
                ? <Object>[
                    <String, dynamic>{
                      'date': '2026-09-25',
                      'entries': <Object>[
                        <String, dynamic>{
                          'id': 'lesson-1',
                          'start': '2026-09-25T07:00:00.000Z',
                          'end': '2026-09-25T08:30:00.000Z',
                          'title': 'Mathematik 2',
                          'status': 'regular',
                          'type': 'regular_teaching',
                          'teachers': <Object>[],
                          'rooms': <Object>[],
                          'groups': <Object>[],
                        },
                      ],
                    },
                  ]
                : <Object>[],
          }),
        );
      }
      if (lateEvent &&
          options.path == '/calendars/events' &&
          options.queryParameters['from'] == '2027-01-22') {
        return FakeHttpResponse(
          envelope(<Object>[
            <String, dynamic>{
              'id': 'late-event',
              'calendarId': 'cal-1',
              'calendarSlug': 'campus',
              'title': 'Später Termin',
              'start': '2027-03-22T09:00:00.000Z',
              'end': '2027-03-22T10:00:00.000Z',
            },
          ]),
        );
      }
      if (truncatedRange && options.path == '/calendars/events') {
        if (options.queryParameters['from'] == '2026-09-24' &&
            options.queryParameters['to'] == '2026-09-27') {
          return FakeHttpResponse(
            envelope(<Object>[], meta: <String, dynamic>{'truncated': true}),
          );
        }
        if (options.queryParameters['from'] == '2026-09-26') {
          return FakeHttpResponse(
            envelope(<Object>[
              <String, dynamic>{
                'id': 'split-event',
                'calendarId': 'cal-1',
                'calendarSlug': 'campus',
                'title': 'Termin nach Teilung',
                'start': '2026-09-27T09:00:00.000Z',
                'end': '2026-09-27T10:00:00.000Z',
              },
            ]),
          );
        }
      }
      return FakeHttpResponse(envelope(<Object>[]));
    });
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(
          store ?? InMemoryKeyValueStore(),
        ),
        contentCacheProvider.overrideWithValue(
          SafeContentCache(MemoryContentCache()),
        ),
        savedEventsStoreProvider.overrideWithValue(MemorySavedEventsStore()),
        apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('two days of the same month share one aggregation', () {
    final ProviderContainer c = container();

    final ProviderSubscription<CalendarData> early = c.listen(
      calendarDataProvider(DateTime(2026, 5, 4)),
      (_, _) {},
    );
    final ProviderSubscription<CalendarData> late = c.listen(
      calendarDataProvider(DateTime(2026, 5, 27)),
      (_, _) {},
    );

    expect(
      identical(early.read(), late.read()),
      isTrue,
      reason: 'both days describe the same month, so the merge runs once',
    );
  });

  test('a different month is still aggregated separately', () {
    final ProviderContainer c = container();

    final ProviderSubscription<CalendarData> may = c.listen(
      calendarDataProvider(DateTime(2026, 5, 4)),
      (_, _) {},
    );
    final ProviderSubscription<CalendarData> june = c.listen(
      calendarDataProvider(DateTime(2026, 6, 4)),
      (_, _) {},
    );

    expect(identical(may.read(), june.read()), isFalse);
  });

  /// Resolves the catalogue first: without it the selection is empty and the
  /// events endpoint is deliberately never called at all.
  Future<void> loadCatalogue(ProviderContainer c) async {
    c.listen(publicCalendarsCatalogProvider, (_, _) {});
    await c.read(publicCalendarsCatalogProvider.future);
  }

  Iterable<String> eventRequests() => requests
      .map((RequestOptions request) => request.path)
      .where((String path) => path.contains('/calendars/events'));

  test('the events of one month are fetched once, not once per day', () async {
    final ProviderContainer c = container();
    await loadCatalogue(c);

    await c.read(
      publicCalendarMonthEntriesProvider(DateTime(2026, 5, 4)).future,
    );
    await c.read(
      publicCalendarMonthEntriesProvider(DateTime(2026, 5, 27)).future,
    );

    expect(
      eventRequests(),
      hasLength(1),
      reason: 'both days ask for the identical window',
    );
  });

  test('a day in another month does fetch its own window', () async {
    final ProviderContainer c = container();
    await loadCatalogue(c);

    await c.read(
      publicCalendarMonthEntriesProvider(DateTime(2026, 5, 4)).future,
    );
    await c.read(
      publicCalendarMonthEntriesProvider(DateTime(2026, 6, 4)).future,
    );

    expect(eventRequests(), hasLength(2));
  });

  test('the list requests every part of the backend import horizon', () async {
    final ProviderContainer c = container(
      catalogueMeta: <String, dynamic>{
        'from': '2026-09-24',
        'to': '2027-03-23',
        'maxRangeDays': 120,
      },
      lateEvent: true,
    );
    await loadCatalogue(c);

    final List<CalendarEntry> entries = await c.read(
      publicCalendarListEntriesProvider(DateTime(2026, 9, 24, 18)).future,
    );

    final List<RequestOptions> chunks = requests
        .where(
          (RequestOptions request) =>
              request.path.contains('/calendars/events'),
        )
        .toList();
    expect(chunks, hasLength(2));
    expect(chunks[0].queryParameters['from'], '2026-09-24');
    expect(chunks[0].queryParameters['to'], '2027-01-21');
    expect(chunks[1].queryParameters['from'], '2027-01-22');
    expect(chunks[1].queryParameters['to'], '2027-03-23');
    expect(
      entries.map((CalendarEntry entry) => entry.title),
      contains('Später Termin'),
    );
  });

  test('an export range keeps its historic lower bound', () async {
    final ProviderContainer c = container(
      catalogueMeta: <String, dynamic>{
        'from': '2026-01-01',
        'to': '2026-12-31',
        'maxRangeDays': 366,
      },
    );
    await loadCatalogue(c);

    await c.read(
      publicCalendarRangeEntriesProvider(
        CalendarDateWindow(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
      ).future,
    );

    final RequestOptions request = requests.lastWhere(
      (RequestOptions value) => value.path.contains('/calendars/events'),
    );
    expect(request.queryParameters['from'], '2026-01-01');
    expect(request.queryParameters['to'], '2026-12-31');
  });

  test(
    'the list splits a truncated response instead of dropping events',
    () async {
      final ProviderContainer c = container(
        catalogueMeta: <String, dynamic>{
          'from': '2026-09-24',
          'to': '2026-09-27',
          'maxRangeDays': 4,
        },
        truncatedRange: true,
      );
      await loadCatalogue(c);

      final List<CalendarEntry> entries = await c.read(
        publicCalendarListEntriesProvider(DateTime(2026, 9, 24)).future,
      );

      expect(
        entries.map((CalendarEntry entry) => entry.title),
        contains('Termin nach Teilung'),
      );
      expect(eventRequests(), hasLength(3));
    },
  );

  test('the list includes later entries from every local source', () {
    final DateTime from = DateTime(2026, 8, 27, 18);
    final List<CalendarEntry> entries = <CalendarEntry>[
      _entry('before', DateTime(2026, 8, 26, 12)),
      _entry('today', DateTime(2026, 8, 27, 12)),
      _entry('later', DateTime(2027, 12, 25, 12)),
    ];

    expect(
      calendarEntriesFrom(entries, from).map((CalendarEntry entry) => entry.id),
      <String>['today', 'later'],
    );
  });

  test('a cached backend horizon keeps rolling forward with today', () {
    final CalendarDateWindow window = calendarListWindow(
      DateTime(2026, 9, 25),
      '2026-09-24',
      '2027-03-23',
    );

    expect(window.from, DateTime(2026, 9, 25));
    expect(window.to, DateTime(2027, 3, 24));
  });

  test(
    'the list asks for timetable data only through its advertised horizon',
    () async {
      final ProviderContainer c = container(
        store: InMemoryKeyValueStore(<String, Object>{
          PreferenceKeys.preferredTimetableGroup: 'demo-group',
        }),
      );
      final DateTime today = DateTime(2026, 9, 24);
      c.listen(calendarListDataProvider(today), (_, _) {});
      await c.read(selectedTimetableGroupProvider.future);
      c.read(calendarListDataProvider(today));
      await c.read(
        timetableRangeProvider(
          TimetableRangeRequest(
            groupId: 'demo-group',
            from: today,
            to: DateTime(2026, 10, 22),
          ),
        ).future,
      );

      final List<RequestOptions> timetableRequests = requests
          .where(
            (RequestOptions request) => request.path == '/timetable/entries',
          )
          .toList();
      expect(timetableRequests, hasLength(1));
      expect(timetableRequests.single.queryParameters['from'], '2026-09-24');
      expect(timetableRequests.single.queryParameters['to'], '2026-10-22');
    },
  );

  test(
    'export uses status coverage when the selected group endpoint fails',
    () async {
      final ProviderContainer c = container(
        groupEndpointFails: true,
        timetableEntry: true,
        store: InMemoryKeyValueStore(<String, Object>{
          PreferenceKeys.preferredTimetableGroup: 'demo-group',
          PreferenceKeys.calendarDisabledSources: <String>[
            CalendarSource.moodle.storageValue,
            CalendarSource.publicCalendar.storageValue,
          ],
        }),
      );
      final ProviderSubscription<CalendarData> export = c.listen(
        calendarExportDataProvider,
        (_, _) {},
      );
      expect(export.read().isLoading, isTrue);

      await c.read(timetableStatusProvider.future);
      await c.pump();
      await c.read(
        timetableRangeProvider(
          TimetableRangeRequest(
            groupId: 'demo-group',
            from: DateTime(2026, 9, 24),
            to: DateTime(2026, 10, 22),
          ),
        ).future,
      );
      await c.pump();

      final CalendarData data = export.read();
      expect(
        requests.where(
          (RequestOptions request) =>
              request.path == '/timetable/groups/demo-group',
        ),
        isEmpty,
      );
      final RequestOptions timetableRequest = requests.singleWhere(
        (RequestOptions request) => request.path == '/timetable/entries',
      );
      expect(timetableRequest.queryParameters['from'], '2026-09-24');
      expect(timetableRequest.queryParameters['to'], '2026-10-22');
      expect(data.hasTimetableError, isFalse);
      expect(data.timetableState, CalendarTimetableState.ready);
      expect(
        data.entries.map((CalendarEntry entry) => entry.title),
        contains('Mathematik 2'),
      );
    },
  );

  test('export waits for the opted-in saved-event store', () async {
    final ProviderContainer c = container(
      store: InMemoryKeyValueStore(<String, Object>{
        PreferenceKeys.calendarSavedEventsEnabled: 1,
        PreferenceKeys.calendarDisabledSources: kMergeableCalendarSources
            .map((CalendarSource source) => source.storageValue)
            .toList(growable: false),
      }),
    );
    final ProviderSubscription<CalendarData> export = c.listen(
      calendarExportDataProvider,
      (_, _) {},
    );

    expect(export.read().isLoading, isTrue);
    await c.read(savedEventsControllerProvider.future);
    await c.pump();
    expect(export.read().isLoading, isFalse);
  });

  test('export waits for opted-in canteen favourites', () async {
    final ProviderContainer c = container(
      store: InMemoryKeyValueStore(<String, Object>{
        PreferenceKeys.calendarShowFavouriteMeals: 1,
        PreferenceKeys.canteenFavourites: <String>['Bulgur-Pfanne'],
        PreferenceKeys.calendarDisabledSources: kMergeableCalendarSources
            .map((CalendarSource source) => source.storageValue)
            .toList(growable: false),
      }),
    );
    final ProviderSubscription<CalendarData> export = c.listen(
      calendarExportDataProvider,
      (_, _) {},
    );

    expect(export.read().isLoading, isTrue);
    await c.read(canteensProvider.future);
    await c.pump();
    expect(export.read().isLoading, isFalse);
  });

  test('focused calendar uses the rolling window only in list mode', () {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        calendarClockProvider.overrideWithValue(
          _FixedClock(DateTime(2026, 8, 27, 18)),
        ),
        calendarDataProvider.overrideWith(
          (Ref ref, DateTime day) => CalendarData(
            entries: <CalendarEntry>[_entry('month', day)],
            enabledSources: const <CalendarSource>{},
          ),
        ),
        calendarListDataProvider.overrideWith(
          (Ref ref, DateTime day) => CalendarData(
            entries: <CalendarEntry>[_entry('list-${day.day}', day)],
            enabledSources: const <CalendarSource>{},
          ),
        ),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(focusedCalendarDataProvider).entries.single.id, 'month');
    c.read(calendarViewModeProvider.notifier).set(CalendarViewMode.list);
    expect(c.read(focusedCalendarDataProvider).entries.single.id, 'list-27');
  });

  test('a month nobody watches any more is released', () async {
    // Without this every day someone browses to keeps its merged month —
    // entries, day index, event days — alive until the process ends.
    final ProviderContainer c = container();

    final ProviderSubscription<CalendarData> first = c.listen(
      calendarDataProvider(DateTime(2026, 5, 4)),
      (_, _) {},
    );
    final CalendarData held = first.read();
    first.close();
    await c.pump();

    final ProviderSubscription<CalendarData> again = c.listen(
      calendarDataProvider(DateTime(2026, 5, 4)),
      (_, _) {},
    );
    expect(identical(again.read(), held), isFalse);
  });

  test('returning to a released month costs no new request', () async {
    // Releasing derived state must not turn into traffic: the week and event
    // providers behind it keep their data, so the return is a re-merge.
    final ProviderContainer c = container();
    await loadCatalogue(c);

    final ProviderSubscription<CalendarData> first = c.listen(
      calendarDataProvider(DateTime(2026, 5, 4)),
      (_, _) {},
    );
    first.read();
    await c.read(
      publicCalendarMonthEntriesProvider(DateTime(2026, 5, 4)).future,
    );
    final int before = eventRequests().length;
    expect(before, 1);

    first.close();
    await c.pump();

    final ProviderSubscription<CalendarData> again = c.listen(
      calendarDataProvider(DateTime(2026, 5, 4)),
      (_, _) {},
    );
    again.read();
    await c.pump();

    expect(eventRequests(), hasLength(before));
  });
}

CalendarEntry _entry(String id, DateTime start) => CalendarEntry(
  id: id,
  source: CalendarSource.publicCalendar,
  title: id,
  start: start,
);

class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
