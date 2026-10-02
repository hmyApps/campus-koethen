// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart' show ThemeMode;

/// How the app chooses between its light and dark palettes.
enum BrightnessPreference {
  system('system', ThemeMode.system),
  light('light', ThemeMode.light),
  dark('dark', ThemeMode.dark);

  const BrightnessPreference(this.storageValue, this.themeMode);

  final String storageValue;
  final ThemeMode themeMode;

  /// Unknown or absent values default to following the OS, same as a fresh
  /// install — never silently force light mode on a device set to dark.
  static BrightnessPreference fromStorage(String? value) => switch (value) {
    'light' => BrightnessPreference.light,
    'dark' => BrightnessPreference.dark,
    _ => BrightnessPreference.system,
  };
}

/// Independently selectable accent family for both brightness variants.
enum AccentScheme {
  pink('pink'),
  green('green'),
  blue('blue'),
  violet('violet'),
  amber('amber');

  const AccentScheme(this.storageValue);

  final String storageValue;

  /// Pink is the migration fallback because it was the only previous accent.
  static AccentScheme fromStorage(String? value) => switch (value) {
    'green' => AccentScheme.green,
    'blue' => AccentScheme.blue,
    'violet' => AccentScheme.violet,
    'amber' => AccentScheme.amber,
    _ => AccentScheme.pink,
  };
}
