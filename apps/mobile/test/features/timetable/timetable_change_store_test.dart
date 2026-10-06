// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/features/timetable/application/timetable_change.dart';
import 'package:campus_koethen/features/timetable/data/encrypted_timetable_change_store.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_test/flutter_test.dart';

TimetableEntry lesson({String id = 'stable-id', String room = 'A1'}) =>
    TimetableEntry(
      id: id,
      start: DateTime.utc(2026, 10, 12, 8),
      end: DateTime.utc(2026, 10, 12, 10),
      title: 'Mathematik',
      rooms: <TimetableRoom>[TimetableRoom(shortName: room)],
      status: TimetableEntryStatus.regular,
    );

void main() {
  test('persists a baseline and returns only later changes', () async {
    final EncryptedTimetableChangeStore store = EncryptedTimetableChangeStore(
      _MemoryBox(),
    );
    const TimetableChangeScope scope = TimetableChangeScope(
      groupId: 'campus-group',
      rangeKey: '2026-10-12',
    );

    expect(
      await store.observe(
        scope: scope,
        entries: <TimetableEntry>[lesson()],
        detectedAt: DateTime.utc(2026, 10, 6),
      ),
      isEmpty,
    );
    final List<TimetableChange> changes = await store.observe(
      scope: scope,
      entries: <TimetableEntry>[lesson(room: 'B2')],
      detectedAt: DateTime.utc(2026, 10, 7),
    );

    expect(changes.single.kind, TimetableChangeKind.room);
    expect(await store.readPending(), hasLength(1));
    await store.acknowledgeGroup('campus-group');
    expect(await store.readPending(), isEmpty);
  });

  test('stores at most fifty unread hints across every scope', () async {
    final EncryptedTimetableChangeStore store = EncryptedTimetableChangeStore(
      _MemoryBox(),
    );
    final List<TimetableEntry> before = <TimetableEntry>[
      for (int index = 0; index < 30; index++) lesson(id: 'lesson-$index'),
    ];
    final List<TimetableEntry> after = <TimetableEntry>[
      for (int index = 0; index < 30; index++)
        lesson(id: 'lesson-$index', room: 'B2'),
    ];
    for (final (String group, DateTime detectedAt) in <(String, DateTime)>[
      ('older', DateTime.utc(2026, 10, 6)),
      ('newer', DateTime.utc(2026, 10, 7)),
    ]) {
      final TimetableChangeScope scope = TimetableChangeScope(
        groupId: group,
        rangeKey: '2026-10-12',
      );
      await store.observe(
        scope: scope,
        entries: before,
        detectedAt: detectedAt.subtract(const Duration(hours: 1)),
      );
      await store.observe(scope: scope, entries: after, detectedAt: detectedAt);
    }

    expect(await store.readPending(), hasLength(50));
    await store.acknowledgeGroup('newer');
    expect(
      await store.readPending(),
      hasLength(20),
      reason: 'ten older hints must have been evicted, not merely hidden',
    );
  });
}

class _MemoryBox extends EncryptedBox {
  _MemoryBox() : super(boxName: 'unused', keyStorageKey: 'unused');

  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<bool> writeChecked(String key, String next) async {
    value = next;
    return true;
  }

  @override
  Future<EncryptedBoxWipeResult> wipeChecked() async {
    value = null;
    return const EncryptedBoxWipeResult(keyAbsent: true, boxAbsent: true);
  }
}
