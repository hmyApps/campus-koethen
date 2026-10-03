// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/widgets/icon_keys.dart';
import 'package:campus_koethen/core/widgets/remote_image.dart';
import 'package:campus_koethen/features/contacts/presentation/contacts_list_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/pump_app.dart';

Map<String, dynamic> _room() => <String, dynamic>{
  'roomKey': 'test-building-level2-b201',
  'roomNumber': 'B.201',
  'buildingName': 'Testgebäude',
  'floorName': '2. Obergeschoss',
  'displayName': 'Beratungsraum',
};

/// The areas the list endpoint serves.
List<Map<String, dynamic>> get _areas => <Map<String, dynamic>>[
  <String, dynamic>{
    'slug': 'stura',
    'name': 'Studierendenrat',
    'shortDescription': 'Vertretung der Studierenden',
    'iconKey': 'students-council',
    'sortOrder': 10,
    'personCount': 1,
  },
  <String, dynamic>{
    'slug': 'pruefungsamt',
    'name': 'Prüfungsamt',
    'shortDescription': 'Prüfungen und Noten',
    'iconKey': 'contact',
    'sortOrder': 20,
    'personCount': 0,
  },
];

/// The same content as the search index sees it.
List<Map<String, dynamic>> get _index => <Map<String, dynamic>>[
  <String, dynamic>{
    'slug': 'stura',
    'name': 'Studierendenrat',
    'shortDescription': 'Vertretung der Studierenden',
    'descriptionText': 'Wir beraten bei Härtefallanträgen.',
    'iconKey': 'students-council',
    'phone': '+49 3496 12345',
    'rooms': <Map<String, dynamic>>[_room()],
    'persons': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Demo Person',
        'role': 'Vorsitz',
        'email': 'demo@example.org',
        'rooms': <Map<String, dynamic>>[],
      },
    ],
  },
  <String, dynamic>{
    'slug': 'pruefungsamt',
    'name': 'Prüfungsamt',
    'shortDescription': 'Prüfungen und Noten',
    'descriptionText': '',
    'iconKey': 'contact',
    'rooms': <Map<String, dynamic>>[],
    'persons': <Map<String, dynamic>>[],
  },
];

class ContactsApi {
  ContactsApi({this.includeAreaImage = false});

  final bool includeAreaImage;
  final List<String> requestedPaths = <String>[];

  FakeHttpAdapter get adapter => FakeHttpAdapter((RequestOptions options) {
    requestedPaths.add(options.path);
    if (options.path.contains('search-index')) {
      return FakeHttpResponse(envelope(_index));
    }
    if (options.path.contains('contact-areas')) {
      final List<Map<String, dynamic>> areas = _areas;
      if (includeAreaImage) {
        areas.first['image'] = '/v1/media/contact-area.jpg';
      }
      return FakeHttpResponse(envelope(areas));
    }
    return FakeHttpResponse(envelope(<Object>[]));
  });
}

Future<ContactsApi> pumpContacts(
  WidgetTester tester, {
  Locale locale = AppLocales.german,
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(390, 1200),
  bool includeAreaImage = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final ContactsApi api = ContactsApi(includeAreaImage: includeAreaImage);
  await pumpScreen(
    tester,
    const ContactsListScreen(),
    locale: locale,
    textScaler: textScaler,
    overrides: <Override>[
      apiClientProvider.overrideWithValue(fakeApiClient(api.adapter)),
    ],
  );
  await tester.pumpAndSettle();
  return api;
}

Future<void> _type(WidgetTester tester, String term) async {
  await tester.enterText(find.byType(TextField), term);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('list shows the area icon even when the area has an image', (
    WidgetTester tester,
  ) async {
    await pumpContacts(tester, includeAreaImage: true);

    final Finder areaCard = find.ancestor(
      of: find.text('Studierendenrat'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: areaCard,
        matching: find.byIcon(IconKeys.resolve('students-council')),
      ),
      findsOneWidget,
    );
    expect(find.byType(RemoteImage), findsNothing);
  });

  testWidgets('the list stays the list until something is typed', (
    WidgetTester tester,
  ) async {
    final ContactsApi api = await pumpContacts(tester);

    expect(find.text('Studierendenrat'), findsOneWidget);
    expect(find.text('Prüfungsamt'), findsOneWidget);
    // The index is not fetched before it is needed.
    expect(
      api.requestedPaths.any((String p) => p.contains('search-index')),
      isFalse,
    );

    await tester.tap(find.byTooltip('Kontakte durchsuchen'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.text('Studierendenrat'),
      findsOneWidget,
      reason: 'an empty search field is not a filter',
    );
  });

  group('searching', () {
    testWidgets('finds an area by name', (WidgetTester tester) async {
      await pumpContacts(tester);
      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();

      await _type(tester, 'prüfung');

      expect(find.text('Prüfungsamt'), findsOneWidget);
      expect(find.text('Studierendenrat'), findsNothing);
      expect(find.text('1 Treffer'), findsOneWidget);
    });

    testWidgets('finds a person and names the area they belong to', (
      WidgetTester tester,
    ) async {
      await pumpContacts(tester);
      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();

      await _type(tester, 'demo person');

      expect(find.text('Demo Person'), findsOneWidget);
      expect(find.text('Vorsitz · in Studierendenrat'), findsOneWidget);
    });

    testWidgets('finds an area by its room number', (
      WidgetTester tester,
    ) async {
      await pumpContacts(tester);
      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();

      await _type(tester, 'b201');

      expect(find.text('Studierendenrat'), findsOneWidget);
      // The result says why it is a result.
      expect(find.text('B.201'), findsOneWidget);
    });

    testWidgets('finds an area by a word in its long description', (
      WidgetTester tester,
    ) async {
      await pumpContacts(tester);
      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();

      await _type(tester, 'härtefall');

      expect(find.text('Studierendenrat'), findsOneWidget);
    });

    testWidgets('loads the index once, not once per keystroke', (
      WidgetTester tester,
    ) async {
      // The whole reason the endpoint exists.
      final ContactsApi api = await pumpContacts(tester);
      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();

      await _type(tester, 'p');
      await _type(tester, 'pr');
      await _type(tester, 'prü');
      await _type(tester, 'prüf');

      expect(
        api.requestedPaths
            .where((String p) => p.contains('search-index'))
            .length,
        1,
      );
    });

    testWidgets('says so when nothing matches', (WidgetTester tester) async {
      await pumpContacts(tester);
      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();

      await _type(tester, 'zzzz');

      expect(find.text('Kein Treffer'), findsOneWidget);
    });

    testWidgets('closing the search brings the list back and clears the term', (
      WidgetTester tester,
    ) async {
      await pumpContacts(tester);
      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();
      await _type(tester, 'prüfung');

      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Studierendenrat'), findsOneWidget);

      // Reopening starts empty rather than with a forgotten filter.
      await tester.tap(find.byTooltip('Kontakte durchsuchen'));
      await tester.pumpAndSettle();
      expect(find.text('Studierendenrat'), findsOneWidget);
    });
  });

  testWidgets('renders in English', (WidgetTester tester) async {
    await pumpContacts(tester, locale: AppLocales.english);

    await tester.tap(find.byTooltip('Search contacts'));
    await tester.pumpAndSettle();
    await _type(tester, 'zzzz');

    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('survives a narrow phone with doubled text', (
    WidgetTester tester,
  ) async {
    await pumpContacts(
      tester,
      size: const Size(320, 1600),
      textScaler: const TextScaler.linear(2),
    );

    await tester.tap(find.byTooltip('Kontakte durchsuchen'));
    await tester.pumpAndSettle();
    await _type(tester, 'e');

    expect(tester.takeException(), isNull);
  });
}
