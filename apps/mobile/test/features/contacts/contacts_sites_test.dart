// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/site/campus_site.dart';
import 'package:campus_koethen/features/contacts/application/contacts_providers.dart';
import 'package:campus_koethen/features/contacts/data/contact_models.dart';
import 'package:campus_koethen/features/contacts/domain/contact_sites.dart';
import 'package:campus_koethen/features/contacts/presentation/contacts_list_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

ContactArea _area(String slug, CampusSite site, {int order = 0}) => ContactArea(
  slug: slug,
  name: 'Bereich $slug',
  sortOrder: order,
  site: site,
);

final List<ContactArea> _all = <ContactArea>[
  _area('stura', CampusSite.koethen, order: 10),
  _area('ssc', CampusSite.koethen, order: 20),
  _area('dessau-stura', CampusSite.dessau, order: 10),
  _area('bernburg-stura', CampusSite.bernburg, order: 10),
];

List<String> _slugs(Iterable<ContactArea> areas) =>
    areas.map((ContactArea a) => a.slug).toList();

void main() {
  group('the site of a contact area', () {
    test('is read from the API answer', () {
      expect(
        ContactArea.fromJson(<String, Object?>{
          'slug': 'a',
          'site': 'dessau',
        })!.site,
        CampusSite.dessau,
      );
    });

    test('is Köthen when the API says nothing or something unknown', () {
      expect(
        ContactArea.fromJson(<String, Object?>{'slug': 'a'})!.site,
        CampusSite.koethen,
      );
      expect(
        ContactArea.fromJson(<String, Object?>{
          'slug': 'a',
          'site': 'halle',
        })!.site,
        CampusSite.koethen,
      );
    });
  });

  group('grouping by site', () {
    test('the own site comes first, the others in site order', () {
      final List<ContactSiteGroup> groups = groupContactAreasBySite(
        _all,
        CampusSite.dessau,
      );

      expect(groups.map((ContactSiteGroup g) => g.site), <CampusSite>[
        CampusSite.dessau,
        CampusSite.koethen,
        CampusSite.bernburg,
      ]);
      expect(_slugs(groups[1].areas), <String>['stura', 'ssc']);
    });

    test('without a preference the sites keep their product order', () {
      expect(
        groupContactAreasBySite(_all, null).map((ContactSiteGroup g) => g.site),
        <CampusSite>[
          CampusSite.koethen,
          CampusSite.bernburg,
          CampusSite.dessau,
        ],
      );
    });

    test('a site without areas has no group', () {
      final List<ContactSiteGroup> groups = groupContactAreasBySite(
        <ContactArea>[_area('a', CampusSite.koethen)],
        CampusSite.dessau,
      );

      expect(groups, hasLength(1));
    });

    test('nothing is dropped and the order inside a site is kept', () {
      final List<ContactSiteGroup> groups = groupContactAreasBySite(
        _all,
        CampusSite.koethen,
      );

      expect(
        groups.expand((ContactSiteGroup g) => g.areas),
        hasLength(_all.length),
      );
      expect(_slugs(groups.first.areas), <String>['stura', 'ssc']);
    });
  });

  group('the contacts list', () {
    Future<void> pumpList(
      WidgetTester tester,
      List<ContactArea> areas, {
      CampusSite? site,
    }) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      if (site != null) {
        await store.setString(PreferenceKeys.campusSite, site.storageValue);
      }
      await pumpScreen(
        tester,
        const ContactsListScreen(),
        keyValueStore: store,
        overrides: <Override>[
          contactAreasProvider.overrideWith(
            (Ref ref) async =>
                Loaded<List<ContactArea>>(value: areas, meta: ApiMeta.empty),
          ),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('splits the areas by site, the own site first', (
      WidgetTester tester,
    ) async {
      await pumpList(tester, _all, site: CampusSite.dessau);

      final double dessau = tester.getTopLeft(find.text('Dessau').first).dy;
      final double koethen = tester.getTopLeft(find.text('Köthen').first).dy;
      expect(dessau, lessThan(koethen));
      expect(find.text('Bereich dessau-stura'), findsOneWidget);
      expect(find.text('Bereich stura'), findsOneWidget);
    });

    testWidgets('shows no headings while there is one site only', (
      WidgetTester tester,
    ) async {
      await pumpList(tester, <ContactArea>[
        _area('stura', CampusSite.koethen),
        _area('ssc', CampusSite.koethen),
      ]);

      expect(find.text('Köthen'), findsNothing);
      expect(find.text('Bereich stura'), findsOneWidget);
    });
  });
}
