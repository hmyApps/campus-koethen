// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_modules.dart';
import '../../app/navigation_config.dart';
import '../locale/locale_mode.dart';
import '../theme/appearance_preferences.dart';
import 'key_value_store.dart';
import 'preference_keys.dart';

/// All locally persisted user settings that are plain scalars.
class AppSettings {
  const AppSettings({
    this.localeMode = LocaleMode.german,
    this.brightnessPreference = BrightnessPreference.system,
    this.accentScheme = AccentScheme.pink,
    this.reducedMotion = false,
    this.navigation = NavigationConfig.defaults,
    this.preferredCanteenSlug,
    this.timetableGroupId,
    this.defaultBuildingKey,
    this.onboardingCompleted = false,
    this.mailDownloadAttachments = false,
    this.mailExchangeCalendarEnabled = false,
  });

  final LocaleMode localeMode;
  final BrightnessPreference brightnessPreference;
  final AccentScheme accentScheme;

  /// Material consumes [ThemeMode], while storage and UI use the explicit
  /// product vocabulary above. In particular, `system` stays `system`.
  ThemeMode get themeMode => brightnessPreference.themeMode;

  /// The **local** reduced-motion wish. The operating system's own setting is
  /// honoured separately, so this being false does not mean "animate".
  final bool reducedMotion;

  final NavigationConfig navigation;

  /// Slug of the canteen the user prefers, or `null` for "not chosen yet".
  final String? preferredCanteenSlug;

  /// **Campus** UUID of the chosen timetable group, or `null` for "not chosen
  /// yet". The app never stores an upstream identifier.
  final String? timetableGroupId;

  /// buildingKey the campus map opens on, or `null` for "not chosen yet".
  final String? defaultBuildingKey;

  /// Whether the first-run onboarding has been completed **or skipped**.
  /// Skipping counts: the user answered the question by declining it.
  final bool onboardingCompleted;

  /// When true, the mail sync downloads attachment bytes too, so attachments
  /// are available offline. Off by default to keep the cache small.
  final bool mailDownloadAttachments;

  /// Whether personal Exchange appointments may be read and merged locally.
  /// This remains false until the reader explicitly opts in.
  final bool mailExchangeCalendarEnabled;

  AppSettings copyWith({
    LocaleMode? localeMode,
    BrightnessPreference? brightnessPreference,
    AccentScheme? accentScheme,
    bool? reducedMotion,
    NavigationConfig? navigation,
    String? preferredCanteenSlug,
    bool clearPreferredCanteen = false,
    String? timetableGroupId,
    bool clearTimetableGroup = false,
    String? defaultBuildingKey,
    bool clearDefaultBuilding = false,
    bool? onboardingCompleted,
    bool? mailDownloadAttachments,
    bool? mailExchangeCalendarEnabled,
  }) {
    return AppSettings(
      localeMode: localeMode ?? this.localeMode,
      brightnessPreference: brightnessPreference ?? this.brightnessPreference,
      accentScheme: accentScheme ?? this.accentScheme,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      navigation: navigation ?? this.navigation,
      defaultBuildingKey: clearDefaultBuilding
          ? null
          : (defaultBuildingKey ?? this.defaultBuildingKey),
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      preferredCanteenSlug: clearPreferredCanteen
          ? null
          : (preferredCanteenSlug ?? this.preferredCanteenSlug),
      timetableGroupId: clearTimetableGroup
          ? null
          : (timetableGroupId ?? this.timetableGroupId),
      mailDownloadAttachments:
          mailDownloadAttachments ?? this.mailDownloadAttachments,
      mailExchangeCalendarEnabled:
          mailExchangeCalendarEnabled ?? this.mailExchangeCalendarEnabled,
    );
  }
}

/// The key/value store used for scalar settings.
///
/// Overridden in `main()` with the real `shared_preferences` backed store and
/// in tests with [InMemoryKeyValueStore].
final Provider<KeyValueStore> keyValueStoreProvider = Provider<KeyValueStore>(
  (Ref ref) => InMemoryKeyValueStore(),
);

/// Reads and writes [AppSettings].
class SettingsController extends Notifier<AppSettings> {
  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  AppSettings build() {
    ref.watch(keyValueStoreProvider);
    return _read();
  }

  /// Reads the whole settings block out of the store.
  ///
  /// Shared with [resetLocalPreferences], which has to publish what is
  /// actually persisted rather than assume the defaults took hold.
  AppSettings _read() {
    final KeyValueStore store = _store;
    return AppSettings(
      localeMode: LocaleMode.fromStorage(
        store.getString(PreferenceKeys.localeMode),
      ),
      brightnessPreference: BrightnessPreference.fromStorage(
        store.getString(PreferenceKeys.brightnessPreference) ??
            store.getString(PreferenceKeys.legacyThemeMode),
      ),
      accentScheme: AccentScheme.fromStorage(
        store.getString(PreferenceKeys.accentScheme),
      ),
      reducedMotion: store.getInt(PreferenceKeys.reducedMotion) == 1,
      navigation: NavigationConfig.fromStorage(
        store.getStringList(PreferenceKeys.navigationTabs),
      ),
      preferredCanteenSlug: store.getString(PreferenceKeys.preferredCanteen),
      timetableGroupId: store.getString(PreferenceKeys.preferredTimetableGroup),
      defaultBuildingKey: store.getString(PreferenceKeys.defaultBuilding),
      onboardingCompleted:
          store.getInt(PreferenceKeys.onboardingCompleted) == 1,
      mailDownloadAttachments:
          store.getInt(PreferenceKeys.mailDownloadAttachments) == 1,
      mailExchangeCalendarEnabled:
          store.getInt(PreferenceKeys.mailExchangeCalendarEnabled) == 1,
    );
  }

  Future<void> setLocaleMode(LocaleMode mode) async {
    state = state.copyWith(localeMode: mode);
    await _store.setString(PreferenceKeys.localeMode, mode.storageValue);
  }

  Future<void> setBrightnessPreference(BrightnessPreference preference) async {
    state = state.copyWith(brightnessPreference: preference);
    await _store.setString(
      PreferenceKeys.brightnessPreference,
      preference.storageValue,
    );
    // Once the v2 value exists it wins on every read. Removing the old value
    // avoids leaving two apparently active sources in a preferences export.
    await _store.remove(PreferenceKeys.legacyThemeMode);
  }

  Future<void> setAccentScheme(AccentScheme scheme) async {
    state = state.copyWith(accentScheme: scheme);
    await _store.setString(PreferenceKeys.accentScheme, scheme.storageValue);
  }

  Future<void> setPreferredCanteen(String? slug) async {
    if (slug == null) {
      state = state.copyWith(clearPreferredCanteen: true);
      await _store.remove(PreferenceKeys.preferredCanteen);
      return;
    }
    state = state.copyWith(preferredCanteenSlug: slug);
    await _store.setString(PreferenceKeys.preferredCanteen, slug);
  }

  /// Stores the **Campus** UUID of the chosen timetable group.
  Future<void> setTimetableGroup(String? groupId) async {
    if (groupId == null) {
      state = state.copyWith(clearTimetableGroup: true);
      await _store.remove(PreferenceKeys.preferredTimetableGroup);
      return;
    }
    state = state.copyWith(timetableGroupId: groupId);
    await _store.setString(PreferenceKeys.preferredTimetableGroup, groupId);
  }

  Future<void> setReducedMotion(bool enabled) async {
    state = state.copyWith(reducedMotion: enabled);
    await _store.setInt(PreferenceKeys.reducedMotion, enabled ? 1 : 0);
  }

  /// Stores the four modules of the navigation bar.
  ///
  /// The wish list is normalised first, so an invalid combination cannot be
  /// persisted at all — the repair happens before the write, not on the next
  /// read.
  Future<void> setNavigationTabs(Iterable<AppModule> modules) async {
    final NavigationConfig config = NavigationConfig.of(modules);
    state = state.copyWith(navigation: config);
    await _store.setStringList(
      PreferenceKeys.navigationTabs,
      config.toStorage(),
    );
  }

  Future<void> setDefaultBuilding(String? buildingKey) async {
    if (buildingKey == null) {
      state = state.copyWith(clearDefaultBuilding: true);
      await _store.remove(PreferenceKeys.defaultBuilding);
      return;
    }
    state = state.copyWith(defaultBuildingKey: buildingKey);
    await _store.setString(PreferenceKeys.defaultBuilding, buildingKey);
  }

  /// Marks the onboarding as answered — completed or deliberately skipped.
  Future<void> setOnboardingCompleted(bool completed) async {
    state = state.copyWith(onboardingCompleted: completed);
    await _store.setInt(PreferenceKeys.onboardingCompleted, completed ? 1 : 0);
  }

  /// Clears every setting this controller owns and returns to the defaults.
  ///
  /// Scoped on purpose: it resets **presentation and preferences**, not the
  /// secure stores behind mail, grades and Moodle. Those hold credentials and
  /// are removed through their own "remove account" action, which is the only
  /// place that can also clear their encrypted caches.
  /// Returns true when every key was actually removed.
  ///
  /// `onboardingCompleted` is deliberately NOT in the list. Clearing it did
  /// not reset a preference, it re-armed the router's onboarding redirect —
  /// and because the redirect reads the flag without listening to it, the
  /// throw back into onboarding happened at the NEXT navigation, minutes
  /// later and with no visible connection to the button that caused it
  /// (SET-1). Repeating the introduction has its own entry.
  Future<bool> resetLocalPreferences() async {
    bool complete = true;
    for (final String key in <String>[
      PreferenceKeys.localeMode,
      PreferenceKeys.brightnessPreference,
      PreferenceKeys.legacyThemeMode,
      PreferenceKeys.accentScheme,
      PreferenceKeys.reducedMotion,
      PreferenceKeys.navigationTabs,
      PreferenceKeys.preferredCanteen,
      PreferenceKeys.preferredTimetableGroup,
      PreferenceKeys.defaultBuilding,
      PreferenceKeys.mailDownloadAttachments,
      PreferenceKeys.mailExchangeCalendarEnabled,
      PreferenceKeys.calendarHomeWidgetEnabled,
      PreferenceKeys.calendarHomeWidgetShowDetails,
    ]) {
      // Each key on its own: a throw used to abandon the loop, leaving a half
      // reset behind a snack bar that said it was done — and the untouched
      // values came back at the next start (SET-6).
      try {
        await _store.remove(key);
      } catch (_) {
        complete = false;
      }
    }
    // Rebuilt from the store rather than assumed: after a partial failure the
    // published state has to match what is actually persisted.
    state = _read();
    return complete;
  }

  Future<void> setMailDownloadAttachments(bool enabled) async {
    state = state.copyWith(mailDownloadAttachments: enabled);
    await _store.setInt(
      PreferenceKeys.mailDownloadAttachments,
      enabled ? 1 : 0,
    );
  }

  Future<void> setMailExchangeCalendarEnabled(bool enabled) async {
    state = state.copyWith(mailExchangeCalendarEnabled: enabled);
    await _store.setInt(
      PreferenceKeys.mailExchangeCalendarEnabled,
      enabled ? 1 : 0,
    );
  }
}

final NotifierProvider<SettingsController, AppSettings> settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
