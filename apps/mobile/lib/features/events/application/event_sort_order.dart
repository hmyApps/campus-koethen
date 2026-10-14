// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/key_value_store.dart';
import '../../../core/prefs/preference_keys.dart';
import '../../../core/prefs/settings_controller.dart';
import '../domain/event_sort.dart';

/// The event overview's persisted sort order ("Sortierung" in the source
/// filter sheet) — one small scalar in the key-value store.
class EventSortOrderController extends Notifier<EventSortOrder> {
  late KeyValueStore _store;

  @override
  EventSortOrder build() {
    _store = ref.watch(keyValueStoreProvider);
    return EventSortOrder.fromStorage(
      _store.getString(PreferenceKeys.eventSortOrder),
    );
  }

  Future<void> setOrder(EventSortOrder order) async {
    if (order == state) return;
    state = order;
    await _store.setString(PreferenceKeys.eventSortOrder, order.storageValue);
  }
}

final NotifierProvider<EventSortOrderController, EventSortOrder>
eventSortOrderProvider =
    NotifierProvider<EventSortOrderController, EventSortOrder>(
      EventSortOrderController.new,
    );
