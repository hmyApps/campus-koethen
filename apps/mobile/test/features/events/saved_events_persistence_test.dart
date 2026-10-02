// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/cache_providers.dart';
import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/locale/locale_providers.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/features/events/application/event_providers.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:campus_koethen/features/events/domain/saved_events_rules.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';

SavedEventSnapshot _snapshot({
  String eventRef = 'post:a',
  UnifiedEventKind kind = UnifiedEventKind.postEvent,
  DateTime? start,
  DateTime? end,
  DateTime? savedAt,
  bool isOrphaned = false,
  String? channelSlug = 'campus-events',
  String? calendarSlug,
}) => SavedEventSnapshot(
  eventRef: eventRef,
  kind: kind,
  title: 'Gespeichertes Event',
  start: start ?? DateTime.utc(2026, 8, 10, 18),
  end: end,
  savedAt: savedAt ?? DateTime.utc(2026, 8, 1),
  isOrphaned: isOrphaned,
  channelSlug: channelSlug,
  calendarSlug: calendarSlug,
);

ProviderContainer _containerWith(SavedEventsStore store, {DateTime? now}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      savedEventsStoreProvider.overrideWithValue(store),
      if (now != null) savedEventsClockProvider.overrideWithValue(() => now),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('snapshot completeness', () {
    // Regression for LEVIORA-115 F2: a snapshot has to be self-contained,
    // because the saved list is the one that has to work offline.
    final UnifiedEvent live = UnifiedEvent(
      eventRef: 'calendar:abc',
      kind: UnifiedEventKind.calendarEvent,
      title: 'StuRa-Sitzung',
      start: DateTime.utc(2026, 9, 1, 16),
      end: DateTime.utc(2026, 9, 1, 18),
      channelSlug: 'campus-events',
      calendarSlug: 'stura-termine',
      sourceLabel: 'StuRa-Termine',
      colorArgb: 0xFF5B3FD0,
      isCancelled: true,
      location: 'Raum 1.02',
      description: 'Tagesordnung folgt',
    );

    test('saving keeps everything the card renders', () {
      final UnifiedEvent restored = SavedEventSnapshot.fromUnifiedEvent(
        live,
        savedAt: DateTime.utc(2026, 8, 1),
      ).toUnifiedEvent();

      expect(restored.location, 'Raum 1.02');
      expect(restored.description, 'Tagesordnung folgt');
      expect(restored.isCancelled, isTrue);
      expect(restored.colorArgb, 0xFF5B3FD0);
      expect(restored.sourceLabel, 'StuRa-Termine');
    });

    test('a JSON round trip preserves them too', () {
      final SavedEventSnapshot original = SavedEventSnapshot.fromUnifiedEvent(
        live,
        savedAt: DateTime.utc(2026, 8, 1),
      );
      final SavedEventSnapshot? decoded = SavedEventSnapshot.fromJson(
        original.toJson(),
      );

      expect(decoded?.location, 'Raum 1.02');
      expect(decoded?.description, 'Tagesordnung folgt');
      expect(decoded?.isCancelled, isTrue);
      expect(decoded?.colorArgb, 0xFF5B3FD0);
    });

    test('an entry written before these fields existed still reads', () {
      // Stored shape prior to this change — the new keys are simply absent.
      final SavedEventSnapshot? decoded =
          SavedEventSnapshot.fromJson(<String, dynamic>{
            'eventRef': 'calendar:abc',
            'kind': 'calendar-event',
            'title': 'StuRa-Sitzung',
            'start': '2026-09-01T16:00:00.000Z',
            'end': '2026-09-01T18:00:00.000Z',
            'allDay': false,
            'channelSlug': 'campus-events',
            'calendarSlug': 'stura-termine',
            'sourceLabel': 'StuRa-Termine',
            'savedAt': '2026-08-01T00:00:00.000Z',
            'isOrphaned': false,
          });

      expect(decoded, isNotNull);
      expect(decoded?.title, 'StuRa-Sitzung');
      expect(decoded?.location, isNull);
      expect(decoded?.description, isNull);
      expect(decoded?.isCancelled, isFalse);
    });

    test('copyWith(isOrphaned:) does not drop them', () {
      final SavedEventSnapshot flagged = SavedEventSnapshot.fromUnifiedEvent(
        live,
        savedAt: DateTime.utc(2026, 8, 1),
      ).copyWith(isOrphaned: true);

      expect(flagged.isOrphaned, isTrue);
      expect(flagged.location, 'Raum 1.02');
      expect(flagged.description, 'Tagesordnung folgt');
      expect(flagged.isCancelled, isTrue);
    });
  });

  group('restart', () {
    test(
      'a fresh controller loads whatever the store already persisted',
      () async {
        final MemorySavedEventsStore store = MemorySavedEventsStore();
        await store.writeAll(<SavedEventSnapshot>[
          _snapshot(eventRef: 'post:x'),
        ]);

        final ProviderContainer container = _containerWith(
          store,
          now: DateTime.utc(2026, 8, 5),
        );
        final List<SavedEventSnapshot> loaded = await container.read(
          savedEventsControllerProvider.future,
        );

        expect(loaded, hasLength(1));
        expect(loaded.single.eventRef, 'post:x');
      },
    );

    test(
      'a save survives being read back by a brand new controller instance',
      () async {
        final MemorySavedEventsStore store = MemorySavedEventsStore();
        final ProviderContainer first = _containerWith(
          store,
          now: DateTime.utc(2026, 8, 5),
        );
        await first.read(savedEventsControllerProvider.future);
        await first
            .read(savedEventsControllerProvider.notifier)
            .save(
              UnifiedEvent(
                eventRef: 'post:new',
                kind: UnifiedEventKind.postEvent,
                title: 'Neu',
                start: DateTime.utc(2026, 8, 12),
              ),
            );
        first.dispose();

        // "Restart": a second, independent container reading the same
        // underlying store — nothing but the persisted bytes carries over.
        final ProviderContainer second = _containerWith(
          store,
          now: DateTime.utc(2026, 8, 5),
        );
        final List<SavedEventSnapshot> reloaded = await second.read(
          savedEventsControllerProvider.future,
        );
        expect(
          reloaded.map((SavedEventSnapshot s) => s.eventRef),
          contains('post:new'),
        );
      },
    );
  });

  test('a failed commit does not publish an event as saved', () async {
    final _FailingSavedEventsStore store = _FailingSavedEventsStore();
    final ProviderContainer container = _containerWith(
      store,
      now: DateTime.utc(2026, 8, 5),
    );
    await container.read(savedEventsControllerProvider.future);

    await expectLater(
      container
          .read(savedEventsControllerProvider.notifier)
          .save(
            UnifiedEvent(
              eventRef: 'post:not-written',
              kind: UnifiedEventKind.postEvent,
              title: 'Nicht gespeichert',
              start: DateTime.utc(2026, 8, 12),
            ),
          ),
      throwsA(
        isA<SavedEventsStoreFailure>().having(
          (SavedEventsStoreFailure failure) => failure.operation,
          'operation',
          SavedEventsStoreOperation.write,
        ),
      ),
    );

    expect(container.read(savedEventsControllerProvider).requireValue, isEmpty);
    expect(await store.readAll(), isEmpty);
  });

  group('the 500-entry cap', () {
    test(
      'declines a save once the cap is reached, without evicting anything',
      () async {
        final List<SavedEventSnapshot> full = List<SavedEventSnapshot>.generate(
          kSavedEventsCap,
          (int i) => _snapshot(eventRef: 'post:$i'),
        );
        final MemorySavedEventsStore store = MemorySavedEventsStore();
        await store.writeAll(full);

        final ProviderContainer container = _containerWith(
          store,
          now: DateTime.utc(2026, 8, 5),
        );
        await container.read(savedEventsControllerProvider.future);

        final bool accepted = await container
            .read(savedEventsControllerProvider.notifier)
            .save(
              UnifiedEvent(
                eventRef: 'post:overflow',
                kind: UnifiedEventKind.postEvent,
                title: 'Zu viel',
                start: DateTime.utc(2026, 8, 12),
              ),
            );

        expect(accepted, isFalse);
        final List<SavedEventSnapshot> current = container
            .read(savedEventsControllerProvider)
            .requireValue;
        expect(current, hasLength(kSavedEventsCap));
        expect(
          current.map((SavedEventSnapshot s) => s.eventRef),
          isNot(contains('post:overflow')),
        );
      },
    );

    test(
      're-saving an already-saved event is a no-op success even at the cap',
      () async {
        final List<SavedEventSnapshot> full = List<SavedEventSnapshot>.generate(
          kSavedEventsCap,
          (int i) => _snapshot(eventRef: 'post:$i'),
        );
        final MemorySavedEventsStore store = MemorySavedEventsStore();
        await store.writeAll(full);
        final ProviderContainer container = _containerWith(
          store,
          now: DateTime.utc(2026, 8, 5),
        );
        await container.read(savedEventsControllerProvider.future);

        final bool accepted = await container
            .read(savedEventsControllerProvider.notifier)
            .save(
              UnifiedEvent(
                eventRef: 'post:0',
                kind: UnifiedEventKind.postEvent,
                title: 'Bereits gespeichert',
                start: DateTime.utc(2026, 8, 10),
              ),
            );
        expect(accepted, isTrue);
        expect(
          container.read(savedEventsControllerProvider).requireValue,
          hasLength(kSavedEventsCap),
        );
      },
    );
  });

  group('unlimited time retention', () {
    test(
      'keeps a snapshot more than 365 days past its end on the next load',
      () async {
        final MemorySavedEventsStore store = MemorySavedEventsStore();
        await store.writeAll(<SavedEventSnapshot>[
          _snapshot(
            eventRef: 'post:long-gone',
            start: DateTime.utc(2025, 1, 1, 10),
            end: DateTime.utc(2025, 1, 1, 12),
          ),
          _snapshot(
            eventRef: 'post:still-kept',
            start: DateTime.utc(2025, 12, 1, 10),
            end: DateTime.utc(2025, 12, 1, 12),
          ),
        ]);

        // Both events remain saved regardless of their age.
        final ProviderContainer container = _containerWith(
          store,
          now: DateTime.utc(2026, 2, 5),
        );
        final List<SavedEventSnapshot> loaded = await container.read(
          savedEventsControllerProvider.future,
        );

        expect(loaded.map((SavedEventSnapshot s) => s.eventRef), <String>[
          'post:long-gone',
          'post:still-kept',
        ]);
        final List<SavedEventSnapshot> persisted = await store.readAll();
        expect(persisted, hasLength(2));
      },
    );

    test('keeps a more recent saved event too', () async {
      final MemorySavedEventsStore store = MemorySavedEventsStore();
      await store.writeAll(<SavedEventSnapshot>[
        _snapshot(
          eventRef: 'post:recent',
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 1, 1, 2),
        ),
      ]);
      final ProviderContainer container = _containerWith(
        store,
        now: DateTime.utc(2026, 6, 1), // ~150 days later
      );
      final List<SavedEventSnapshot> loaded = await container.read(
        savedEventsControllerProvider.future,
      );
      expect(loaded, hasLength(1));
    });
  });

  group('the orphan rule', () {
    test('a successful load whose window covers the snapshot but is missing it '
        'marks it orphaned', () async {
      final MemorySavedEventsStore store = MemorySavedEventsStore();
      await store.writeAll(<SavedEventSnapshot>[
        _snapshot(eventRef: 'post:missing', start: DateTime.utc(2026, 8, 10)),
      ]);
      final ProviderContainer container = _containerWith(
        store,
        now: DateTime.utc(2026, 8, 5),
      );
      await container.read(savedEventsControllerProvider.future);

      await container
          .read(savedEventsControllerProvider.notifier)
          .reconcileAfterSuccessfulLoad(
            loadedEventRefs: const <String>[], // the source no longer has it
            windowFrom: DateTime.utc(2026, 8, 1),
            windowTo: DateTime.utc(2026, 8, 31),
            belongsToThisSource: (SavedEventSnapshot s) =>
                s.kind == UnifiedEventKind.postEvent,
          );

      final List<SavedEventSnapshot> current = container
          .read(savedEventsControllerProvider)
          .requireValue;
      expect(current.single.isOrphaned, isTrue);
    });

    test(
      'a snapshot outside the requested window is left alone (no bare window '
      'edge orphaning)',
      () async {
        final MemorySavedEventsStore store = MemorySavedEventsStore();
        await store.writeAll(<SavedEventSnapshot>[
          _snapshot(eventRef: 'post:later', start: DateTime.utc(2026, 9, 1)),
        ]);
        final ProviderContainer container = _containerWith(
          store,
          now: DateTime.utc(2026, 8, 5),
        );
        await container.read(savedEventsControllerProvider.future);

        await container
            .read(savedEventsControllerProvider.notifier)
            .reconcileAfterSuccessfulLoad(
              loadedEventRefs: const <String>[],
              windowFrom: DateTime.utc(2026, 8, 1),
              windowTo: DateTime.utc(2026, 8, 31), // does not cover Sept 1
              belongsToThisSource: (SavedEventSnapshot s) =>
                  s.kind == UnifiedEventKind.postEvent,
            );

        expect(
          container
              .read(savedEventsControllerProvider)
              .requireValue
              .single
              .isOrphaned,
          isFalse,
        );
      },
    );

    test('snapshot update: a previously orphaned event reappearing in a '
        'successful load is un-orphaned again', () async {
      final MemorySavedEventsStore store = MemorySavedEventsStore();
      await store.writeAll(<SavedEventSnapshot>[
        _snapshot(
          eventRef: 'post:back',
          start: DateTime.utc(2026, 8, 10),
          isOrphaned: true,
        ),
      ]);
      final ProviderContainer container = _containerWith(
        store,
        now: DateTime.utc(2026, 8, 5),
      );
      await container.read(savedEventsControllerProvider.future);

      await container
          .read(savedEventsControllerProvider.notifier)
          .reconcileAfterSuccessfulLoad(
            loadedEventRefs: const <String>['post:back'],
            windowFrom: DateTime.utc(2026, 8, 1),
            windowTo: DateTime.utc(2026, 8, 31),
            belongsToThisSource: (SavedEventSnapshot s) =>
                s.kind == UnifiedEventKind.postEvent,
          );

      expect(
        container
            .read(savedEventsControllerProvider)
            .requireValue
            .single
            .isOrphaned,
        isFalse,
      );
    });

    test(
      'a reconcile call for a different source never touches this snapshot',
      () async {
        final MemorySavedEventsStore store = MemorySavedEventsStore();
        await store.writeAll(<SavedEventSnapshot>[
          _snapshot(
            eventRef: 'calendar:key1',
            kind: UnifiedEventKind.calendarEvent,
            start: DateTime.utc(2026, 8, 10),
            channelSlug: null,
            calendarSlug: 'stura-termine',
          ),
        ]);
        final ProviderContainer container = _containerWith(
          store,
          now: DateTime.utc(2026, 8, 5),
        );
        await container.read(savedEventsControllerProvider.future);

        // A post-events reconcile call must never touch a calendar-event
        // snapshot, even though its window covers the same date.
        await container
            .read(savedEventsControllerProvider.notifier)
            .reconcileAfterSuccessfulLoad(
              loadedEventRefs: const <String>[],
              windowFrom: DateTime.utc(2026, 8, 1),
              windowTo: DateTime.utc(2026, 8, 31),
              belongsToThisSource: (SavedEventSnapshot s) =>
                  s.kind == UnifiedEventKind.postEvent,
            );

        expect(
          container
              .read(savedEventsControllerProvider)
              .requireValue
              .single
              .isOrphaned,
          isFalse,
        );
      },
    );
  });

  group('offline/error never orphans', () {
    test(
      'a network failure served from cache leaves saved snapshots untouched',
      () async {
        final MemorySavedEventsStore store = MemorySavedEventsStore();
        await store.writeAll(<SavedEventSnapshot>[
          _snapshot(
            eventRef: 'post:untouched',
            start: DateTime.utc(2026, 8, 10),
          ),
        ]);

        bool fail = false;
        final FakeHttpAdapter adapter = FakeHttpAdapter((
          RequestOptions options,
        ) {
          if (fail) {
            throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            );
          }
          return FakeHttpResponse(
            envelope(
              <Object>[], // the live response never carries this event...
              meta: <String, dynamic>{
                'from': '2026-08-01',
                'to': '2026-08-31',
                'pagination': <String, dynamic>{
                  'page': 1,
                  'pageSize': 50,
                  'total': 0,
                  'totalPages': 1,
                },
              },
            ),
          );
        });

        final ProviderContainer container = ProviderContainer(
          overrides: <Override>[
            savedEventsStoreProvider.overrideWithValue(store),
            savedEventsClockProvider.overrideWithValue(
              () => DateTime.utc(2026, 8, 5),
            ),
            localeCodeProvider.overrideWithValue('de'),
            contentCacheProvider.overrideWithValue(
              SafeContentCache(MemoryContentCache()),
            ),
            apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
          ],
        );
        addTearDown(container.dispose);
        await container.read(savedEventsControllerProvider.future);

        // First (live, successful) load: the window covers the snapshot and
        // the response is missing it — this legitimately orphans it.
        await container.read(eventPostsOverviewProvider.future);
        expect(
          container
              .read(savedEventsControllerProvider)
              .requireValue
              .single
              .isOrphaned,
          isTrue,
          reason:
              'sanity check: the live path does orphan when genuinely missing',
        );

        // Reset it back, then force every further load through the cache
        // fallback path (a real network failure) and confirm it is never
        // touched again from there.
        await container
            .read(savedEventsControllerProvider.notifier)
            .reconcileAfterSuccessfulLoad(
              loadedEventRefs: const <String>['post:untouched'],
              windowFrom: DateTime.utc(2026, 8, 1),
              windowTo: DateTime.utc(2026, 8, 31),
              belongsToThisSource: (SavedEventSnapshot s) =>
                  s.kind == UnifiedEventKind.postEvent,
            );
        expect(
          container
              .read(savedEventsControllerProvider)
              .requireValue
              .single
              .isOrphaned,
          isFalse,
        );

        fail = true;
        container.invalidate(eventPostsOverviewProvider);
        await container.read(eventPostsOverviewProvider.future);

        expect(
          container
              .read(savedEventsControllerProvider)
              .requireValue
              .single
              .isOrphaned,
          isFalse,
          reason: 'a cache-fallback response must never set the orphan flag',
        );
      },
    );
  });
}

class _FailingSavedEventsStore implements SavedEventsStore {
  @override
  Future<List<SavedEventSnapshot>> readAll() async =>
      const <SavedEventSnapshot>[];

  @override
  Future<void> writeAll(List<SavedEventSnapshot> snapshots) async =>
      throw SavedEventsStoreFailure(
        SavedEventsStoreOperation.write,
        StateError('failed'),
      );

  @override
  Future<void> upsert(SavedEventSnapshot snapshot) async =>
      throw SavedEventsStoreFailure(
        SavedEventsStoreOperation.write,
        StateError('failed'),
      );

  @override
  Future<void> upsertAll(Iterable<SavedEventSnapshot> snapshots) async =>
      throw SavedEventsStoreFailure(
        SavedEventsStoreOperation.write,
        StateError('failed'),
      );

  @override
  Future<void> delete(String eventRef) async => throw SavedEventsStoreFailure(
    SavedEventsStoreOperation.write,
    StateError('failed'),
  );
}
