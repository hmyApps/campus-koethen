// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/site/campus_site.dart';
import 'map_catalog.dart';

/// What the map shows first: a campus site and, if that site has plans, a
/// building of it.
typedef VisibleBuilding = ({CampusSite site, String? buildingKey});

/// Decides which site and building the map shows.
///
/// A concrete building — chosen on the map, implied by a floor or by a
/// linked room — always wins, and the site follows from it: a link to a Dessau
/// room must not be shown on a Köthen plan because Köthen was preferred.
/// Without one, the site comes from the reader's choice on the map, then from
/// the preference set in the onboarding or settings, and finally Köthen. A
/// site without any plan resolves to no building at all; the map says so
/// instead of drawing somebody else's campus.
VisibleBuilding resolveVisibleBuilding({
  required MapCatalog? map,
  required String? explicitBuilding,
  required String? explicitFloor,
  required String? roomBuilding,
  required String? defaultBuildingKey,
  required CampusSite? explicitSite,
  required CampusSite? preferredSite,
}) {
  final CampusSite fallbackSite =
      explicitSite ?? preferredSite ?? CampusSite.koethen;
  if (map == null) return (site: fallbackSite, buildingKey: null);

  final String? concrete = map.building(explicitBuilding) != null
      ? explicitBuilding
      : map.buildingOfFloor(explicitFloor) ?? roomBuilding;
  final MapBuilding? chosen = map.building(concrete);
  if (chosen != null) {
    return (site: chosen.site, buildingKey: chosen.buildingKey);
  }

  final List<MapBuilding> ofSite = map.buildingsOf(fallbackSite);
  if (ofSite.isEmpty) return (site: fallbackSite, buildingKey: null);
  // The reader's default building, but only inside the site being shown.
  final MapBuilding? preferred = map.building(defaultBuildingKey);
  final MapBuilding building =
      preferred != null && preferred.site == fallbackSite
      ? preferred
      : ofSite.first;
  return (site: fallbackSite, buildingKey: building.buildingKey);
}
