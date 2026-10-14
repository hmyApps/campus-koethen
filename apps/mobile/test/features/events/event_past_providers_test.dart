// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/time/clock.dart';
import 'package:campus_koethen/features/calendar/application/public_calendar_providers.dart';
import 'package:campus_koethen/features/calendar/data/public_calendars_repository.dart';
import 'package:campus_koethen/features/calendar/domain/public_calendar.dart';
import 'package:campus_koethen/features/events/application/event_providers.dart';
import 'package:campus_koethen/features/events/application/event_sort_order.dart';
import 'package:campus_koethen/features/events/application/event_source_filter.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/data/event_posts_repository.dart';
import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/events/domain/event_sort.dart';
import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Local noon on 2026-10-14 — "today" for the past window.
final DateTime _now = DateTime(2026, 10, 14, 12);

class _FixedClock implements Clock {
  const _FixedClock();
  @override
  DateTime now() => _now;
}

class _StaticOverviewClock extends EventOverviewClockController {
  @override
  DateTime build() => _now;
}

NewsArticle _post(
  String slug, {
  required DateTime start,
  required DateTime end,
  String channel = 'campus-events',
  DateTime? publishedAt,
}) => NewsArticle(
  slug: slug,
  title: 'Demo $slug',
  tag: const NewsTagRef(slug: 'event', name: 'Event'),
  primaryChannel: NewsChannelRef(slug: channel, name: channel),
  publishedAt: publishedAt,
  eventStart: start,
  eventEnd: end,
);

PublicCalendarEvent _calendarEvent(
  String id, {
  required DateTime start,
  required DateTime end,
  String calendarSlug = 'stura-termine',
}) => PublicCalendarEvent(
  id: id,
  calendarId: 'cal-$calendarSlug',
  calendarSlug: calendarSlug,
  title: 'Demo $id',
  start: start,
  end: end,
);

const PublicCalendar _calendar = PublicCalendar(
  id: 'cal-stura-termine',
  slug: 'stura-termine',
  name: 'StuRa Termine',
  colorHex: '#336699',
  sortOrder: 0,
  defaultSubscribed: true,
  googleOpenUrl: 'https://calendar.google.com/calendar/render?cid=demo',
);

/// Records every past-window request, answers with the configured result
/// or error.
class _FakeEventPostsRepository implements EventPostsRepository {
  _FakeEventPostsRepository({this.current, this.past, this.pastError});

  final EventPostsResult? current;
  final EventPostsResult? past;
  final Object? pastError;
  final List<(String?, String?)> requests = <(String?, String?)>[];

  @override
  Future<EventPostsResult> fetchAllEventPosts({
    required String locale,
    String? channelsParameter,
    String? from,
    String? to,
  }) async {
    requests.add((from, to));
    if (from == null && to == null) {
      return current ?? _emptyPosts;
    }
    if (pastError != null) throw pastError!;
    return past ?? _emptyPosts;
  }
}

const EventPostsResult _emptyPosts = EventPostsResult(
  articles: <NewsArticle>[],
  isTruncated: false,
  from: '2026-10-14',
  to: '2027-11-18',
);

class _FakeCalendarsRepository implements PublicCalendarsRepository {
  _FakeCalendarsRepository({
    this.past = const <PublicCalendarEvent>[],
    this.pastError,
  });

  final List<PublicCalendarEvent> past;
  final Object? pastError;
  final List<(List<String>, String, String)> pastRequests =
      <(List<String>, String, String)>[];

  @override
  Future<Loaded<List<PublicCalendarEvent>>> fetchEventsDefaultWindow({
    required String locale,
    required List<String> slugs,
  }) async => Loaded<List<PublicCalendarEvent>>(
    value: const <PublicCalendarEvent>[],
    meta: const ApiMeta(from: '2026-10-14', to: '2027-11-18'),
  );

  @override
  Future<Loaded<List<PublicCalendarEvent>>> fetchEvents({
    required String locale,
    required List<String> slugs,
    required String from,
    required String to,
  }) async {
    pastRequests.add((slugs, from, to));
    if (pastError != null) throw pastError!;
    return Loaded<List<PublicCalendarEvent>>(
      value: past,
      meta: ApiMeta(from: from, to: to),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const List<EventSourceOption> _options = <EventSourceOption>[
  EventSourceOption(key: 'campus-events', label: 'Campus Events'),
  EventSourceOption(key: 'kultur', label: 'Kultur'),
  EventSourceOption(key: 'stura-termine', label: 'StuRa Termine'),
];

ProviderContainer _container({
  required _FakeEventPostsRepository posts,
  _FakeCalendarsRepository? calendars,
  Set<String>? selected,
  MemorySavedEventsStore? savedStore,
  InMemoryKeyValueStore? store,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      keyValueStoreProvider.overrideWithValue(
        store ??
            InMemoryKeyValueStore(<String, Object>{
              PreferenceKeys.eventSourceStoreVersion:
                  PreferenceKeys.eventSourceStoreCurrentVersion,
              PreferenceKeys.eventSourceSeenKeys: _options
                  .map((EventSourceOption o) => o.key)
                  .toList(),
              PreferenceKeys.eventSourceSelectedKeys:
                  (selected ??
                          _options.map((EventSourceOption o) => o.key).toSet())
                      .toList(),
            }),
      ),
      eventsClockProvider.overrideWithValue(const _FixedClock()),
      eventOverviewClockProvider.overrideWith(_StaticOverviewClock.new),
      savedEventsClockProvider.overrideWithValue(() => _now),
      savedEventsStoreProvider.overrideWithValue(
        savedStore ?? MemorySavedEventsStore(),
      ),
      eventSourceOptionsProvider.overrideWith((Ref ref) async => _options),
      publicCalendarsCatalogProvider.overrideWith(
        (Ref ref) async => const Loaded<List<PublicCalendar>>(
          value: <PublicCalendar>[_calendar],
          meta: ApiMeta.empty,
        ),
      ),
      eventPostsRepositoryProvider.overrideWithValue(posts),
      publicCalendarsRepositoryProvider.overrideWithValue(
        calendars ?? _FakeCalendarsRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Loads every source the overview watches and returns its data.
Future<EventOverviewData> _settle(ProviderContainer c) async {
  c.listen(eventOverviewProvider, (_, _) {});
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(eventOverviewProvider);
}

List<String> _refs(List<UnifiedEvent> events) =>
    events.map((UnifiedEvent e) => e.eventRef).toList();

void main() {
  final NewsArticle endedThisMorning = _post(
    'fruehstueck',
    start: DateTime(2026, 10, 14, 8),
    end: DateTime(2026, 10, 14, 10),
    publishedAt: DateTime(2026, 10, 1),
  );
  final NewsArticle upcoming = _post(
    'werwolf',
    start: DateTime(2026, 10, 20, 18),
    end: DateTime(2026, 10, 20, 22),
    publishedAt: DateTime(2026, 10, 7),
  );
  final NewsArticle lastMonth = _post(
    'kochen',
    start: DateTime(2026, 9, 9, 17),
    end: DateTime(2026, 9, 9, 20),
    publishedAt: DateTime(2026, 10, 2),
  );
  final NewsArticle lastWeekKultur = _post(
    'theater',
    start: DateTime(2026, 10, 7, 19),
    end: DateTime(2026, 10, 7, 21),
    channel: 'kultur',
    publishedAt: DateTime(2026, 9, 1),
  );

  EventPostsResult current(List<NewsArticle> articles) => EventPostsResult(
    articles: articles,
    isTruncated: false,
    from: '2026-10-14',
    to: '2027-11-18',
  );

  EventPostsResult past(List<NewsArticle> articles) => EventPostsResult(
    articles: articles,
    isTruncated: false,
    from: '2026-04-17',
    to: '2026-10-14',
  );

  test('hidden by default: no past request, no past section', () async {
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository(
      current: current(<NewsArticle>[endedThisMorning, upcoming]),
    );
    final _FakeCalendarsRepository calendars = _FakeCalendarsRepository();
    final ProviderContainer c = _container(posts: posts, calendars: calendars);

    final EventOverviewData data = await _settle(c);

    expect(_refs(data.events), <String>['post:werwolf']);
    expect(data.showPast, isFalse);
    expect(data.pastEvents, isEmpty);
    expect(posts.requests, <(String?, String?)>[(null, null)]);
    expect(calendars.pastRequests, isEmpty);
  });

  test('showing past events requests BOTH bounds explicitly for both '
      'sources', () async {
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository();
    final _FakeCalendarsRepository calendars = _FakeCalendarsRepository();
    final ProviderContainer c = _container(posts: posts, calendars: calendars);
    c.read(eventShowPastProvider.notifier).show();

    await _settle(c);

    expect(posts.requests, contains(('2026-04-17', '2026-10-14')));
    expect(calendars.pastRequests, hasLength(1));
    expect(calendars.pastRequests.single.$1, <String>['stura-termine']);
    expect(calendars.pastRequests.single.$2, '2026-04-17');
    expect(calendars.pastRequests.single.$3, '2026-10-14');
  });

  test('the past section holds ended events of both windows — including '
      'one that ended this morning — and never a current one', () async {
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository(
      current: current(<NewsArticle>[endedThisMorning, upcoming]),
      // The past window overlaps today, so it repeats this morning's event.
      past: past(<NewsArticle>[endedThisMorning, lastMonth]),
    );
    final _FakeCalendarsRepository calendars = _FakeCalendarsRepository(
      past: <PublicCalendarEvent>[
        _calendarEvent(
          'sitzung',
          start: DateTime(2026, 10, 1, 16),
          end: DateTime(2026, 10, 1, 18),
        ),
      ],
    );
    final ProviderContainer c = _container(posts: posts, calendars: calendars);
    c.read(eventShowPastProvider.notifier).show();

    final EventOverviewData data = await _settle(c);

    expect(_refs(data.events), <String>['post:werwolf']);
    // Chronological: most recently held first.
    expect(_refs(data.pastEvents), <String>[
      'post:fruehstueck',
      'calendar:sitzung',
      'post:kochen',
    ]);
    expect(data.showPast, isTrue);
    expect(data.pastLoading, isFalse);
  });

  test('the source filter applies to past events too', () async {
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository(
      past: past(<NewsArticle>[lastMonth, lastWeekKultur]),
    );
    final ProviderContainer c = _container(
      posts: posts,
      selected: const <String>{'kultur'},
    );
    c.read(eventShowPastProvider.notifier).show();

    final EventOverviewData data = await _settle(c);

    expect(_refs(data.pastEvents), <String>['post:theater']);
  });

  test('"Neueste zuerst" orders both sections by publishedAt', () async {
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository(
      current: current(<NewsArticle>[
        upcoming,
        _post(
          'spaeter',
          start: DateTime(2026, 11, 1, 18),
          end: DateTime(2026, 11, 1, 20),
          publishedAt: DateTime(2026, 10, 12),
        ),
      ]),
      past: past(<NewsArticle>[lastMonth, lastWeekKultur, endedThisMorning]),
    );
    final ProviderContainer c = _container(posts: posts);
    c.read(eventShowPastProvider.notifier).show();
    await c
        .read(eventSortOrderProvider.notifier)
        .setOrder(EventSortOrder.newestFirst);

    final EventOverviewData data = await _settle(c);

    expect(_refs(data.events), <String>['post:spaeter', 'post:werwolf']);
    expect(_refs(data.pastEvents), <String>[
      'post:kochen',
      'post:fruehstueck',
      'post:theater',
    ]);
  });

  test('a failing past source keeps current events and the other past '
      'source', () async {
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository(
      current: current(<NewsArticle>[upcoming]),
      pastError: Exception('offline'),
    );
    final _FakeCalendarsRepository calendars = _FakeCalendarsRepository(
      past: <PublicCalendarEvent>[
        _calendarEvent(
          'sitzung',
          start: DateTime(2026, 10, 1, 16),
          end: DateTime(2026, 10, 1, 18),
        ),
      ],
    );
    final ProviderContainer c = _container(posts: posts, calendars: calendars);
    c.read(eventShowPastProvider.notifier).show();

    final EventOverviewData data = await _settle(c);

    expect(_refs(data.events), <String>['post:werwolf']);
    expect(data.hasPostsError, isFalse);
    expect(data.hasPastPostsError, isTrue);
    expect(data.hasPastCalendarError, isFalse);
    expect(_refs(data.pastEvents), <String>['calendar:sitzung']);
  });

  test('a failing past calendar load keeps the past posts', () async {
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository(
      current: current(<NewsArticle>[upcoming]),
      past: past(<NewsArticle>[lastMonth]),
    );
    final ProviderContainer c = _container(
      posts: posts,
      calendars: _FakeCalendarsRepository(pastError: Exception('offline')),
    );
    c.read(eventShowPastProvider.notifier).show();

    final EventOverviewData data = await _settle(c);

    expect(_refs(data.events), <String>['post:werwolf']);
    expect(data.hasCalendarError, isFalse);
    expect(data.hasPastCalendarError, isTrue);
    expect(data.hasPastPostsError, isFalse);
    expect(_refs(data.pastEvents), <String>['post:kochen']);
  });

  test('a past load never touches the saved list orphan flags', () async {
    final MemorySavedEventsStore saved = MemorySavedEventsStore();
    await saved.writeAll(<SavedEventSnapshot>[
      SavedEventSnapshot(
        eventRef: 'post:geloescht',
        kind: UnifiedEventKind.postEvent,
        title: 'Demo gemerkt',
        start: DateTime(2026, 9, 1, 18),
        end: DateTime(2026, 9, 1, 20),
        savedAt: DateTime(2026, 8, 1),
        channelSlug: 'campus-events',
      ),
      SavedEventSnapshot(
        eventRef: 'calendar:weg',
        kind: UnifiedEventKind.calendarEvent,
        title: 'Demo gemerkt',
        start: DateTime(2026, 9, 2, 18),
        end: DateTime(2026, 9, 2, 20),
        savedAt: DateTime(2026, 8, 1),
        calendarSlug: 'stura-termine',
      ),
    ]);
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository(
      past: past(<NewsArticle>[lastMonth]),
    );
    final ProviderContainer c = _container(posts: posts, savedStore: saved);
    await c.read(savedEventsControllerProvider.future);
    c.read(eventShowPastProvider.notifier).show();

    await _settle(c);

    final List<SavedEventSnapshot> after = c
        .read(savedEventsControllerProvider)
        .requireValue;
    expect(after.every((SavedEventSnapshot s) => !s.isOrphaned), isTrue);
  });

  test('hiding past events again empties the past section', () async {
    final _FakeEventPostsRepository posts = _FakeEventPostsRepository(
      past: past(<NewsArticle>[lastMonth]),
    );
    final ProviderContainer c = _container(posts: posts);
    c.read(eventShowPastProvider.notifier).show();
    expect((await _settle(c)).pastEvents, isNotEmpty);

    c.read(eventShowPastProvider.notifier).hide();

    final EventOverviewData data = await _settle(c);
    expect(data.showPast, isFalse);
    expect(data.pastEvents, isEmpty);
  });

  group('eventSortOrderProvider', () {
    test('defaults to chronological and persists a choice', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer c = _container(
        posts: _FakeEventPostsRepository(),
        store: store,
      );
      expect(c.read(eventSortOrderProvider), EventSortOrder.chronological);

      await c
          .read(eventSortOrderProvider.notifier)
          .setOrder(EventSortOrder.newestFirst);

      expect(c.read(eventSortOrderProvider), EventSortOrder.newestFirst);
      expect(store.getString(PreferenceKeys.eventSortOrder), 'newestFirst');

      final ProviderContainer reloaded = _container(
        posts: _FakeEventPostsRepository(),
        store: store,
      );
      expect(reloaded.read(eventSortOrderProvider), EventSortOrder.newestFirst);
    });
  });
}
