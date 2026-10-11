// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';

import 'app_modules.dart';

/// Which modules the bottom navigation bar shows.
///
/// The bar is always five entries: **four modules the user picks** and a fixed
/// **More** at the end. More is fixed for a reason — it is the only guarantee
/// that every module stays reachable no matter what the other four contain.
///
/// Everything that reads a stored configuration goes through [fromStorage],
/// which *repairs* rather than rejects: an unknown identifier from a removed
/// module, a duplicate, a wrong length, a module that may not be pinned or a
/// hand-edited preference must never leave a user with a broken bar. Storage is
/// untrusted input.
@immutable
class NavigationConfig {
  const NavigationConfig._(this.tabs);

  /// The four user-chosen modules, in bar order.
  final List<AppModule> tabs;

  /// How many slots the user controls.
  static const int tabCount = 4;

  /// What a fresh install shows.
  static const NavigationConfig defaults = NavigationConfig._(<AppModule>[
    AppModule.news,
    AppModule.calendar,
    AppModule.canteen,
    AppModule.mail,
  ]);

  /// Builds a valid configuration from any wish list.
  ///
  /// Modules that may not be pinned or are temporarily unavailable are dropped, duplicates collapsed, the list
  /// truncated to [tabCount] and any remaining gap filled from the defaults and
  /// then the rest of the catalogue — so the result is always exactly four
  /// distinct, pinnable and currently available modules.
  factory NavigationConfig.of(Iterable<AppModule> wanted) {
    final List<AppModule> chosen = <AppModule>[];
    void take(AppModule module) {
      if (chosen.length >= tabCount) return;
      if (!module.pinnable) return;
      // Greyed out in More; a tab must not become a way around that.
      if (module.isTemporarilyUnavailable) return;
      if (module.isExcludedFromBuild) return;
      if (chosen.contains(module)) return;
      chosen.add(module);
    }

    wanted.forEach(take);
    // Fill from the defaults first so a half-configured bar still looks like
    // the product's intended one, then from the remaining catalogue.
    defaults.tabs.forEach(take);
    AppModule.pinnableModules.forEach(take);
    return NavigationConfig._(List<AppModule>.unmodifiable(chosen));
  }

  /// Reads a stored configuration. `null` — a first launch — yields
  /// [defaults].
  factory NavigationConfig.fromStorage(List<String>? stored) {
    if (stored == null) return defaults;
    return NavigationConfig.of(
      stored
          .map(AppModule.fromStorage)
          .whereType<AppModule>()
          .toList(growable: false),
    );
  }

  List<String> toStorage() =>
      tabs.map((AppModule m) => m.storageValue).toList(growable: false);

  /// Whether this configuration is one the app can actually render.
  ///
  /// Always true for anything [NavigationConfig.of] produced; kept as an
  /// explicit predicate so tests state the invariant rather than assume it.
  bool get isValid =>
      tabs.length == tabCount &&
      tabs.toSet().length == tabCount &&
      tabs.every(
        (AppModule m) =>
            m.pinnable && !m.isTemporarilyUnavailable && !m.isExcludedFromBuild,
      );

  bool contains(AppModule module) => tabs.contains(module);

  /// Index of the tab owning [route], or `-1` when no tab does.
  ///
  /// Prefix matching, because a tab stays selected while the user is deeper in
  /// its stack — `/calendar/manage` still belongs to the calendar tab.
  int indexOfRoute(String route) {
    for (int i = 0; i < tabs.length; i++) {
      final String tabRoute = tabs[i].route;
      if (route == tabRoute || route.startsWith('$tabRoute/')) return i;
    }
    return -1;
  }

  /// The "More" hub for this bar.
  List<MoreCategoryEntry> get moreEntries => moreEntriesFor(tabs);

  @override
  bool operator ==(Object other) =>
      other is NavigationConfig && listEquals(other.tabs, tabs);

  @override
  int get hashCode => Object.hashAll(tabs);

  @override
  String toString() =>
      'NavigationConfig(${tabs.map((AppModule m) => m.storageValue).join(', ')})';
}
