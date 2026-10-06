// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../data/timetable_models.dart';

enum TimetableChangeKind { cancelled, room, time }

@immutable
class TimetableChange {
  const TimetableChange({
    required this.entryId,
    required this.title,
    required this.kind,
    required this.detectedAt,
    required this.oldStart,
    required this.newStart,
    this.oldRooms = const <String>[],
    this.newRooms = const <String>[],
    this.groupId = '',
    this.rangeKey = '',
  });

  final String entryId;
  final String title;
  final TimetableChangeKind kind;
  final DateTime detectedAt;
  final DateTime oldStart;
  final DateTime? newStart;
  final List<String> oldRooms;
  final List<String> newRooms;
  final String groupId;
  final String rangeKey;

  TimetableChange inScope(TimetableChangeScope scope) => TimetableChange(
    entryId: entryId,
    title: title,
    kind: kind,
    detectedAt: detectedAt,
    oldStart: oldStart,
    newStart: newStart,
    oldRooms: oldRooms,
    newRooms: newRooms,
    groupId: scope.groupId,
    rangeKey: scope.rangeKey,
  );
}

@immutable
class TimetableChangeScope {
  const TimetableChangeScope({required this.groupId, required this.rangeKey});

  final String groupId;
  final String rangeKey;

  @override
  bool operator ==(Object other) =>
      other is TimetableChangeScope &&
      other.groupId == groupId &&
      other.rangeKey == rangeKey;

  @override
  int get hashCode => Object.hash(groupId, rangeKey);
}

/// Compares two successful snapshots of exactly the same timetable range.
/// Stable Campus entry ids are the only identity; title/time heuristics are
/// intentionally never used. A first snapshot establishes a baseline.
List<TimetableChange> detectTimetableChanges({
  required List<TimetableEntry>? previous,
  required List<TimetableEntry> current,
  required DateTime detectedAt,
}) {
  if (previous == null) return const <TimetableChange>[];
  final Map<String, TimetableEntry> after = <String, TimetableEntry>{
    for (final TimetableEntry entry in current) entry.id: entry,
  };
  final List<TimetableChange> changes = <TimetableChange>[];

  for (final TimetableEntry old in previous) {
    if (!old.end.isAfter(detectedAt)) continue;
    final TimetableEntry? next = after[old.id];
    final bool cancelled =
        next == null ||
        (old.status != TimetableEntryStatus.cancelled &&
            next.status == TimetableEntryStatus.cancelled);
    if (cancelled) {
      changes.add(
        _change(old, next, TimetableChangeKind.cancelled, detectedAt),
      );
      continue;
    }
    final List<String> oldRooms = _rooms(old);
    final List<String> newRooms = _rooms(next);
    if (!_sameStrings(oldRooms, newRooms)) {
      changes.add(_change(old, next, TimetableChangeKind.room, detectedAt));
    }
    if (old.start != next.start || old.end != next.end) {
      changes.add(_change(old, next, TimetableChangeKind.time, detectedAt));
    }
  }
  return List<TimetableChange>.unmodifiable(changes);
}

TimetableChange _change(
  TimetableEntry old,
  TimetableEntry? next,
  TimetableChangeKind kind,
  DateTime detectedAt,
) => TimetableChange(
  entryId: old.id,
  title: old.displayTitle ?? '',
  kind: kind,
  detectedAt: detectedAt,
  oldStart: old.start,
  newStart: next?.start,
  oldRooms: _rooms(old),
  newRooms: next == null ? const <String>[] : _rooms(next),
);

List<String> _rooms(TimetableEntry entry) =>
    entry.rooms.map((TimetableRoom room) => room.label).toSet().toList()
      ..sort();

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
