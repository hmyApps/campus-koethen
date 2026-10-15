// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/site/campus_site.dart';
import '../data/contact_models.dart';

/// The contact areas of one campus site.
class ContactSiteGroup {
  const ContactSiteGroup(this.site, this.areas);

  final CampusSite site;
  final List<ContactArea> areas;
}

/// Splits [areas] by site: the reader's own site first, then the others in
/// product order. A site without an area has no group. Inside a group the
/// order the API chose is kept.
List<ContactSiteGroup> groupContactAreasBySite(
  List<ContactArea> areas,
  CampusSite? preferred,
) {
  final List<CampusSite> order = <CampusSite>[
    ?preferred,
    for (final CampusSite site in CampusSite.values)
      if (site != preferred) site,
  ];
  return <ContactSiteGroup>[
    for (final CampusSite site in order)
      if (areas.any((ContactArea a) => a.site == site))
        ContactSiteGroup(
          site,
          areas
              .where((ContactArea a) => a.site == site)
              .toList(growable: false),
        ),
  ];
}
