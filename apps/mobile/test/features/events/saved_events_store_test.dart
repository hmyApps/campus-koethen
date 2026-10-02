// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

SavedEventSnapshot _snapshot(String eventRef, DateTime savedAt) =>
    SavedEventSnapshot(
      eventRef: eventRef,
      kind: UnifiedEventKind.postEvent,
      title: eventRef,
      start: DateTime.utc(2026, 8, 10),
      savedAt: savedAt,
    );

void main() {
  late Directory directory;
  late Box<String> box;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('saved-events-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<String>('saved-events');
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('migrates the legacy list once without losing a snapshot', () async {
    final List<SavedEventSnapshot> legacy = <SavedEventSnapshot>[
      _snapshot('post:a', DateTime.utc(2026, 8, 1)),
      _snapshot('post:b', DateTime.utc(2026, 8, 2)),
    ];
    await box.put(
      'items',
      jsonEncode(
        legacy.map((SavedEventSnapshot item) => item.toJson()).toList(),
      ),
    );
    final HiveSavedEventsStore store = HiveSavedEventsStore(box: box);

    expect(
      (await store.readAll()).map((SavedEventSnapshot item) => item.eventRef),
      <String>['post:a', 'post:b'],
    );
    expect(box.get('items'), isNull);
    expect(
      box.keys.where((dynamic key) => '$key'.startsWith('event.')),
      hasLength(2),
    );

    final HiveSavedEventsStore reopened = HiveSavedEventsStore(box: box);
    expect(
      (await reopened.readAll()).map(
        (SavedEventSnapshot item) => item.eventRef,
      ),
      <String>['post:a', 'post:b'],
    );
  });

  test('updating one snapshot leaves the other ID entry intact', () async {
    final HiveSavedEventsStore store = HiveSavedEventsStore(box: box);
    final SavedEventSnapshot first = _snapshot(
      'post:a',
      DateTime.utc(2026, 8, 1),
    );
    final SavedEventSnapshot second = _snapshot(
      'post:b',
      DateTime.utc(2026, 8, 2),
    );
    await store.writeAll(<SavedEventSnapshot>[first, second]);
    final String? untouched = box.get('event.post:b');

    await store.upsert(first.copyWith(isOrphaned: true));

    expect(box.get('event.post:b'), untouched);
    expect((await store.readAll()).first.isOrphaned, isTrue);
  });

  test('a corrupt entry is a typed read error, not an empty list', () async {
    final HiveSavedEventsStore store = HiveSavedEventsStore(box: box);
    await store.readAll();
    await box.put('event.broken', '{not-json');

    await expectLater(
      store.readAll(),
      throwsA(
        isA<SavedEventsStoreFailure>().having(
          (SavedEventsStoreFailure failure) => failure.operation,
          'operation',
          SavedEventsStoreOperation.read,
        ),
      ),
    );
  });
}
