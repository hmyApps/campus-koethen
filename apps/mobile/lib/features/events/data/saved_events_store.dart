// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../domain/saved_event_snapshot.dart';

enum SavedEventsStoreOperation { open, migrate, read, write }

/// A typed persistence failure for the user's saved-event collection.
class SavedEventsStoreFailure implements Exception {
  const SavedEventsStoreFailure(this.operation, this.cause);

  final SavedEventsStoreOperation operation;
  final Object cause;

  @override
  String toString() => 'SavedEventsStoreFailure($operation, $cause)';
}

/// Persists the offline saved-events list ("Meine gemerkten Events").
///
/// Each snapshot is stored under its stable [SavedEventSnapshot.eventRef].
/// Failures are surfaced because these are user choices, not a disposable
/// content cache.
abstract interface class SavedEventsStore {
  Future<List<SavedEventSnapshot>> readAll();
  Future<void> writeAll(List<SavedEventSnapshot> snapshots);
  Future<void> upsert(SavedEventSnapshot snapshot);
  Future<void> upsertAll(Iterable<SavedEventSnapshot> snapshots);
  Future<void> delete(String eventRef);
}

class HiveSavedEventsStore implements SavedEventsStore {
  factory HiveSavedEventsStore({
    Box<String>? box,
    Future<void> Function()? initializeHive,
    Future<Box<String>> Function(String name)? openBox,
  }) => HiveSavedEventsStore._(
    box,
    initializeHive ?? (() => Hive.initFlutter()),
    openBox ?? ((String name) => Hive.openBox<String>(name)),
  );

  HiveSavedEventsStore._(this._box, this._initializeHive, this._openBox);

  static const String boxName = 'campus_saved_events_v1';
  static const String _itemsKey = 'items';
  static const String _schemaKey = '_schema';
  static const String _schemaVersion = '2';
  static const String _eventPrefix = 'event.';

  Box<String>? _box;
  final Future<void> Function() _initializeHive;
  final Future<Box<String>> Function(String name) _openBox;
  Future<Box<String>>? _readyFuture;

  Future<Box<String>> _ready() async {
    final Future<Box<String>>? pending = _readyFuture;
    if (pending != null) return pending;
    final Future<Box<String>> created = _openAndMigrate();
    _readyFuture = created;
    try {
      return await created;
    } catch (_) {
      if (identical(_readyFuture, created)) _readyFuture = null;
      rethrow;
    }
  }

  Future<Box<String>> _openAndMigrate() async {
    final Box<String> box = await _open();
    await _migrate(box);
    return box;
  }

  Future<Box<String>> _open() async {
    if (_box != null && _box!.isOpen) return _box!;
    try {
      await _initializeHive();
      _box = await _openBox(boxName);
      return _box!;
    } catch (error) {
      throw SavedEventsStoreFailure(SavedEventsStoreOperation.open, error);
    }
  }

  Future<void> _migrate(Box<String> box) async {
    try {
      if (box.get(_schemaKey) == _schemaVersion) return;
      final String? legacy = box.get(_itemsKey);
      final List<SavedEventSnapshot> snapshots = legacy == null
          ? const <SavedEventSnapshot>[]
          : _decodeSnapshots(legacy);
      await box.putAll(<String, String>{
        for (final SavedEventSnapshot snapshot in snapshots)
          _eventKey(snapshot.eventRef): jsonEncode(snapshot.toJson()),
        _schemaKey: _schemaVersion,
      });
      try {
        await box.delete(_itemsKey);
      } catch (_) {}
    } catch (error) {
      if (error is SavedEventsStoreFailure) rethrow;
      throw SavedEventsStoreFailure(SavedEventsStoreOperation.migrate, error);
    }
  }

  @override
  Future<List<SavedEventSnapshot>> readAll() async {
    try {
      final Box<String> box = await _ready();
      final List<SavedEventSnapshot> snapshots = <SavedEventSnapshot>[];
      for (final Object key in box.keys) {
        if (key is! String || !key.startsWith(_eventPrefix)) continue;
        final String? raw = box.get(key);
        if (raw == null) throw const FormatException('Missing saved event');
        final SavedEventSnapshot? snapshot = SavedEventSnapshot.fromJson(
          jsonDecode(raw),
        );
        if (snapshot == null) {
          throw const FormatException('Invalid saved event');
        }
        snapshots.add(snapshot);
      }
      snapshots.sort(_compareSnapshots);
      return snapshots;
    } catch (error) {
      if (error is SavedEventsStoreFailure) rethrow;
      throw SavedEventsStoreFailure(SavedEventsStoreOperation.read, error);
    }
  }

  @override
  Future<void> writeAll(List<SavedEventSnapshot> snapshots) async {
    try {
      final Box<String> box = await _ready();
      final Set<String> nextKeys = snapshots
          .map((SavedEventSnapshot snapshot) => _eventKey(snapshot.eventRef))
          .toSet();
      await box.putAll(<String, String>{
        for (final SavedEventSnapshot snapshot in snapshots)
          _eventKey(snapshot.eventRef): jsonEncode(snapshot.toJson()),
      });
      await box.deleteAll(<Object>[
        for (final Object key in box.keys)
          if (key is String &&
              key.startsWith(_eventPrefix) &&
              !nextKeys.contains(key))
            key,
      ]);
    } catch (error) {
      if (error is SavedEventsStoreFailure) rethrow;
      throw SavedEventsStoreFailure(SavedEventsStoreOperation.write, error);
    }
  }

  @override
  Future<void> upsert(SavedEventSnapshot snapshot) =>
      upsertAll(<SavedEventSnapshot>[snapshot]);

  @override
  Future<void> upsertAll(Iterable<SavedEventSnapshot> snapshots) async {
    try {
      final Box<String> box = await _ready();
      await box.putAll(<String, String>{
        for (final SavedEventSnapshot snapshot in snapshots)
          _eventKey(snapshot.eventRef): jsonEncode(snapshot.toJson()),
      });
    } catch (error) {
      if (error is SavedEventsStoreFailure) rethrow;
      throw SavedEventsStoreFailure(SavedEventsStoreOperation.write, error);
    }
  }

  @override
  Future<void> delete(String eventRef) async {
    try {
      final Box<String> box = await _ready();
      await box.delete(_eventKey(eventRef));
    } catch (error) {
      if (error is SavedEventsStoreFailure) rethrow;
      throw SavedEventsStoreFailure(SavedEventsStoreOperation.write, error);
    }
  }

  static String _eventKey(String eventRef) => '$_eventPrefix$eventRef';

  static List<SavedEventSnapshot> _decodeSnapshots(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Invalid saved-event list');
    }
    final List<SavedEventSnapshot> snapshots = <SavedEventSnapshot>[];
    for (final Object? value in decoded) {
      final SavedEventSnapshot? snapshot = SavedEventSnapshot.fromJson(value);
      if (snapshot == null) {
        throw const FormatException('Invalid saved event');
      }
      snapshots.add(snapshot);
    }
    return snapshots;
  }

  static int _compareSnapshots(
    SavedEventSnapshot left,
    SavedEventSnapshot right,
  ) {
    final int bySavedAt = left.savedAt.compareTo(right.savedAt);
    return bySavedAt != 0 ? bySavedAt : left.eventRef.compareTo(right.eventRef);
  }
}

/// In-memory store used by tests and as a safe fallback.
class MemorySavedEventsStore implements SavedEventsStore {
  List<SavedEventSnapshot> _items = const <SavedEventSnapshot>[];

  @override
  Future<List<SavedEventSnapshot>> readAll() async =>
      List<SavedEventSnapshot>.unmodifiable(_items);

  @override
  Future<void> writeAll(List<SavedEventSnapshot> snapshots) async {
    _items = List<SavedEventSnapshot>.unmodifiable(snapshots);
  }

  @override
  Future<void> upsert(SavedEventSnapshot snapshot) =>
      upsertAll(<SavedEventSnapshot>[snapshot]);

  @override
  Future<void> upsertAll(Iterable<SavedEventSnapshot> snapshots) async {
    final List<SavedEventSnapshot> next = List<SavedEventSnapshot>.of(_items);
    for (final SavedEventSnapshot snapshot in snapshots) {
      final int index = next.indexWhere(
        (SavedEventSnapshot item) => item.eventRef == snapshot.eventRef,
      );
      if (index < 0) {
        next.add(snapshot);
      } else {
        next[index] = snapshot;
      }
    }
    _items = List<SavedEventSnapshot>.unmodifiable(next);
  }

  @override
  Future<void> delete(String eventRef) async {
    _items = List<SavedEventSnapshot>.unmodifiable(
      _items.where(
        (SavedEventSnapshot snapshot) => snapshot.eventRef != eventRef,
      ),
    );
  }
}
