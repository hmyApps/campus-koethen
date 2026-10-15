// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/site/campus_site.dart';
import '../data/canteen_models.dart';

/// The canteens with those of [preferred] first.
///
/// A reorder, never a filter: somebody who studies in Köthen may well eat in
/// Dessau. The API order is kept inside each group, and canteens whose site
/// is unknown (an older API) follow the known ones.
List<Canteen> orderCanteensForSite(
  List<Canteen> canteens,
  CampusSite? preferred,
) {
  if (preferred == null) return canteens;
  int rank(Canteen canteen) {
    if (canteen.site == preferred) return 0;
    return canteen.site == null ? 2 : 1;
  }

  final List<Canteen> ordered = List<Canteen>.of(canteens);
  // `List.sort` is not stable; the index keeps the API order inside a group.
  final Map<Canteen, int> index = <Canteen, int>{
    for (int i = 0; i < canteens.length; i++) canteens[i]: i,
  };
  ordered.sort((Canteen a, Canteen b) {
    final int byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : index[a]!.compareTo(index[b]!);
  });
  return ordered;
}
