// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/time/clock.dart';
import 'package:campus_koethen/features/calendar/application/calendar_providers.dart';
import 'package:campus_koethen/features/calendar/application/public_calendar_providers.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/public_calendar.dart';
import 'package:campus_koethen/features/notifications/data/device_time_zone.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:campus_koethen/features/notifications/application/event_reminder_candidates.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Which events N1 is allowed to see — ADR-0001 § 7.2 and the acceptance
/// criteria of LEVIORA-166.
///
/// This is the half of the feature that no unit test of the pure builder can
/// reach: whether the *right* entries arrive there in the first place, and
/// whether a bookmarked event that is also a live calendar entry arrives once
/// or twice.

/// A fixed "today", so a month horizon is a known set of months.
final DateTime kNow = DateTime(2026, 7, 1, 12);

class _FixedClock implements Clock {
  const _FixedClock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// The catalogue entry that maps a calendar slug to its editorial channel —
/// the lookup the post-versus-calendar dedup rule needs.
PublicCalendar catalogueEntry({
  String slug = 'hsa-events',
  String? channelSlug,
}) => PublicCalendar(
  id: slug,
  slug: slug,
  name: 'HSA Events',
  colorHex: '#336699',
  sortOrder: 0,
  defaultSubscribed: true,
  googleOpenUrl: 'https://example.invalid/',
  channelSlug: channelSlug,
);

CalendarEntry liveEvent({
  String calendarSlug = 'hsa-events',
  String eventId = '4711',
  String title = 'Campus Sommerfest 2026',
  DateTime? start,
  bool allDay = false,
}) => CalendarEntry(
  id: 'publicCalendar:$calendarSlug:$eventId',
  source: CalendarSource.publicCalendar,
  title: title,
  start: start ?? DateTime(2026, 7, 22, 16),
  allDay: allDay,
  calendarSlug: calendarSlug,
  sourceLabel: 'HSA Events',
);

SavedEventSnapshot savedSnapshot({
  String eventRef = 'calendar:4711',
  UnifiedEventKind kind = UnifiedEventKind.calendarEvent,
  String title = 'Campus Sommerfest 2026',
  DateTime? start,
  bool allDay = false,
  bool isOrphaned = false,
  bool isCancelled = false,
  String? channelSlug,
  String? calendarSlug = 'hsa-events',
}) => SavedEventSnapshot(
  eventRef: eventRef,
  kind: kind,
  title: title,
  start: start ?? DateTime(2026, 7, 22, 16),
  allDay: allDay,
  channelSlug: channelSlug,
  calendarSlug: calendarSlug,
  isCancelled: isCancelled,
  isOrphaned: isOrphaned,
  savedAt: DateTime(2026, 6, 1),
);

/// A container wired the way the app wires it, minus the network: the public
/// months answer with fixed lists and the saved box is in memory.
Future<ProviderContainer> containerWith({
  List<CalendarEntry> live = const <CalendarEntry>[],
  List<SavedEventSnapshot> saved = const <SavedEventSnapshot>[],
  List<PublicCalendar> catalogue = const <PublicCalendar>[],
  List<Override> extra = const <Override>[],
}) async {
  final MemorySavedEventsStore store = MemorySavedEventsStore();
  await store.writeAll(saved);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      savedEventsStoreProvider.overrideWithValue(store),
      savedEventsClockProvider.overrideWithValue(() => kNow),
      notificationClockProvider.overrideWithValue(_FixedClock(kNow)),
      timeZoneResolverProvider.overrideWithValue(
        FixedTimeZoneResolver('Europe/Berlin'),
      ),
      publicCalendarsCatalogProvider.overrideWith(
        (Ref ref) async =>
            Loaded<List<PublicCalendar>>(value: catalogue, meta: ApiMeta.empty),
      ),
      // Only the month the fixtures live in answers with anything; the rest of
      // the horizon is empty, exactly as an unfetched month would be.
      publicCalendarMonthEntriesProvider.overrideWith(
        (Ref ref, DateTime anchor) async =>
            anchor.month == 7 ? live : const <CalendarEntry>[],
      ),
      ...extra,
    ],
  );
  addTearDown(container.dispose);

  // The two async sources have to have settled before the synchronous
  // candidate provider is asked, or it would legitimately answer "nothing
  // known yet" — which is a different rule, tested separately below.
  await container.read(savedEventsControllerProvider.future);
  await container.read(
    publicCalendarMonthEntriesProvider(DateTime(2026, 7)).future,
  );
  await container.read(publicCalendarsCatalogProvider.future);
  await container.read(notificationLocationProvider.future);
  return container;
}

List<String> entryIds(ProviderContainer c) => c
    .read(notificationEventEntriesProvider)
    .map((CalendarEntry e) => e.id)
    .toList(growable: false);

void main() {
  setUpAll(() async {
    // The reminder text formats a time, which needs the locale's date
    // symbols; the app loads them at start-up.
    await initializeDateFormatting('de');
    await initializeDateFormatting('en');
  });

  group('the display switches never change the plan (ADR-0001 § 7.2)', () {
    test(
      'a bookmarked event is in scope even with the calendar switch off',
      () async {
        // `calendarSavedEventsEnabledProvider` is OFF by default. A scope that
        // read it would produce no reminder for a saved event in the normal
        // case — the single most important thing this category does.
        final ProviderContainer container = await containerWith(
          saved: <SavedEventSnapshot>[savedSnapshot()],
        );

        expect(
          container.read(calendarSavedEventsEnabledProvider),
          isFalse,
          reason: 'the fixture must be the default-off case to be meaningful',
        );
        expect(entryIds(container), <String>['savedEvent:calendar:4711']);
      },
    );

    test('the public-calendar display switch cannot change the plan', () async {
      final ProviderContainer container = await containerWith(
        live: <CalendarEntry>[liveEvent()],
      );
      final List<String> before = entryIds(container);

      await container
          .read(calendarEnabledSourcesProvider.notifier)
          .toggle(CalendarSource.publicCalendar);

      expect(
        container
            .read(calendarEnabledSourcesProvider)
            .contains(CalendarSource.publicCalendar),
        isFalse,
      );
      expect(entryIds(container), before);
    });

    test('a deselected public calendar DOES change it', () async {
      // The other half of the same rule: the calendar *selection* is part of
      // the scope, the calendar *view filter* is not. The selection is applied
      // one level down, in `publicCalendarMonthEntriesProvider`, which answers
      // with nothing when nothing is selected.
      final ProviderContainer container = await containerWith();

      expect(entryIds(container), isEmpty);
    });
  });

  group('exactly one reminder per event', () {
    test('a bookmarked event that is also live appears once', () async {
      final ProviderContainer container = await containerWith(
        live: <CalendarEntry>[liveEvent()],
        saved: <SavedEventSnapshot>[savedSnapshot()],
      );

      // The saved snapshot's own `eventRef` names exactly the live entry, so
      // the events feature's dedup rule drops the snapshot and keeps the live
      // one — which carries the richer detail.
      expect(entryIds(container), <String>['publicCalendar:hsa-events:4711']);

      final List<NotificationRequest> requests = container.read(
        eventReminderCandidatesProvider,
      );
      expect(
        requests.map((NotificationRequest r) => r.key).toSet(),
        hasLength(requests.length),
      );
    });

    test(
      'a bookmarked post duplicating a live calendar entry appears once',
      () async {
        // The second dedup path: same channel attribution, same all-day flag,
        // minute-exact same start. It needs the catalogue, which is what maps a
        // calendar slug to its editorial channel.
        final ProviderContainer container = await containerWith(
          live: <CalendarEntry>[liveEvent()],
          catalogue: <PublicCalendar>[catalogueEntry(channelSlug: 'hsa-news')],
          saved: <SavedEventSnapshot>[
            savedSnapshot(
              eventRef: 'post:sommerfest',
              kind: UnifiedEventKind.postEvent,
              channelSlug: 'hsa-news',
            ),
          ],
        );

        expect(entryIds(container), <String>['publicCalendar:hsa-events:4711']);
      },
    );

    test('a post at another time is NOT a duplicate and stays', () async {
      // The rule is minute-exact, never same-day: two things on one day are
      // two things, and both deserve their own reminder.
      final ProviderContainer container = await containerWith(
        live: <CalendarEntry>[liveEvent()],
        catalogue: <PublicCalendar>[catalogueEntry(channelSlug: 'hsa-news')],
        saved: <SavedEventSnapshot>[
          savedSnapshot(
            eventRef: 'post:vortrag',
            kind: UnifiedEventKind.postEvent,
            channelSlug: 'hsa-news',
            start: DateTime(2026, 7, 22, 18),
          ),
        ],
      );

      expect(entryIds(container), hasLength(2));
    });

    test('two unrelated events stay two', () async {
      final ProviderContainer container = await containerWith(
        live: <CalendarEntry>[
          liveEvent(eventId: '1'),
          liveEvent(eventId: '2', start: DateTime(2026, 7, 23, 16)),
        ],
      );

      expect(entryIds(container), hasLength(2));
    });
  });

  group('what the scope leaves out', () {
    test('an orphaned bookmark — its source no longer has it', () async {
      final ProviderContainer container = await containerWith(
        saved: <SavedEventSnapshot>[savedSnapshot(isOrphaned: true)],
      );

      expect(entryIds(container), isEmpty);
    });

    test('a cancelled bookmark', () async {
      final ProviderContainer container = await containerWith(
        saved: <SavedEventSnapshot>[savedSnapshot(isCancelled: true)],
      );

      expect(entryIds(container), isEmpty);
    });

    test(
      'a month that has not been loaded contributes nothing, not an error',
      () async {
        // The plan must never wait on the network. An unresolved month is simply
        // absent from this run and arrives in the next one.
        final ProviderContainer container = ProviderContainer(
          overrides: <Override>[
            keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
            savedEventsStoreProvider.overrideWithValue(
              MemorySavedEventsStore(),
            ),
            savedEventsClockProvider.overrideWithValue(() => kNow),
            notificationClockProvider.overrideWithValue(_FixedClock(kNow)),
            timeZoneResolverProvider.overrideWithValue(
              FixedTimeZoneResolver('Europe/Berlin'),
            ),
            publicCalendarMonthEntriesProvider.overrideWith(
              (Ref ref, DateTime anchor) =>
                  Future<List<CalendarEntry>>.error(Exception('offline')),
            ),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(notificationEventEntriesProvider), isEmpty);
        expect(container.read(eventReminderCandidatesProvider), isEmpty);
      },
    );
  });

  group('resolving a payload back to its entry (ADR-0001 § 7.8)', () {
    test('a live id resolves to the entry it names', () async {
      final ProviderContainer container = await containerWith(
        live: <CalendarEntry>[liveEvent()],
      );

      final CalendarEntry? found = container.read(
        calendarEntryForNotificationProvider('publicCalendar:hsa-events:4711'),
      );
      expect(found?.title, 'Campus Sommerfest 2026');
    });

    test('an id that no longer names anything resolves to null', () async {
      final ProviderContainer container = await containerWith(
        live: <CalendarEntry>[liveEvent()],
      );

      expect(
        container.read(
          calendarEntryForNotificationProvider('publicCalendar:gone:1'),
        ),
        isNull,
      );
      expect(container.read(calendarEntryForNotificationProvider('')), isNull);
    });

    test('every scheduled reminder can be resolved back', () async {
      // The round trip that matters: what the planner puts in a payload is
      // exactly what the tap side looks up. A change to either identity
      // scheme breaks this and nothing else.
      final ProviderContainer container = await containerWith(
        live: <CalendarEntry>[liveEvent()],
        saved: <SavedEventSnapshot>[
          savedSnapshot(
            eventRef: 'post:vortrag',
            kind: UnifiedEventKind.postEvent,
          ),
        ],
      );

      final List<NotificationRequest> requests = container.read(
        eventReminderCandidatesProvider,
      );
      expect(requests, isNotEmpty);
      for (final NotificationRequest request in requests) {
        expect(
          container.read(
            calendarEntryForNotificationProvider(request.payload.target),
          ),
          isNotNull,
          reason: request.key,
        );
      }
    });
  });
}
