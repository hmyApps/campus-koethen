// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/saved_events_store.dart';
import '../domain/saved_event_snapshot.dart';
import '../domain/saved_events_rules.dart';
import '../domain/unified_event.dart';

/// Riverpod front end of [SavedEventsStore], applying cap and orphan rules.
/// State changes become visible only after the store confirms the commit.
class SavedEventsController extends AsyncNotifier<List<SavedEventSnapshot>> {
  SavedEventsStore get _store => ref.read(savedEventsStoreProvider);
  DateTime Function() get _now => ref.read(savedEventsClockProvider);

  @override
  Future<List<SavedEventSnapshot>> build() => _store.readAll();

  bool get acceptsWrites => state.hasValue && !state.isLoading;

  Future<bool> save(UnifiedEvent event) async {
    if (!acceptsWrites) return false;
    final List<SavedEventSnapshot> current = state.requireValue;
    if (current.any((SavedEventSnapshot s) => s.eventRef == event.eventRef)) {
      return true;
    }
    if (!canAddSavedEvent(current)) return false;

    final SavedEventSnapshot added = SavedEventSnapshot.fromUnifiedEvent(
      event,
      savedAt: _now(),
    );
    await _store.upsert(added);
    state = AsyncData<List<SavedEventSnapshot>>(
      List<SavedEventSnapshot>.unmodifiable(<SavedEventSnapshot>[
        ...current,
        added,
      ]),
    );
    return true;
  }

  Future<void> remove(String eventRef) async {
    if (!acceptsWrites) return;
    final List<SavedEventSnapshot> current = state.requireValue;
    final List<SavedEventSnapshot> next = current
        .where((SavedEventSnapshot s) => s.eventRef != eventRef)
        .toList();
    if (next.length == current.length) return;
    await _store.delete(eventRef);
    state = AsyncData<List<SavedEventSnapshot>>(
      List<SavedEventSnapshot>.unmodifiable(next),
    );
  }

  bool isSaved(String eventRef) => (state.value ?? const <SavedEventSnapshot>[])
      .any((SavedEventSnapshot s) => s.eventRef == eventRef);

  Future<void> reconcileAfterSuccessfulLoad({
    required Iterable<String> loadedEventRefs,
    required DateTime windowFrom,
    required DateTime windowTo,
    required bool Function(SavedEventSnapshot snapshot) belongsToThisSource,
  }) async {
    if (!acceptsWrites) return;
    final List<SavedEventSnapshot> current = state.requireValue;
    if (current.isEmpty) return;
    final List<SavedEventSnapshot> next = reconcileOrphanStatus(
      saved: current,
      loadedEventRefs: loadedEventRefs.toSet(),
      windowFrom: windowFrom,
      windowTo: windowTo,
      belongsToThisSource: belongsToThisSource,
    );
    final List<SavedEventSnapshot> changed = <SavedEventSnapshot>[
      for (int i = 0; i < next.length; i++)
        if (next[i].isOrphaned != current[i].isOrphaned) next[i],
    ];
    if (changed.isEmpty) return;
    await _store.upsertAll(changed);
    state = AsyncData<List<SavedEventSnapshot>>(
      List<SavedEventSnapshot>.unmodifiable(next),
    );
  }

  SavedEventsGroups groups({DateTime? now}) => groupSavedEvents(
    state.value ?? const <SavedEventSnapshot>[],
    now: now ?? _now(),
  );
}

final AsyncNotifierProvider<SavedEventsController, List<SavedEventSnapshot>>
savedEventsControllerProvider =
    AsyncNotifierProvider<SavedEventsController, List<SavedEventSnapshot>>(
      SavedEventsController.new,
      retry: (_, _) => null,
    );

final Provider<Set<String>> savedEventRefsProvider = Provider<Set<String>>((
  Ref ref,
) {
  final List<SavedEventSnapshot> saved =
      ref.watch(savedEventsControllerProvider).value ??
      const <SavedEventSnapshot>[];
  return <String>{
    for (final SavedEventSnapshot snapshot in saved) snapshot.eventRef,
  };
});

final Provider<DateTime Function()> savedEventsClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

final Provider<SavedEventsStore> savedEventsStoreProvider =
    Provider<SavedEventsStore>((Ref ref) => HiveSavedEventsStore());
