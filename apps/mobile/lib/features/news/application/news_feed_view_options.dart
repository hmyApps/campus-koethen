// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/key_value_store.dart';
import '../../../core/prefs/preference_keys.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/time/clock.dart';
import '../domain/news_feed_arrangement.dart';

/// The clock the feed's "has this event ended?" rule reads. Overridden in
/// tests for deterministic boundaries — same convention as
/// `eventsClockProvider`.
final Provider<Clock> newsFeedClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// The reader's chosen feed order, persisted as one scalar.
class NewsFeedSortController extends Notifier<NewsFeedSort> {
  late KeyValueStore _store;

  @override
  NewsFeedSort build() {
    _store = ref.watch(keyValueStoreProvider);
    return NewsFeedSort.fromStorage(
      _store.getString(PreferenceKeys.newsFeedSort),
    );
  }

  Future<void> select(NewsFeedSort sort) async {
    if (sort == state) return;
    state = sort;
    await _store.setString(PreferenceKeys.newsFeedSort, sort.storageValue);
  }
}

final NotifierProvider<NewsFeedSortController, NewsFeedSort>
newsFeedSortProvider = NotifierProvider<NewsFeedSortController, NewsFeedSort>(
  NewsFeedSortController.new,
);

/// Keys for [newsShowEndedEventsProvider]: the main feed and each channel
/// screen remember their own "show older events" toggle.
abstract final class NewsFeedScopeKey {
  static const String mainFeed = 'feed';

  static String channel(String slug) => 'channel:$slug';
}

/// Whether ended event posts are currently revealed in one feed.
///
/// Deliberately not persisted: it is a glance into the past for this
/// session, and a feed that silently stayed full of old events after the
/// next launch would defeat the point of hiding them.
class NewsShowEndedEventsController extends Notifier<bool> {
  NewsShowEndedEventsController(this.scope);

  final String scope;

  @override
  bool build() => false;

  void toggle() => state = !state;
}

final newsShowEndedEventsProvider =
    NotifierProvider.family<NewsShowEndedEventsController, bool, String>(
      NewsShowEndedEventsController.new,
    );
