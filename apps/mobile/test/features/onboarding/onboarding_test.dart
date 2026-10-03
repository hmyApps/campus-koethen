// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/app/app_router.dart';
import 'package:campus_koethen/core/cache/cache_providers.dart';
import 'package:campus_koethen/core/cache/content_cache.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/api_client.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/theme/app_theme.dart';
import 'package:campus_koethen/features/campusmap/application/campus_map_providers.dart';
import 'package:campus_koethen/features/campusmap/domain/map_catalog.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_settings_controller.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/onboarding/presentation/onboarding_screen.dart';
import 'package:campus_koethen/features/news/presentation/news_list_screen.dart';
import 'package:campus_koethen/features/settings/application/sign_out_everywhere_controller.dart';
import 'package:campus_koethen/features/settings/domain/direct_service.dart';
import 'package:campus_koethen/features/university_account/application/university_account_controller.dart';
import 'package:campus_koethen/features/university_account/application/university_service_connector.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/fake_notification_gateway.dart';

ApiClient _emptyApi() => fakeApiClient(
  FakeHttpAdapter((RequestOptions _) => FakeHttpResponse(envelope(<Object>[]))),
);

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;

  @override
  Future<UniversityIdentity?> read() async => value;

  @override
  Future<void> write(UniversityIdentity identity) async => value = identity;

  @override
  Future<void> clear() async => value = null;
}

class _RecordingServiceAdapter implements UniversityServiceAdapter {
  _RecordingServiceAdapter({this.connectGate, this.connectStarted});

  final Completer<void>? connectGate;
  final Completer<void>? connectStarted;
  UniversityIdentity? connectedWith;
  String? connectedWithDisplayName;

  @override
  Future<void> connect(
    UniversityIdentity identity, {
    String? displayName,
  }) async {
    connectedWith = identity;
    connectedWithDisplayName = displayName;
    if (connectStarted != null && !connectStarted!.isCompleted) {
      connectStarted!.complete();
    }
    await connectGate?.future;
  }

  @override
  Future<void> disconnect() async {}
}

/// Pumps the real app — router, redirect and all — on a phone-sized surface.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  KeyValueStore? store,
  Locale locale = AppLocales.german,
  FakeNotificationGateway? notificationGateway,
  UniversityIdentityStore? identityStore,
  Map<DirectService, UniversityServiceAdapter> serviceAdapters =
      const <DirectService, UniversityServiceAdapter>{},
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final KeyValueStore effectiveStore = store ?? InMemoryKeyValueStore();
  if (locale == AppLocales.english) {
    await effectiveStore.setString(
      PreferenceKeys.localeMode,
      LocaleMode.english.storageValue,
    );
  }

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      keyValueStoreProvider.overrideWithValue(effectiveStore),
      contentCacheProvider.overrideWithValue(
        SafeContentCache(MemoryContentCache()),
      ),
      apiClientProvider.overrideWithValue(_emptyApi()),
      // The bundled map catalogue is read from the asset bundle, which never
      // resolves under `flutter test`. The building step used to render "not
      // available" for a load that was still pending (ONB-1) — now that it
      // shows a spinner instead, an unresolved future would keep
      // `pumpAndSettle` spinning forever. Resolving it here to an empty
      // catalogue reproduces the same visible outcome for the right reason.
      mapCatalogProvider.overrideWith(
        (Ref ref) async => MapCatalog(
          schemaVersion: 1,
          mapVersion: 'test',
          buildings: const <MapBuilding>[],
          floors: const <MapFloor>[],
          rooms: const <MapRoomGeometry>[],
        ),
      ),
      notificationGatewayProvider.overrideWithValue(
        notificationGateway ?? FakeNotificationGateway(),
      ),
      universityIdentityStoreProvider.overrideWithValue(
        identityStore ?? _MemoryIdentityStore(),
      ),
      connectedDirectServicesProvider.overrideWithValue(
        const <DirectService>[],
      ),
      for (final MapEntry<DirectService, UniversityServiceAdapter> entry
          in serviceAdapters.entries)
        universityServiceAdapterProvider(
          entry.key,
        ).overrideWithValue(entry.value),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          final LocaleMode localeMode = ref.watch(
            settingsProvider.select(
              (AppSettings settings) => settings.localeMode,
            ),
          );
          return MaterialApp.router(
            theme: AppTheme.light(),
            locale: localeMode.locale,
            supportedLocales: AppLocales.supported,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: container.read(appRouterProvider),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a first launch lands in the setup, not on the dashboard', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(NewsListScreen), findsNothing);
    expect(find.text('Sprache auswählen'), findsOneWidget);
    expect(find.text('Schritt 1 von 8'), findsOneWidget);
  });

  testWidgets(
    'the first choice changes and persists the language immediately',
    (WidgetTester tester) async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();
      final ProviderContainer container = await pumpApp(tester, store: store);

      expect(find.text('Sprache auswählen'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(find.text('Choose your language'), findsOneWidget);
      expect(find.text('Step 1 of 8'), findsOneWidget);
      expect(find.text('Skip all'), findsOneWidget);
      expect(container.read(settingsProvider).localeMode, LocaleMode.english);
      expect(
        store.getString(PreferenceKeys.localeMode),
        LocaleMode.english.storageValue,
      );

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);
    },
  );

  testWidgets('the welcome step carries the independence notice', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    // A project rule, not a footnote: the app must never look official.
    expect(
      find.textContaining(
        'Campus Köthen ist keine offizielle App der Hochschule Anhalt.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Die App wird von Erik Engler über die App Stores bereitgestellt.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a completed setup goes straight to the dashboard', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    await store.setInt(PreferenceKeys.onboardingCompleted, 1);

    await pumpApp(tester, store: store);

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(NewsListScreen), findsOneWidget);
  });

  testWidgets('skipping everything finishes the setup', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    final FakeNotificationGateway gateway = FakeNotificationGateway(
      permission: NotificationPermissionStatus.notDetermined,
    );
    final ProviderContainer container = await pumpApp(
      tester,
      store: store,
      notificationGateway: gateway,
    );

    await tester.tap(find.text('Alles überspringen'));
    await tester.pumpAndSettle();

    // Skipping counts as answering — the app must not ask again unprompted.
    expect(container.read(settingsProvider).onboardingCompleted, isTrue);
    expect(store.getInt(PreferenceKeys.onboardingCompleted), 1);
    expect(gateway.requestCount, 0);
    expect(find.byType(NewsListScreen), findsOneWidget);
  });

  testWidgets('individual steps can be skipped forward and back', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Schritt 1 von 8'), findsOneWidget);

    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 2 von 8'), findsOneWidget);
    expect(find.text('Willkommen'), findsOneWidget);

    await tester.tap(find.text('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 1 von 8'), findsOneWidget);
  });

  testWidgets('asks only for what the app actually needs', (
    WidgetTester tester,
  ) async {
    // Accent colour and the navigation bar are preferences, not decisions the
    // app needs before it is usable. They live in the settings.
    await pumpApp(tester);

    for (int i = 0; i < 2; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Aussehen'), findsNothing);
    expect(find.text('Navigation'), findsNothing);
  });

  testWidgets('a choice made during setup is kept', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    final ProviderContainer container = await pumpApp(tester, store: store);

    // Step 3 is the campus step. What is asserted here is that a choice made
    // during setup is persisted — the controller is the thing under test, not
    // whether a bundled asset happened to load within this frame budget.
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Dein Campus'), findsOneWidget);

    await container
        .read(settingsProvider.notifier)
        .setPreferredCanteen('koethen-fasanerieallee');
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).preferredCanteenSlug,
      'koethen-fasanerieallee',
    );
    expect(
      store.getString(PreferenceKeys.preferredCanteen),
      'koethen-fasanerieallee',
    );
  });

  testWidgets('choosing content does not throw the user back to step one', (
    WidgetTester tester,
  ) async {
    // The global redirect sends every route back to the setup while it is
    // unfinished. A step that navigated away was therefore bounced straight
    // back — and rebuilt from the start, losing the reader's place.
    await pumpApp(tester);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(
      find.text('Schritt 4 von 8'),
      findsOneWidget,
      reason: 'the content step',
    );
    // The pickers are here, in the step — not behind a route that the
    // redirect would bounce straight back to step one.
    expect(find.text('News-Kanäle wählen'), findsOneWidget);
    expect(find.text('Schritt 1 von 8'), findsNothing);
  });

  testWidgets('an unavailable source is stated instead of blocking', (
    WidgetTester tester,
  ) async {
    // The fake API answers every request with an empty list, so there are no
    // canteens to choose. The step must say so and stay passable.
    await pumpApp(tester);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(find.text('Dein Campus'), findsOneWidget);
    expect(find.text('Es sind noch keine Mensen hinterlegt.'), findsOneWidget);
    // …and moving on still works.
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 4 von 8'), findsOneWidget);
  });

  testWidgets('calendar sources are configured in their own fifth step', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    for (int i = 0; i < 4; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Schritt 5 von 8'), findsOneWidget);
    expect(find.text('Dein Kalender'), findsOneWidget);
    expect(find.text('Stundenplan'), findsOneWidget);
    expect(find.text('Lieblingsspeisen im Kalender'), findsOneWidget);
    expect(find.text('Öffentliche Kalender wählen'), findsOneWidget);
  });

  testWidgets(
    'credentials stay transient until selected services validate them',
    (WidgetTester tester) async {
      final _MemoryIdentityStore identityStore = _MemoryIdentityStore();
      final _RecordingServiceAdapter mail = _RecordingServiceAdapter();
      final _RecordingServiceAdapter grades = _RecordingServiceAdapter();
      await pumpApp(
        tester,
        identityStore: identityStore,
        serviceAdapters: <DirectService, UniversityServiceAdapter>{
          DirectService.mail: mail,
          DirectService.grades: grades,
        },
      );

      for (int i = 0; i < 5; i++) {
        await tester.tap(find.text('Weiter'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Schritt 6 von 8'), findsOneWidget);
      expect(find.text('Hochschulzugang'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('onboarding-university-identifier')),
        'student42',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('onboarding-university-password')),
        'secret-password',
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(identityStore.value, isNull, reason: 'not validated yet');

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Schritt 7 von 8'), findsOneWidget);
      expect(find.text('Dienste verknüpfen'), findsOneWidget);

      await tester.tap(find.text('Studentische E-Mail'));
      await tester.tap(find.text('Noten (HISinOne / HIS-QIS)'));
      await tester.pump();
      await tester.tap(find.text('Ausgewählte Dienste verbinden'));
      await tester.pumpAndSettle();

      const UniversityIdentity expected = UniversityIdentity(
        identifier: 'student42',
        password: 'secret-password',
      );
      expect(mail.connectedWith, expected);
      expect(grades.connectedWith, expected);
      expect(identityStore.value, expected);
    },
  );

  testWidgets('selecting mail offers a display name field and forwards it', (
    WidgetTester tester,
  ) async {
    final _MemoryIdentityStore identityStore = _MemoryIdentityStore();
    final _RecordingServiceAdapter mail = _RecordingServiceAdapter();
    final _RecordingServiceAdapter moodle = _RecordingServiceAdapter();
    await pumpApp(
      tester,
      identityStore: identityStore,
      serviceAdapters: <DirectService, UniversityServiceAdapter>{
        DirectService.mail: mail,
        DirectService.moodle: moodle,
      },
    );

    for (int i = 0; i < 5; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const ValueKey<String>('onboarding-university-identifier')),
      'student42',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('onboarding-university-password')),
      'secret-password',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Dienste verknüpfen'), findsOneWidget);

    // The name field is mail-specific and only appears once mail is
    // selected — ticking Moodle alone must not reveal it.
    expect(find.text('Anzeigename (optional)'), findsNothing);
    await tester.tap(find.text('Moodle'));
    await tester.pump();
    expect(find.text('Anzeigename (optional)'), findsNothing);

    await tester.tap(find.text('Studentische E-Mail'));
    await tester.pump();
    expect(find.text('Anzeigename (optional)'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Anzeigename (optional)'),
      'Max Mustermensch',
    );
    await tester.pump();
    await tester.tap(find.text('Ausgewählte Dienste verbinden'));
    await tester.pumpAndSettle();

    expect(mail.connectedWithDisplayName, 'Max Mustermensch');
    expect(moodle.connectedWithDisplayName, isNull);
  });

  testWidgets(
    'an embedded connection locks every onboarding exit until it finishes',
    (WidgetTester tester) async {
      final Completer<void> connectGate = Completer<void>();
      final Completer<void> connectStarted = Completer<void>();
      final _RecordingServiceAdapter mail = _RecordingServiceAdapter(
        connectGate: connectGate,
        connectStarted: connectStarted,
      );
      await pumpApp(
        tester,
        serviceAdapters: <DirectService, UniversityServiceAdapter>{
          DirectService.mail: mail,
        },
      );

      for (int i = 0; i < 5; i++) {
        await tester.tap(find.text('Weiter'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byKey(const ValueKey<String>('onboarding-university-identifier')),
        'student42',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('onboarding-university-password')),
        'secret-password',
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Studentische E-Mail'));
      await tester.pump();

      await tester.tap(find.text('Ausgewählte Dienste verbinden'));
      await connectStarted.future;
      await tester.pump();

      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Alles überspringen'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Zurück'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Überspringen'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Weiter'))
            .onPressed,
        isNull,
      );
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(
        find.bySemanticsLabel('Ausgewählte Dienste werden verbunden'),
        findsOneWidget,
      );

      connectGate.complete();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Zurück'))
            .onPressed,
        isNotNull,
      );
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
    },
  );

  test('reuse consent explicitly covers secure storage and later use', () {
    final String de = lookupAppLocalizations(
      AppLocales.german,
    ).universityAccountReuseConsent;
    final String en = lookupAppLocalizations(
      AppLocales.english,
    ).universityAccountReuseConsent;

    expect(de, contains('sicheren Gerätespeicher'));
    expect(de, contains('später'));
    expect(de, contains('dienstbezogen'));
    expect(en, contains('secure device storage'));
    expect(en, contains('later'));
    expect(en, contains('per service'));
  });

  testWidgets('the notification step is eighth and enabled by default', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    for (int i = 0; i < 7; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Schritt 8 von 8'), findsOneWidget);
    expect(find.text('Benachrichtigungen'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('finishing requests system permission and enables delivery', (
    WidgetTester tester,
  ) async {
    final FakeNotificationGateway gateway = FakeNotificationGateway(
      permission: NotificationPermissionStatus.notDetermined,
      requestResult: NotificationPermissionStatus.granted,
    );
    final ProviderContainer container = await pumpApp(
      tester,
      notificationGateway: gateway,
    );

    for (int i = 0; i < 7; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Schritt 8 von 8'), findsOneWidget);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(gateway.requestCount, 1);
    expect(find.text('Lokale Benachrichtigungen aktivieren?'), findsNothing);
    expect(container.read(notificationSettingsProvider).optedIn, isTrue);
    expect(container.read(settingsProvider).onboardingCompleted, isTrue);
    expect(find.byType(NewsListScreen), findsOneWidget);
  });

  testWidgets('switching notifications off skips the system permission', (
    WidgetTester tester,
  ) async {
    final FakeNotificationGateway gateway = FakeNotificationGateway(
      permission: NotificationPermissionStatus.notDetermined,
    );
    final ProviderContainer container = await pumpApp(
      tester,
      notificationGateway: gateway,
    );

    for (int i = 0; i < 7; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(gateway.requestCount, 0);
    expect(container.read(notificationSettingsProvider).optedIn, isFalse);
    expect(container.read(settingsProvider).onboardingCompleted, isTrue);
    expect(find.byType(NewsListScreen), findsOneWidget);
  });

  testWidgets('renders in English', (WidgetTester tester) async {
    await pumpApp(tester, locale: AppLocales.english);
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('Skip all'), findsOneWidget);
    expect(find.text('Step 1 of 8'), findsOneWidget);
  });

  testWidgets('survives a small phone with doubled text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 2000);
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
        mapCatalogProvider.overrideWith(
          (Ref ref) async => MapCatalog(
            schemaVersion: 1,
            mapVersion: 'test',
            buildings: const <MapBuilding>[],
            floors: const <MapFloor>[],
            rooms: const <MapRoomGeometry>[],
          ),
        ),
        notificationGatewayProvider.overrideWithValue(
          FakeNotificationGateway(),
        ),
        universityIdentityStoreProvider.overrideWithValue(
          _MemoryIdentityStore(),
        ),
        connectedDirectServicesProvider.overrideWithValue(
          const <DirectService>[],
        ),
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
          routerConfig: container.read(appRouterProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (int i = 0; i < 7; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Schritt 8 von 8'), findsOneWidget);
    expect(find.text('Benachrichtigungen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
