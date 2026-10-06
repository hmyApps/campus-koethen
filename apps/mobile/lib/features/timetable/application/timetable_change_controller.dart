// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../data/encrypted_timetable_change_store.dart';
import '../data/timetable_models.dart';
import 'timetable_change.dart';

final Provider<EncryptedTimetableChangeStore> timetableChangeStoreProvider =
    Provider<EncryptedTimetableChangeStore>(
      (Ref ref) => EncryptedTimetableChangeStore(),
    );

final Provider<Clock> timetableChangeClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

class TimetableChangeController extends AsyncNotifier<List<TimetableChange>> {
  EncryptedTimetableChangeStore get _store =>
      ref.read(timetableChangeStoreProvider);

  @override
  Future<List<TimetableChange>> build() => _store.readPending();

  Future<void> observe({
    required TimetableChangeScope scope,
    required Timetable timetable,
  }) async {
    try {
      await _store.observe(
        scope: scope,
        entries: <TimetableEntry>[
          for (final TimetableDay day in timetable.days) ...day.entries,
        ],
        detectedAt: ref.read(timetableChangeClockProvider).now(),
      );
      state = AsyncData<List<TimetableChange>>(await _store.readPending());
    } catch (_) {
      // Change hints are additive. A failed local hint store must never hide a
      // successfully fetched timetable or turn it into a refresh error.
    }
  }

  Future<void> acknowledgeGroup(String groupId) async {
    await _store.acknowledgeGroup(groupId);
    state = AsyncData<List<TimetableChange>>(await _store.readPending());
  }
}

final AsyncNotifierProvider<TimetableChangeController, List<TimetableChange>>
timetableChangeControllerProvider =
    AsyncNotifierProvider<TimetableChangeController, List<TimetableChange>>(
      TimetableChangeController.new,
      retry: (_, _) => null,
    );
