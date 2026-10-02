// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/app_modules.dart';
import 'package:campus_koethen/app/navigation_config.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/theme/appearance_preferences.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(KeyValueStore store) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[keyValueStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('personalisation defaults', () {
    test('a fresh install starts on the product defaults', () {
      final AppSettings settings = _container(
        InMemoryKeyValueStore(),
      ).read(settingsProvider);

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.brightnessPreference, BrightnessPreference.system);
      expect(settings.accentScheme, AccentScheme.pink);
      expect(settings.localeMode, LocaleMode.german);
      expect(settings.reducedMotion, isFalse);
      expect(settings.navigation, NavigationConfig.defaults);
      expect(settings.defaultBuildingKey, isNull);
      expect(
        settings.onboardingCompleted,
        isFalse,
        reason: 'the first launch must be able to tell it is the first',
      );
    });

    test(
      'a corrupted store degrades to defaults instead of throwing',
      () async {
        final InMemoryKeyValueStore store = InMemoryKeyValueStore();
        await store.setString(PreferenceKeys.brightnessPreference, 'neon');
        await store.setString(PreferenceKeys.accentScheme, 'infrared');
        await store.setStringList(PreferenceKeys.navigationTabs, <String>[
          'nope',
        ]);

        final AppSettings settings = _container(store).read(settingsProvider);
        expect(settings.brightnessPreference, BrightnessPreference.system);
        expect(settings.accentScheme, AccentScheme.pink);
        expect(settings.navigation.isValid, isTrue);
      },
    );

    for (final BrightnessPreference preference in BrightnessPreference.values) {
      test(
        'legacy ${preference.storageValue} brightness is preserved',
        () async {
          final InMemoryKeyValueStore store = InMemoryKeyValueStore();
          await store.setString(
            PreferenceKeys.legacyThemeMode,
            preference.storageValue,
          );

          final AppSettings settings = _container(store).read(settingsProvider);

          expect(settings.brightnessPreference, preference);
          expect(settings.themeMode, preference.themeMode);
          expect(settings.accentScheme, AccentScheme.pink);
        },
      );
    }

    for (final AccentScheme accent in AccentScheme.values) {
      test('stored ${accent.storageValue} accent is preserved', () async {
        final InMemoryKeyValueStore store = InMemoryKeyValueStore();
        await store.setString(PreferenceKeys.accentScheme, accent.storageValue);

        expect(_container(store).read(settingsProvider).accentScheme, accent);
      });
    }

    test('the removed system-language preference migrates to German', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await store.setString(PreferenceKeys.localeMode, 'system');

      final AppSettings settings = _container(store).read(settingsProvider);

      expect(settings.localeMode, LocaleMode.german);
      expect(LocaleMode.values, <LocaleMode>[
        LocaleMode.german,
        LocaleMode.english,
      ]);
    });
  });

  group('writing settings', () {
    test('each axis persists and reads back', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = _container(store);
      final SettingsController controller = container.read(
        settingsProvider.notifier,
      );

      await controller.setLocaleMode(LocaleMode.english);
      await controller.setBrightnessPreference(BrightnessPreference.system);
      await controller.setAccentScheme(AccentScheme.green);
      await controller.setReducedMotion(true);
      await controller.setDefaultBuilding('ratke-gebaeude');
      await controller.setOnboardingCompleted(true);
      await controller.setNavigationTabs(<AppModule>[
        AppModule.mail,
        AppModule.todos,
        AppModule.campusMap,
        AppModule.grades,
      ]);

      // The live state is updated…
      final AppSettings live = container.read(settingsProvider);
      expect(live.localeMode, LocaleMode.english);
      expect(live.brightnessPreference, BrightnessPreference.system);
      expect(live.themeMode, ThemeMode.system);
      expect(live.accentScheme, AccentScheme.green);
      expect(live.reducedMotion, isTrue);
      expect(live.defaultBuildingKey, 'ratke-gebaeude');
      expect(live.onboardingCompleted, isTrue);
      expect(live.navigation.tabs, <AppModule>[
        AppModule.mail,
        AppModule.todos,
        AppModule.campusMap,
        AppModule.grades,
      ]);

      // …and so is the store, so a restart keeps the choice.
      final AppSettings reloaded = _container(store).read(settingsProvider);
      expect(reloaded.localeMode, LocaleMode.english);
      expect(reloaded.brightnessPreference, BrightnessPreference.system);
      expect(reloaded.themeMode, ThemeMode.system);
      expect(reloaded.accentScheme, AccentScheme.green);
      expect(
        store.getString(PreferenceKeys.brightnessPreference),
        BrightnessPreference.system.storageValue,
      );
      expect(
        store.getString(PreferenceKeys.accentScheme),
        AccentScheme.green.storageValue,
      );
      expect(reloaded.reducedMotion, isTrue);
      expect(reloaded.defaultBuildingKey, 'ratke-gebaeude');
      expect(reloaded.onboardingCompleted, isTrue);
      expect(reloaded.navigation, live.navigation);
    });

    test(
      'an invalid navigation wish is repaired before it is stored',
      () async {
        final InMemoryKeyValueStore store = InMemoryKeyValueStore();
        final SettingsController controller = _container(
          store,
        ).read(settingsProvider.notifier);

        // A module that may not be pinned, and a duplicate — none of this may
        // reach storage.
        await controller.setNavigationTabs(<AppModule>[
          AppModule.settings,
          AppModule.news,
          AppModule.news,
          AppModule.about,
        ]);

        final List<String>? stored = store.getStringList(
          PreferenceKeys.navigationTabs,
        );
        expect(stored, hasLength(4));
        expect(stored, isNot(contains(AppModule.settings.storageValue)));
        expect(stored, isNot(contains(AppModule.about.storageValue)));
        expect(stored!.toSet().length, 4);
      },
    );

    test('clearing the default building removes the key', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final SettingsController controller = _container(
        store,
      ).read(settingsProvider.notifier);

      await controller.setDefaultBuilding('ratke-gebaeude');
      await controller.setDefaultBuilding(null);

      expect(store.getString(PreferenceKeys.defaultBuilding), isNull);
    });
  });

  group('local reset', () {
    test('returns every preference to its default', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = _container(store);
      final SettingsController controller = container.read(
        settingsProvider.notifier,
      );

      await controller.setBrightnessPreference(BrightnessPreference.dark);
      await controller.setAccentScheme(AccentScheme.violet);
      await controller.setReducedMotion(true);
      await controller.setPreferredCanteen('mensa-koethen');
      await controller.setDefaultBuilding('ratke-gebaeude');
      await controller.setOnboardingCompleted(true);

      await controller.resetLocalPreferences();

      final AppSettings after = container.read(settingsProvider);
      expect(after.themeMode, ThemeMode.system);
      expect(after.brightnessPreference, BrightnessPreference.system);
      expect(after.accentScheme, AccentScheme.pink);
      expect(after.reducedMotion, isFalse);
      expect(after.preferredCanteenSlug, isNull);
      expect(after.defaultBuildingKey, isNull);
      expect(
        after.onboardingCompleted,
        isTrue,
        reason:
            'SET-1: clearing this flag does not reset a preference, it re-arms '
            'the router redirect — and because the redirect reads the flag '
            'without listening to it, the jump back into onboarding happened '
            'at the NEXT navigation, with no visible connection to the button '
            'that caused it. Repeating the introduction has its own entry in '
            'the same settings section, which clears the flag AND navigates '
            'there straight away.',
      );

      // And the store is genuinely empty, not just the in-memory state.
      final AppSettings reloaded = _container(store).read(settingsProvider);
      expect(reloaded.themeMode, ThemeMode.system);
      expect(reloaded.accentScheme, AccentScheme.pink);
      expect(reloaded.onboardingCompleted, isTrue);
    });

    test('reports whether every key was actually removed', () async {
      // SET-6: the loop used to abandon on the first throw while the snack bar
      // still said "done", so the untouched values came back at the next start.
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = _container(store);
      final SettingsController controller = container.read(
        settingsProvider.notifier,
      );
      await controller.setBrightnessPreference(BrightnessPreference.dark);
      await controller.setAccentScheme(AccentScheme.amber);

      expect(await controller.resetLocalPreferences(), isTrue);
      expect(container.read(settingsProvider).themeMode, ThemeMode.system);
      expect(container.read(settingsProvider).accentScheme, AccentScheme.pink);
    });

    test('does not touch keys owned by the secure personal services', () async {
      // The reset is scoped to presentation and preferences. Credentials and
      // encrypted caches belong to "remove account" inside each service — a
      // settings reset must never half-delete a mail account.
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      await store.setString('mail.account.host.v1', 'mail.example.org');
      await store.setInt('grades.lastSync.v1', 1234);

      await _container(
        store,
      ).read(settingsProvider.notifier).resetLocalPreferences();

      expect(store.getString('mail.account.host.v1'), 'mail.example.org');
      expect(store.getInt('grades.lastSync.v1'), 1234);
    });
  });
}
