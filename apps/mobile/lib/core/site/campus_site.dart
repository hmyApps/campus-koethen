// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../l10n/l10n.dart';

/// The campus sites of Hochschule Anhalt this app covers.
///
/// A site decides what is shown first: which canteens, which building plans
/// and which contacts. It never hides the others — somebody who studies in
/// Köthen may well eat in Dessau.
enum CampusSite {
  koethen('koethen'),
  bernburg('bernburg'),
  dessau('dessau');

  const CampusSite(this.storageValue);

  /// Stable key: written to local storage, carried by the map catalogue and
  /// the Campus API. Never the enum index.
  final String storageValue;

  /// The site for a stored or transmitted key, or `null` for anything else
  /// (a value written by a newer app, a damaged preference).
  static CampusSite? fromStorage(String? value) {
    for (final CampusSite site in values) {
      if (site.storageValue == value) return site;
    }
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
    CampusSite.koethen => l10n.campusSiteKoethen,
    CampusSite.bernburg => l10n.campusSiteBernburg,
    CampusSite.dessau => l10n.campusSiteDessau,
  };
}
