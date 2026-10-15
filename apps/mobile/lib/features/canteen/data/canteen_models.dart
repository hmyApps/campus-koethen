// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/network/json.dart';
import '../../../core/site/campus_site.dart';
import '../domain/meal_taxonomy.dart';

/// A canteen as delivered by `GET /v1/canteens`.
///
/// The client never knows any upstream location identifier — adding a canteen
/// is a backend configuration change, not an app release.
class Canteen {
  const Canteen({
    required this.slug,
    required this.displayName,
    this.campusLabel,
    this.site,
    this.lastSuccessfulSyncAt,
    this.dataStale = false,
  });

  final String slug;
  final String displayName;
  final String? campusLabel;

  /// The campus site the canteen belongs to, or `null` for an API that does
  /// not say (or names a site this app does not know).
  final CampusSite? site;

  /// `null` means: never successfully synchronised.
  final DateTime? lastSuccessfulSyncAt;

  final bool dataStale;

  static Canteen? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? slug = asString(map['slug']);
    if (slug == null) return null;
    return Canteen(
      slug: slug,
      displayName: asString(map['displayName']) ?? slug,
      campusLabel: asString(map['campusLabel']),
      site: CampusSite.fromStorage(asString(map['site'])),
      lastSuccessfulSyncAt: asDateTime(map['lastSuccessfulSyncAt']),
      dataStale: asBool(map['dataStale']) ?? false,
    );
  }

  static List<Canteen> listFromJson(Object? json) => asList(
    json,
  ).map(Canteen.fromJson).whereType<Canteen>().toList(growable: false);
}

/// Ingredient or marker label. Both namespaces arrive in one list and are told
/// apart by [kind], because the upstream source mixes them.
class MealMarker {
  const MealMarker({required this.code, required this.label, this.kind});

  final String code;
  final String label;

  /// `ingredient` or `marker`. Unknown values are kept verbatim and grouped
  /// under the neutral marker heading.
  final String? kind;

  bool get isIngredient => kind == 'ingredient';

  static MealMarker? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? label = asString(map['label']);
    if (label == null) return null;
    return MealMarker(
      code: asString(map['code']) ?? '',
      label: label,
      kind: asString(map['kind']),
    );
  }
}

/// One price group of a meal.
///
/// [amount] stays a decimal **string** all the way to the formatter, so no
/// binary floating point rounding can happen anywhere in the app.
class MealPrice {
  const MealPrice({
    required this.group,
    required this.label,
    required this.amount,
    required this.currency,
  });

  /// Stable technical key, e.g. `student`, `employee`, `guest`.
  final String group;

  /// Translated display label supplied by the API.
  final String label;

  /// Decimal representation, e.g. `"1.95"`.
  final String amount;

  /// ISO 4217 code, e.g. `EUR`.
  final String currency;

  /// The price group the UI emphasises.
  static const String studentGroup = 'student';

  bool get isStudentGroup => group == studentGroup;

  static MealPrice? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? group = asString(map['group']);
    final String? amount = asString(map['amount']);
    if (group == null || amount == null) return null;
    return MealPrice(
      group: group,
      label: asString(map['label']) ?? group,
      amount: amount,
      currency: asString(map['currency']) ?? 'EUR',
    );
  }
}

/// A single meal. There is deliberately **no image field** anywhere.
class Meal {
  const Meal({
    required this.id,
    required this.name,
    this.subtitle,
    this.sourceLanguage,
    this.counterId,
    this.isSprint = false,
    this.extras = const <String>[],
    this.markers = const <MealMarker>[],
    this.traits = const <MealTrait>{},
    this.allergens = const <MealAllergen>{},
    this.prices = const <MealPrice>[],
  });

  final String id;
  final String name;
  final String? subtitle;

  /// `de` when name, subtitle, extras and marker labels come untranslated from
  /// the German-language source.
  final String? sourceLanguage;

  final int? counterId;
  final bool isSprint;
  final List<String> extras;
  final List<MealMarker> markers;

  /// Stable semantic properties from the API. The filter uses these — never a
  /// marker code and never a German label.
  final Set<MealTrait> traits;

  /// Declared allergens as stable keys. A subtype always arrives together with
  /// its parent, so excluding "gluten" covers a dish declared as wheat.
  final Set<MealAllergen> allergens;

  final List<MealPrice> prices;

  List<MealMarker> get nonIngredientMarkers =>
      markers.where((MealMarker marker) => !marker.isIngredient).toList();

  /// The price for [group], or `null` when the source did not deliver one.
  ///
  /// A missing price is stated as missing; another group's price would be a
  /// different number for a different person.
  MealPrice? priceFor(String group) {
    for (final MealPrice price in prices) {
      if (price.group == group) return price;
    }
    return null;
  }

  static Meal? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? name = asString(map['name']);
    if (name == null) return null;
    return Meal(
      id: asString(map['id']) ?? name,
      name: name,
      subtitle: asString(map['subtitle']),
      sourceLanguage: asString(map['sourceLanguage']),
      counterId: asInt(map['counterId']),
      isSprint: asBool(map['isSprint']) ?? false,
      extras: _parseExtras(map['extras']),
      markers: asList(map['markers'])
          .map(MealMarker.fromJson)
          .whereType<MealMarker>()
          .toList(growable: false),
      // A key this build does not know is dropped rather than guessed at: the
      // API may publish a new one before the app is updated.
      traits: asList(map['traits'])
          .map(asString)
          .whereType<String>()
          .map(MealTrait.fromKey)
          .whereType<MealTrait>()
          .toSet(),
      allergens: asList(map['allergens'])
          .map(asString)
          .whereType<String>()
          .map(MealAllergen.fromKey)
          .whereType<MealAllergen>()
          .toSet(),
      prices: asList(
        map['prices'],
      ).map(MealPrice.fromJson).whereType<MealPrice>().toList(growable: false),
    );
  }

  /// `extras` may be plain strings or objects with a name/label — both shapes
  /// are accepted so a harmless upstream change cannot empty the screen.
  static List<String> _parseExtras(Object? json) {
    return asList(json)
        .map((Object? entry) {
          if (entry is String) return asString(entry);
          final Map<String, dynamic>? map = asJsonMap(entry);
          if (map == null) return null;
          return asString(map['name']) ?? asString(map['label']);
        })
        .whereType<String>()
        .toList(growable: false);
  }
}

/// One calendar day of a menu. An empty [meals] list is a real, empty day —
/// it is not a loading failure.
class MenuDay {
  const MenuDay({required this.date, required this.meals});

  final DateTime date;
  final List<Meal> meals;

  static MenuDay? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final DateTime? date = asCalendarDate(map['date']);
    if (date == null) return null;
    return MenuDay(
      date: date,
      meals: asList(
        map['meals'],
      ).map(Meal.fromJson).whereType<Meal>().toList(growable: false),
    );
  }
}

/// The menu of one canteen over a date range.
class CanteenMenu {
  const CanteenMenu({
    required this.canteenSlug,
    required this.displayName,
    required this.days,
    this.campusLabel,
  });

  final String canteenSlug;
  final String displayName;
  final String? campusLabel;
  final List<MenuDay> days;

  /// The first day from [from] onwards that actually has meals.
  ///
  /// A canteen is closed at weekends and in the holidays, so "today" is often
  /// an empty page. Pointing at the next day with an offer is the answer the
  /// user wanted; showing an empty list and letting them tap forward is not.
  MenuDay? nextOpenDayFrom(DateTime from) {
    final DateTime start = DateTime(from.year, from.month, from.day);
    MenuDay? best;
    for (final MenuDay day in days) {
      if (day.meals.isEmpty) continue;
      if (day.date.isBefore(start)) continue;
      if (best == null || day.date.isBefore(best.date)) best = day;
    }
    return best;
  }

  /// Whether [date] lies inside the window the source actually delivered.
  ///
  /// The stepper is unbounded but the menu covers roughly two weeks, so past
  /// its edge every day looks like a closing day. "The canteen is closed" and
  /// "we have no data that far out" are different answers, and only one of
  /// them is true out there.
  bool covers(DateTime date) {
    if (days.isEmpty) return false;
    final DateTime day = DateTime(date.year, date.month, date.day);
    DateTime first = days.first.date;
    DateTime last = days.first.date;
    for (final MenuDay entry in days) {
      if (entry.date.isBefore(first)) first = entry.date;
      if (entry.date.isAfter(last)) last = entry.date;
    }
    return !day.isBefore(first) && !day.isAfter(last);
  }

  MenuDay? dayFor(DateTime date) {
    for (final MenuDay day in days) {
      if (day.date.year == date.year &&
          day.date.month == date.month &&
          day.date.day == date.day) {
        return day;
      }
    }
    return null;
  }

  static CanteenMenu? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final Map<String, dynamic>? canteen = asJsonMap(map['canteen']);
    final String? slug = asString(canteen?['slug']);
    if (slug == null) return null;
    final List<MenuDay> days =
        asList(map['days']).map(MenuDay.fromJson).whereType<MenuDay>().toList()
          ..sort((MenuDay a, MenuDay b) => a.date.compareTo(b.date));
    return CanteenMenu(
      canteenSlug: slug,
      displayName: asString(canteen?['displayName']) ?? slug,
      campusLabel: asString(canteen?['campusLabel']),
      days: days,
    );
  }
}
