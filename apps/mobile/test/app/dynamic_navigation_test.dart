// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/app_router.dart';
import 'package:campus_koethen/app/takt_navigation_bar.dart';
import 'package:campus_koethen/app/app_routes.dart';
import 'package:campus_koethen/app/app_modules.dart';
import 'package:campus_koethen/core/cache/cache_providers.dart';
import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/network/api_client.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/theme/app_theme.dart';
import 'package:campus_koethen/features/news/presentation/news_list_screen.dart';
import 'package:campus_koethen/features/student_service/presentation/student_service_screen.dart';
import 'package:campus_koethen/features/timetable/presentation/timetable_screen.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_http_adapter.dart';

/// Pumps the real router and shell on a phone-sized surface.
Future<void> pumpApp(
  WidgetTester tester, {
  KeyValueStore? store,
  Locale locale = AppLocales.german,
  String initialLocation = AppRoutes.news,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
      contentCacheProvider.overrideWithValue(
        SafeContentCache(MemoryContentCache()),
      ),
      // No test ever reaches the network: every request answers immediately
      // with an empty envelope, so the tree settles and no timer outlives it.
      apiClientProvider.overrideWithValue(_emptyApi()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: locale,
        supportedLocales: AppLocales.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: createAppRouter(initialLocation: initialLocation),
      ),
    ),
  );
  // Some screens keep a progress indicator running while their service is not
  // configured, so settling is not always possible — a few frames are enough
  // to lay the shell out.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

ApiClient _emptyApi() => fakeApiClient(
  FakeHttpAdapter(
    (RequestOptions options) => FakeHttpResponse(envelope(<Object>[])),
  ),
);

/// Finds text inside the navigation bar only — several section names also
/// appear as headings on the screen behind it.
Finder inBar(String label) => find.descendant(
  of: find.byType(TaktNavigationBar),
  matching: find.text(label),
);

void main() {
  testWidgets('the app opens on News', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.byType(NewsListScreen), findsOneWidget);
  });

  testWidgets('the default bar shows the four modules and More', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    final TaktNavigationBar bar = tester.widget<TaktNavigationBar>(
      find.byType(TaktNavigationBar),
    );
    expect(bar.destinations, hasLength(5));
    expect(inBar('News'), findsOneWidget);
    expect(inBar('Kalender'), findsOneWidget);
    expect(inBar('Mensa'), findsOneWidget);
    // The bar uses the short name; the full one is "Studentische E-Mail".
    expect(inBar('E-Mail'), findsOneWidget);
    expect(inBar('Mehr'), findsOneWidget);
    expect(inBar('Heute'), findsNothing);
  });

  testWidgets('a stored configuration changes all four tabs', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    await store.setStringList(PreferenceKeys.navigationTabs, <String>[
      AppModule.mail.storageValue,
      AppModule.todos.storageValue,
      AppModule.campusMap.storageValue,
      AppModule.grades.storageValue,
    ]);

    await pumpApp(
      tester,
      store: store,
      initialLocation: AppRoutes.mail,
      settle: false,
    );

    expect(inBar('Mehr'), findsOneWidget);
    expect(inBar('Aufgaben'), findsOneWidget);
    expect(inBar('Lageplan'), findsOneWidget);
    expect(inBar('Noten'), findsOneWidget);
    // …and the defaults are gone.
    expect(inBar('Kalender'), findsNothing);
    expect(inBar('Mensa'), findsNothing);
  });

  testWidgets('a pinned timetable opens its own module branch', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    await store.setStringList(PreferenceKeys.navigationTabs, <String>[
      AppModule.timetable.storageValue,
      AppModule.news.storageValue,
      AppModule.canteen.storageValue,
      AppModule.mail.storageValue,
    ]);

    await pumpApp(
      tester,
      store: store,
      initialLocation: AppRoutes.timetable,
      settle: false,
    );

    expect(inBar('Stundenplan'), findsOneWidget);
    expect(find.byType(TimetableScreen), findsOneWidget);
    expect(
      tester
          .widget<TaktNavigationBar>(find.byType(TaktNavigationBar))
          .selectedIndex,
      0,
    );
  });

  testWidgets('a pinned student service opens its own module branch', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    await store.setStringList(PreferenceKeys.navigationTabs, <String>[
      AppModule.studentService.storageValue,
      AppModule.news.storageValue,
      AppModule.canteen.storageValue,
      AppModule.mail.storageValue,
    ]);

    await pumpApp(
      tester,
      store: store,
      initialLocation: AppRoutes.studentService,
      settle: false,
    );

    expect(inBar('HISinOne'), findsOneWidget);
    expect(find.byType(StudentServiceScreen), findsOneWidget);
    expect(
      tester
          .widget<TaktNavigationBar>(find.byType(TaktNavigationBar))
          .selectedIndex,
      0,
    );
  });

  testWidgets('a corrupted configuration still yields a usable bar', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    await store.setStringList(PreferenceKeys.navigationTabs, <String>[
      'removed-module',
      'today',
      AppModule.settings.storageValue,
    ]);

    await pumpApp(tester, store: store);

    final TaktNavigationBar bar = tester.widget<TaktNavigationBar>(
      find.byType(TaktNavigationBar),
    );
    expect(bar.destinations, hasLength(5));
    expect(inBar('Mehr'), findsOneWidget);
    expect(inBar('Einstellungen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a tab switches module', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.byType(NewsListScreen), findsOneWidget);

    await tester.tap(inBar('Mehr'));
    await tester.pumpAndSettle();

    expect(find.byType(NewsListScreen), findsNothing);
    final TaktNavigationBar bar = tester.widget<TaktNavigationBar>(
      find.byType(TaktNavigationBar),
    );
    expect(bar.selectedIndex, 4);
  });

  testWidgets('a module reached outside the bar highlights More', (
    WidgetTester tester,
  ) async {
    // Grades is not in the default bar. Opening it must not leave the bar with
    // nothing selected — More is where it was reached from.
    await pumpApp(tester, initialLocation: AppRoutes.grades, settle: false);

    final TaktNavigationBar bar = tester.widget<TaktNavigationBar>(
      find.byType(TaktNavigationBar),
    );
    expect(bar.selectedIndex, 4);
  });

  testWidgets('the bar is localised', (WidgetTester tester) async {
    await pumpApp(tester, locale: AppLocales.english);
    expect(inBar('More'), findsOneWidget);
    expect(inBar('Email'), findsOneWidget);
    expect(inBar('Mehr'), findsNothing);
  });

  testWidgets('every tab keeps a 48dp touch target', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    final Size bar = tester.getSize(find.byType(TaktNavigationBar));
    expect(bar.height, greaterThanOrEqualTo(48));
  });

  testWidgets('the bar survives a narrow phone and large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        contentCacheProvider.overrideWithValue(
          SafeContentCache(MemoryContentCache()),
        ),
        apiClientProvider.overrideWithValue(_emptyApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: AppLocales.german,
          supportedLocales: AppLocales.supported,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child ?? const SizedBox.shrink(),
          ),
          routerConfig: createAppRouter(initialLocation: AppRoutes.news),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
