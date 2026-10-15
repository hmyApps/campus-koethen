// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/content/content_block.dart';
import '../../../core/links/safe_link_launcher.dart';
import '../../../core/network/json.dart';
import '../../../core/site/campus_site.dart';

/// A compact reference to a room of the campus map.
///
/// Carries everything needed to render a readable line and to deep-link into
/// the map. An empty room list is a normal state — most contacts have none.
class RoomReference {
  const RoomReference({
    required this.roomKey,
    required this.roomNumber,
    this.buildingNumber = '',
    required this.buildingName,
    required this.floorName,
    this.displayName,
  });

  final String roomKey;
  final String roomNumber;
  final String buildingNumber;
  final String buildingName;
  final String floorName;
  final String? displayName;

  static RoomReference? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? roomKey = asString(map['roomKey']);
    if (roomKey == null) return null;
    return RoomReference(
      roomKey: roomKey,
      roomNumber: asString(map['roomNumber']) ?? roomKey,
      buildingNumber: asString(map['buildingNumber']) ?? '',
      buildingName: asString(map['buildingName']) ?? '',
      floorName: asString(map['floorName']) ?? '',
      displayName: asString(map['displayName']),
    );
  }

  static List<RoomReference> listFromJson(Object? json) => asList(json)
      .map(RoomReference.fromJson)
      .whereType<RoomReference>()
      .toList(growable: false);
}

/// A contact person inside an area.
///
/// Every field except [name] is optional. Missing fields are **hidden** by the
/// UI, never rendered as an empty row.
class ContactPerson {
  const ContactPerson({
    required this.name,
    this.role,
    this.description,
    this.email,
    this.phone,
    this.website,
    this.profileImageUrl,
    this.rooms = const <RoomReference>[],
  });

  final String name;
  final String? role;
  final String? description;
  final String? email;
  final String? phone;
  final String? website;
  final String? profileImageUrl;
  final List<RoomReference> rooms;

  static ContactPerson? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? name = asString(map['name']);
    if (name == null) return null;
    final String? website = asString(map['website']);
    return ContactPerson(
      name: name,
      role: asString(map['role']),
      description: asString(map['description']),
      email: asString(map['email']),
      phone: asString(map['phone']),
      website: SafeLinkLauncher.isAllowed(website) ? website : null,
      // A plain media path from the API, not a nested object and not an
      // outbound link: SafeLinkLauncher guards things the user opens
      // elsewhere, and running a relative path past it dropped every photo.
      profileImageUrl: asString(map['profileImage']),
      rooms: RoomReference.listFromJson(map['rooms']),
    );
  }
}

/// A contact area. An area **without** any person is valid and must stay fully
/// usable — that is an explicit product requirement, not an edge case.
class ContactArea {
  const ContactArea({
    required this.slug,
    required this.name,
    required this.sortOrder,
    this.site = CampusSite.koethen,
    this.shortDescription,
    this.iconKey,
    this.imageUrl,
    this.generalEmail,
    this.phone,
    this.website,
    this.appointmentBookingUrl,
    this.address,
    this.openingHours,
    this.personCount = 0,
    this.description = const <ContentBlock>[],
    this.persons = const <ContactPerson>[],
    this.rooms = const <RoomReference>[],
  });

  final String slug;
  final String name;
  final String? shortDescription;
  final String? iconKey;

  /// The campus site the area belongs to. An API that says nothing, or names
  /// a site this app does not know, means Köthen, where every area began.
  final CampusSite site;

  /// Media path published by the Campus API, or `null` when the area has no
  /// picture. The icon carries the area perfectly well on its own, so this is
  /// an enhancement and never a requirement.
  final String? imageUrl;

  final int sortOrder;

  final String? generalEmail;
  final String? phone;
  final String? website;
  final String? appointmentBookingUrl;
  final String? address;
  final String? openingHours;

  /// Only meaningful on the list endpoint.
  final int personCount;

  final List<ContentBlock> description;
  final List<ContactPerson> persons;

  /// Rooms of the campus map. Empty is normal and renders nothing at all.
  final List<RoomReference> rooms;

  /// Whether any general contact channel is maintained at all.
  bool get hasContactDetails =>
      generalEmail != null ||
      phone != null ||
      website != null ||
      appointmentBookingUrl != null ||
      address != null ||
      openingHours != null;

  static ContactArea? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? slug = asString(map['slug']);
    if (slug == null) return null;
    final String? website = asString(map['website']);
    final String? appointmentBookingUrl = asString(
      map['appointmentBookingUrl'],
    );
    final List<ContactPerson> persons = asList(map['persons'])
        .map(ContactPerson.fromJson)
        .whereType<ContactPerson>()
        .toList(growable: false);
    return ContactArea(
      slug: slug,
      name: asString(map['name']) ?? slug,
      shortDescription: asString(map['shortDescription']),
      iconKey: asString(map['iconKey']),
      site: CampusSite.fromStorage(asString(map['site'])) ?? CampusSite.koethen,
      imageUrl: asString(map['image']),
      sortOrder: asInt(map['sortOrder']) ?? 0,
      generalEmail: asString(map['generalEmail']),
      phone: asString(map['phone']),
      website: SafeLinkLauncher.isAllowed(website) ? website : null,
      appointmentBookingUrl: SafeLinkLauncher.isAllowed(appointmentBookingUrl)
          ? appointmentBookingUrl
          : null,
      address: asString(map['address']),
      openingHours: asString(map['openingHours']),
      personCount: asInt(map['personCount']) ?? persons.length,
      description: ContentBlock.parse(map['description']),
      persons: persons,
      rooms: RoomReference.listFromJson(map['rooms']),
    );
  }

  static List<ContactArea> listFromJson(Object? json) =>
      asList(json).map(ContactArea.fromJson).whereType<ContactArea>().toList()
        ..sort((ContactArea a, ContactArea b) {
          final int order = a.sortOrder.compareTo(b.sortOrder);
          return order != 0 ? order : a.name.compareTo(b.name);
        });
}
