// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/news/application/news_feed_view_options.dart';
import 'package:campus_koethen/features/news/domain/news_feed_arrangement.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

ProviderContainer containerWith(KeyValueStore store) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[keyValueStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('newsFeedSortProvider', () {
    test('defaults to newest first', () {
      final ProviderContainer c = containerWith(InMemoryKeyValueStore());
      expect(c.read(newsFeedSortProvider), NewsFeedSort.newest);
    });

    test('persists the choice as a small scalar', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer c = containerWith(store);
      await c
          .read(newsFeedSortProvider.notifier)
          .select(NewsFeedSort.chronological);
      expect(c.read(newsFeedSortProvider), NewsFeedSort.chronological);
      expect(store.getString(PreferenceKeys.newsFeedSort), 'chronological');

      final ProviderContainer reopened = containerWith(store);
      expect(reopened.read(newsFeedSortProvider), NewsFeedSort.chronological);
    });

    test('an unknown stored value falls back to newest', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await store.setString(PreferenceKeys.newsFeedSort, 'bogus');
      expect(
        containerWith(store).read(newsFeedSortProvider),
        NewsFeedSort.newest,
      );
    });
  });

  group('newsShowEndedEventsProvider', () {
    test('is off by default, toggles, and is scoped per feed', () {
      final ProviderContainer c = containerWith(InMemoryKeyValueStore());
      const String main = NewsFeedScopeKey.mainFeed;
      final String channel = NewsFeedScopeKey.channel('fachschaft');
      expect(c.read(newsShowEndedEventsProvider(main)), isFalse);

      c.read(newsShowEndedEventsProvider(main).notifier).toggle();
      expect(c.read(newsShowEndedEventsProvider(main)), isTrue);
      expect(c.read(newsShowEndedEventsProvider(channel)), isFalse);

      c.read(newsShowEndedEventsProvider(main).notifier).toggle();
      expect(c.read(newsShowEndedEventsProvider(main)), isFalse);
    });

    test('is never persisted', () {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer c = containerWith(store);
      c
          .read(newsShowEndedEventsProvider(NewsFeedScopeKey.mainFeed).notifier)
          .toggle();
      expect(
        containerWith(
          store,
        ).read(newsShowEndedEventsProvider(NewsFeedScopeKey.mainFeed)),
        isFalse,
      );
    });
  });
}
