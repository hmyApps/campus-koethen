// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_icons.dart';
import '../../../l10n/l10n.dart';

/// One public entry point of the university library.
///
/// The app only hands the address to the browser. It reads nothing from these
/// catalogues, so they are not a direct service in the sense of AGENTS.md §2.
/// A deeper integration (search, loans) would need its own documented
/// exception and a stable interface from the catalogue operator.
@immutable
class LibraryResource {
  const LibraryResource({
    required this.key,
    required this.url,
    required this.icon,
    required this.title,
    required this.description,
  });

  final String key;
  final String url;
  final IconData icon;
  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) description;
}

/// The curated list, in display order. All addresses are `https`.
final List<LibraryResource> libraryResources = <LibraryResource>[
  LibraryResource(
    key: 'opac',
    url: 'https://opac.lbs-anhalt.gbv.de/DB=1/LNG=DU/',
    icon: AppIcons.library_outlined,
    title: (AppLocalizations l10n) => l10n.libraryOpacTitle,
    description: (AppLocalizations l10n) => l10n.libraryOpacDescription,
  ),
  LibraryResource(
    key: 'discovery',
    url: 'https://discovery.hs-anhalt.de/search',
    icon: AppIcons.search,
    title: (AppLocalizations l10n) => l10n.libraryDiscoveryTitle,
    description: (AppLocalizations l10n) => l10n.libraryDiscoveryDescription,
  ),
  LibraryResource(
    key: 'journals',
    url: 'https://ezb.uni-regensburg.de/index.phtml?bibid=HSB&lang=de',
    icon: AppIcons.article_outlined,
    title: (AppLocalizations l10n) => l10n.libraryJournalsTitle,
    description: (AppLocalizations l10n) => l10n.libraryJournalsDescription,
  ),
  LibraryResource(
    key: 'home',
    url: 'https://www.hs-anhalt.de/hochschulbibliothek',
    icon: AppIcons.info_outline,
    title: (AppLocalizations l10n) => l10n.libraryHomeTitle,
    description: (AppLocalizations l10n) => l10n.libraryHomeDescription,
  ),
];
