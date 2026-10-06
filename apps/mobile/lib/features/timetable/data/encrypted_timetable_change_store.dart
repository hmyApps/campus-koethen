// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';

import '../../../core/cache/encrypted_box.dart';
import '../application/timetable_change.dart';
import 'timetable_models.dart';

/// Encrypted baselines and unread hints for a bounded set of timetable ranges.
/// One checked write stores baseline and new hints together, so a process death
/// cannot leave a new baseline without its corresponding user-visible change.
class EncryptedTimetableChangeStore {
  EncryptedTimetableChangeStore([EncryptedBox? box])
    : _box =
          box ??
          EncryptedBox(
            boxName: 'campus_timetable_changes_v1',
            keyStorageKey: 'timetable.changes.key.v1',
          );

  final EncryptedBox _box;
  Future<void> _queue = Future<void>.value();

  static const String _stateKey = 'state';
  static const int _maxScopes = 12;
  static const int _maxPending = 50;

  Future<List<TimetableChange>> observe({
    required TimetableChangeScope scope,
    required List<TimetableEntry> entries,
    required DateTime detectedAt,
  }) => _serialized<List<TimetableChange>>(() async {
    final List<_ScopeState> scopes = await _readScopes();
    final int index = scopes.indexWhere((_ScopeState s) => s.scope == scope);
    final _ScopeState? old = index < 0 ? null : scopes[index];
    final List<TimetableChange> detected = detectTimetableChanges(
      previous: old?.entries,
      current: entries,
      detectedAt: detectedAt,
    ).map((TimetableChange change) => change.inScope(scope)).toList();
    final List<TimetableChange> pending = _deduplicate(<TimetableChange>[
      ...?old?.pending,
      ...detected,
    ]);
    final _ScopeState next = _ScopeState(
      scope: scope,
      observedAt: detectedAt,
      entries: List<TimetableEntry>.unmodifiable(entries),
      pending: pending,
    );
    if (index < 0) {
      scopes.add(next);
    } else {
      scopes[index] = next;
    }
    scopes.sort(
      (_ScopeState a, _ScopeState b) => b.observedAt.compareTo(a.observedAt),
    );
    if (scopes.length > _maxScopes) {
      scopes.removeRange(_maxScopes, scopes.length);
    }
    await _writeScopes(_capPending(scopes));
    return detected;
  });

  Future<List<TimetableChange>> readPending() =>
      _serialized<List<TimetableChange>>(() async {
        final List<TimetableChange> all =
            <TimetableChange>[
              for (final _ScopeState scope in await _readScopes())
                ...scope.pending,
            ]..sort(
              (TimetableChange a, TimetableChange b) =>
                  b.detectedAt.compareTo(a.detectedAt),
            );
        return List<TimetableChange>.unmodifiable(all.take(_maxPending));
      });

  Future<void> acknowledgeGroup(String groupId) => _serialized<void>(() async {
    final List<_ScopeState> scopes = await _readScopes();
    final List<_ScopeState> next = <_ScopeState>[
      for (final _ScopeState scope in scopes)
        scope.scope.groupId == groupId
            ? scope.copyWith(pending: const <TimetableChange>[])
            : scope,
    ];
    await _writeScopes(next);
  });

  Future<void> clear() => _serialized<void>(() async {
    final EncryptedBoxWipeResult result = await _box.wipeChecked();
    if (!result.isComplete) throw StateError('Timetable change wipe failed');
  });

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<_ScopeState>> _readScopes() async {
    final String? raw = await _box.read(_stateKey);
    if (raw == null) return <_ScopeState>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['scopes'] is! List) return <_ScopeState>[];
      return (decoded['scopes'] as List)
          .whereType<Map>()
          .map(
            (Map value) =>
                _ScopeState.fromJson(Map<String, dynamic>.from(value)),
          )
          .whereType<_ScopeState>()
          .toList();
    } catch (_) {
      return <_ScopeState>[];
    }
  }

  Future<void> _writeScopes(List<_ScopeState> scopes) async {
    final String payload = jsonEncode(<String, Object>{
      'scopes': scopes.map((_ScopeState state) => state.toJson()).toList(),
    });
    if (!await _box.writeChecked(_stateKey, payload)) {
      throw StateError('Timetable change write failed');
    }
  }

  static List<TimetableChange> _deduplicate(List<TimetableChange> changes) {
    final Set<String> seen = <String>{};
    final List<TimetableChange> result = <TimetableChange>[];
    for (final TimetableChange change in changes.reversed) {
      final String key =
          '${change.entryId}|${change.kind.name}|'
          '${change.oldStart.toUtc().toIso8601String()}|'
          '${change.newStart?.toUtc().toIso8601String()}|'
          '${change.oldRooms.join(',')}|${change.newRooms.join(',')}';
      if (seen.add(key)) result.add(change);
    }
    return result.reversed.take(_maxPending).toList(growable: false);
  }

  /// Retains the newest unread hints globally, not fifty per stored week.
  /// Baselines remain available for comparison even when all their hints were
  /// evicted, so the bound reduces encrypted storage without losing change
  /// detection continuity.
  static List<_ScopeState> _capPending(List<_ScopeState> scopes) {
    final List<TimetableChange> newest =
        <TimetableChange>[
          for (final _ScopeState scope in scopes) ...scope.pending,
        ]..sort(
          (TimetableChange a, TimetableChange b) =>
              b.detectedAt.compareTo(a.detectedAt),
        );
    final Set<TimetableChange> retained = newest.take(_maxPending).toSet();
    return <_ScopeState>[
      for (final _ScopeState scope in scopes)
        scope.copyWith(
          pending: scope.pending
              .where((TimetableChange change) => retained.contains(change))
              .toList(growable: false),
        ),
    ];
  }
}

class _ScopeState {
  const _ScopeState({
    required this.scope,
    required this.observedAt,
    required this.entries,
    required this.pending,
  });

  final TimetableChangeScope scope;
  final DateTime observedAt;
  final List<TimetableEntry> entries;
  final List<TimetableChange> pending;

  _ScopeState copyWith({List<TimetableChange>? pending}) => _ScopeState(
    scope: scope,
    observedAt: observedAt,
    entries: entries,
    pending: pending ?? this.pending,
  );

  Map<String, Object> toJson() => <String, Object>{
    'groupId': scope.groupId,
    'rangeKey': scope.rangeKey,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'entries': entries.map(_entryToJson).toList(),
    'pending': pending.map(_changeToJson).toList(),
  };

  static _ScopeState? fromJson(Map<String, dynamic> map) {
    final String? groupId = map['groupId'] as String?;
    final String? rangeKey = map['rangeKey'] as String?;
    final DateTime? observedAt = DateTime.tryParse(
      map['observedAt'] as String? ?? '',
    );
    if (groupId == null || rangeKey == null || observedAt == null) return null;
    final TimetableChangeScope scope = TimetableChangeScope(
      groupId: groupId,
      rangeKey: rangeKey,
    );
    return _ScopeState(
      scope: scope,
      observedAt: observedAt,
      entries: (map['entries'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map((Map value) => _entryFromJson(Map<String, dynamic>.from(value)))
          .whereType<TimetableEntry>()
          .toList(),
      pending: (map['pending'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map(
            (Map value) =>
                _changeFromJson(Map<String, dynamic>.from(value), scope),
          )
          .whereType<TimetableChange>()
          .toList(),
    );
  }
}

Map<String, Object> _entryToJson(TimetableEntry entry) => <String, Object>{
  'id': entry.id,
  'start': entry.start.toUtc().toIso8601String(),
  'end': entry.end.toUtc().toIso8601String(),
  'title': entry.displayTitle ?? '',
  'status': entry.status.name,
  'rooms': entry.rooms.map((TimetableRoom room) => room.label).toList(),
};

TimetableEntry? _entryFromJson(Map<String, dynamic> map) {
  final String? id = map['id'] as String?;
  final DateTime? start = DateTime.tryParse(map['start'] as String? ?? '');
  final DateTime? end = DateTime.tryParse(map['end'] as String? ?? '');
  if (id == null || start == null || end == null) return null;
  final String statusName = map['status'] as String? ?? '';
  final TimetableEntryStatus status = TimetableEntryStatus.values.firstWhere(
    (TimetableEntryStatus value) => value.name == statusName,
    orElse: () => TimetableEntryStatus.unknown,
  );
  return TimetableEntry(
    id: id,
    start: start,
    end: end,
    title: map['title'] as String?,
    status: status,
    rooms: (map['rooms'] as List? ?? const <Object>[])
        .whereType<String>()
        .map((String room) => TimetableRoom(shortName: room))
        .toList(),
  );
}

Map<String, Object?> _changeToJson(TimetableChange change) => <String, Object?>{
  'entryId': change.entryId,
  'title': change.title,
  'kind': change.kind.name,
  'detectedAt': change.detectedAt.toUtc().toIso8601String(),
  'oldStart': change.oldStart.toUtc().toIso8601String(),
  'newStart': change.newStart?.toUtc().toIso8601String(),
  'oldRooms': change.oldRooms,
  'newRooms': change.newRooms,
};

TimetableChange? _changeFromJson(
  Map<String, dynamic> map,
  TimetableChangeScope scope,
) {
  final String? id = map['entryId'] as String?;
  final DateTime? detectedAt = DateTime.tryParse(
    map['detectedAt'] as String? ?? '',
  );
  final DateTime? oldStart = DateTime.tryParse(
    map['oldStart'] as String? ?? '',
  );
  final TimetableChangeKind? kind = TimetableChangeKind.values
      .where((TimetableChangeKind value) => value.name == map['kind'])
      .firstOrNull;
  if (id == null || detectedAt == null || oldStart == null || kind == null) {
    return null;
  }
  return TimetableChange(
    entryId: id,
    title: map['title'] as String? ?? '',
    kind: kind,
    detectedAt: detectedAt,
    oldStart: oldStart,
    newStart: DateTime.tryParse(map['newStart'] as String? ?? ''),
    oldRooms: (map['oldRooms'] as List? ?? const <Object>[])
        .whereType<String>()
        .toList(),
    newRooms: (map['newRooms'] as List? ?? const <Object>[])
        .whereType<String>()
        .toList(),
    groupId: scope.groupId,
    rangeKey: scope.rangeKey,
  );
}
