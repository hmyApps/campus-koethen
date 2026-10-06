// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/timetable/application/timetable_change.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _day = DateTime.utc(2026, 10, 12, 8);

TimetableEntry lesson({
  required String id,
  DateTime? start,
  DateTime? end,
  String room = 'A1',
  TimetableEntryStatus status = TimetableEntryStatus.regular,
}) => TimetableEntry(
  id: id,
  start: start ?? _day,
  end: end ?? _day.add(const Duration(hours: 2)),
  title: 'Mathematik',
  rooms: <TimetableRoom>[TimetableRoom(shortName: room)],
  status: status,
);

void main() {
  test('first snapshot is only a baseline', () {
    expect(
      detectTimetableChanges(
        previous: null,
        current: <TimetableEntry>[lesson(id: 'one')],
        detectedAt: DateTime.utc(2026, 10, 6),
      ),
      isEmpty,
    );
  });

  test('detects cancellation, room and time changes by stable id', () {
    final List<TimetableEntry> before = <TimetableEntry>[
      lesson(id: 'cancel'),
      lesson(id: 'room'),
      lesson(id: 'time'),
    ];
    final List<TimetableEntry> after = <TimetableEntry>[
      lesson(id: 'cancel', status: TimetableEntryStatus.cancelled),
      lesson(id: 'room', room: 'B2'),
      lesson(
        id: 'time',
        start: _day.add(const Duration(hours: 1)),
        end: _day.add(const Duration(hours: 3)),
      ),
    ];

    final List<TimetableChange> changes = detectTimetableChanges(
      previous: before,
      current: after,
      detectedAt: DateTime.utc(2026, 10, 6),
    );

    expect(changes.map((TimetableChange c) => c.kind), <TimetableChangeKind>[
      TimetableChangeKind.cancelled,
      TimetableChangeKind.room,
      TimetableChangeKind.time,
    ]);
  });

  test('a removed future entry is treated as a cancellation', () {
    final List<TimetableChange> changes = detectTimetableChanges(
      previous: <TimetableEntry>[lesson(id: 'gone')],
      current: const <TimetableEntry>[],
      detectedAt: DateTime.utc(2026, 10, 6),
    );

    expect(changes.single.kind, TimetableChangeKind.cancelled);
  });

  test('does not report already finished or unchanged entries', () {
    final TimetableEntry old = lesson(
      id: 'old',
      start: DateTime.utc(2026, 10, 1, 8),
      end: DateTime.utc(2026, 10, 1, 10),
    );
    expect(
      detectTimetableChanges(
        previous: <TimetableEntry>[
          old,
          lesson(id: 'same'),
        ],
        current: <TimetableEntry>[lesson(id: 'same')],
        detectedAt: DateTime.utc(2026, 10, 6),
      ),
      isEmpty,
    );
  });
}
