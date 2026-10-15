// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/site/campus_site.dart';
import 'package:flutter/widgets.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the three sites in their product order', () {
    expect(CampusSite.values, <CampusSite>[
      CampusSite.koethen,
      CampusSite.bernburg,
      CampusSite.dessau,
    ]);
    expect(CampusSite.values.map((CampusSite s) => s.storageValue), <String>[
      'koethen',
      'bernburg',
      'dessau',
    ]);
  });

  test('storage is read tolerantly: anything unknown is "not chosen"', () {
    expect(CampusSite.fromStorage('dessau'), CampusSite.dessau);
    for (final String? bad in <String?>[
      null,
      '',
      'Dessau',
      'halle',
      ' koethen',
    ]) {
      expect(CampusSite.fromStorage(bad), isNull, reason: '$bad');
    }
  });

  test('the names are the cities in both languages', () {
    final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    expect(CampusSite.values.map((CampusSite s) => s.label(de)), <String>[
      'Köthen',
      'Bernburg',
      'Dessau',
    ]);
    expect(CampusSite.dessau.label(en), 'Dessau');
  });

  group('the preferred site setting', () {
    ProviderContainer containerFor(KeyValueStore store) {
      final ProviderContainer container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is not chosen on a fresh install', () {
      expect(
        containerFor(InMemoryKeyValueStore()).read(settingsProvider).campusSite,
        isNull,
      );
    });

    test('is stored and read back', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await containerFor(
        store,
      ).read(settingsProvider.notifier).setCampusSite(CampusSite.bernburg);

      expect(store.getString(PreferenceKeys.campusSite), 'bernburg');
      expect(
        containerFor(store).read(settingsProvider).campusSite,
        CampusSite.bernburg,
      );
    });

    test('a damaged stored value reads as not chosen', () {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore()
        ..setString(PreferenceKeys.campusSite, 'atlantis');

      expect(containerFor(store).read(settingsProvider).campusSite, isNull);
    });

    test('can be cleared again', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = containerFor(store);
      final SettingsController controller = container.read(
        settingsProvider.notifier,
      );
      await controller.setCampusSite(CampusSite.dessau);

      await controller.setCampusSite(null);

      expect(container.read(settingsProvider).campusSite, isNull);
      expect(store.getString(PreferenceKeys.campusSite), isNull);
    });
  });
}
