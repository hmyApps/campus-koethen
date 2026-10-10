// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:campus_koethen/features/moodle/application/moodle_providers.dart';
import 'package:campus_koethen/features/moodle/data/moodle_file_downloader.dart';
import 'package:campus_koethen/features/moodle/data/secure_moodle_token_store.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_cache.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_content.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_course.dart';
import 'package:campus_koethen/features/moodle/presentation/moodle_course_screen.dart';
import 'package:campus_koethen/features/moodle/presentation/moodle_screen.dart';
import 'package:campus_koethen/features/moodle/presentation/moodle_setup_screen.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:campus_koethen/core/theme/app_colors.dart';
import 'package:campus_koethen/core/theme/app_icons.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_moodle.dart';
import '../../support/pump_app.dart';

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;
  int writes = 0;

  @override
  Future<UniversityIdentity?> read() async => value;

  @override
  Future<void> write(UniversityIdentity identity) async {
    writes++;
    value = identity;
  }

  @override
  Future<void> clear() async => value = null;
}

/// A keychain that can be made to fail every read, like a locked keystore.
class _FlakySecureStorage extends FlutterSecureStorage {
  _FlakySecureStorage(this.values);

  final Map<String, String> values;
  Object? readError;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final Object? error = readError;
    if (error != null) throw error;
    return values[key];
  }
}

List<Override> _overrides({
  required FakeMoodleApiClient api,
  required InMemoryMoodleTokenStore tokens,
  required InMemoryMoodleCacheStore cache,
  required MutableClock clock,
}) => <Override>[
  moodleApiClientProvider.overrideWithValue(api),
  moodleTokenStoreProvider.overrideWithValue(tokens),
  moodleCacheStoreProvider.overrideWithValue(cache),
  moodleClockProvider.overrideWithValue(clock),
];

void main() {
  final DateTime t0 = DateTime.utc(2026, 7, 26, 12);

  group('course tabs', _courseTabTests);

  group('file download', _fileDownloadTests);

  group('university identity reuse', () {
    testWidgets(
      'ticking "also use for other services" retains the identity centrally',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final identityStore = _MemoryIdentityStore();
        await pumpScreen(
          tester,
          const MoodleSetupScreen(),
          overrides: _overrides(
            api: FakeMoodleApiClient(),
            tokens: InMemoryMoodleTokenStore(),
            cache: InMemoryMoodleCacheStore(),
            clock: MutableClock(t0),
          ),
          universityIdentityStore: identityStore,
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).at(0), 'student42');
        await tester.enterText(find.byType(TextFormField).at(1), 'pw');
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verbinden'));
        await tester.pumpAndSettle();

        expect(identityStore.writes, 1);
        expect(identityStore.value?.identifier, 'student42');
        expect(identityStore.value?.password, 'pw');
      },
    );

    testWidgets('hides the reuse offer once a central identity is stored', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpScreen(
        tester,
        const MoodleSetupScreen(),
        overrides: _overrides(
          api: FakeMoodleApiClient(),
          tokens: InMemoryMoodleTokenStore(),
          cache: InMemoryMoodleCacheStore(),
          clock: MutableClock(t0),
        ),
        universityIdentityStore: _MemoryIdentityStore()
          ..value = const UniversityIdentity(
            identifier: 'stud',
            password: 'pw',
          ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Diese Zugangsdaten auch für Mail, Moodle und Noten automatisch verwenden.',
        ),
        findsNothing,
      );
    });
  });

  testWidgets('shows the connect screen when disconnected', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const MoodleScreen(),
      overrides: _overrides(
        api: FakeMoodleApiClient(),
        tokens: InMemoryMoodleTokenStore(),
        cache: InMemoryMoodleCacheStore(),
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    // The connect gate is shown, not the overview.
    expect(find.text('Mit Moodle verbinden'), findsOneWidget);
    expect(find.text('Meine Kurse'), findsNothing);
  });

  testWidgets('announces and locks the Moodle connection state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final FakeMoodleApiClient api = FakeMoodleApiClient()
      ..pendingToken = Completer<String>()
      ..tokenRequested = Completer<void>();
    await pumpScreen(
      tester,
      const MoodleSetupScreen(),
      overrides: _overrides(
        api: api,
        tokens: InMemoryMoodleTokenStore(),
        cache: InMemoryMoodleCacheStore(),
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'student42');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.tap(find.text('Verbinden'));
    await api.tokenRequested!.future;
    await tester.pump();

    expect(find.text('Verbindung wird hergestellt …'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Verbindung wird hergestellt …'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Passwort anzeigen'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widgetList<PopScope>(find.byType(PopScope))
          .any((PopScope scope) => !scope.canPop),
      isTrue,
    );

    api.pendingToken!.complete('tok-fake');
    await tester.pumpAndSettle();
  });

  testWidgets('setup lock and shield follow the light and dark brand colour', (
    WidgetTester tester,
  ) async {
    for (final (ThemeMode mode, Color expected) in <(ThemeMode, Color)>[
      (ThemeMode.light, AppColors.light.primary),
      (ThemeMode.dark, AppColors.dark.primary),
    ]) {
      await pumpScreen(
        tester,
        const MoodleScreen(),
        themeMode: mode,
        overrides: _overrides(
          api: FakeMoodleApiClient(),
          tokens: InMemoryMoodleTokenStore(),
          cache: InMemoryMoodleCacheStore(),
          clock: MutableClock(t0),
        ),
      );
      await tester.pumpAndSettle();

      for (final IconData iconData in <IconData>[
        AppIcons.lock_outline,
        AppIcons.shield_outlined,
      ]) {
        final Icon icon = tester.widget<Icon>(find.byIcon(iconData));
        expect(icon.color, expected);
      }
    }
  });

  testWidgets(
    'an unreadable keychain shows a retryable error, not the setup form',
    (WidgetTester tester) async {
      final _FlakySecureStorage storage = _FlakySecureStorage(<String, String>{
        'moodle.token': 'tok',
        'moodle.userid': '7',
      })..readError = StateError('keystore locked');
      final cache = InMemoryMoodleCacheStore()
        ..courses = <MoodleCourse>[
          const MoodleCourse(id: 1, fullName: 'Beispielkurs Informatik'),
        ]
        ..marks = MoodleSyncMarks(lastAttempt: t0);

      await pumpScreen(
        tester,
        const MoodleScreen(),
        overrides: <Override>[
          moodleApiClientProvider.overrideWithValue(FakeMoodleApiClient()),
          moodleTokenStoreProvider.overrideWithValue(
            SecureMoodleTokenStore(storage),
          ),
          moodleCacheStoreProvider.overrideWithValue(cache),
          moodleClockProvider.overrideWithValue(MutableClock(t0)),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Moodle konnte nicht geöffnet werden'), findsOneWidget);
      expect(find.text('Mit Moodle verbinden'), findsNothing);
      expect(cache.clears, 0);

      // Once the keychain answers again, retry restores the connection.
      storage.readError = null;
      await tester.tap(find.text('Aktualisieren'));
      await tester.pumpAndSettle();

      expect(find.text('Beispielkurs Informatik'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows cached courses when connected', (
    WidgetTester tester,
  ) async {
    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');
    final cache = InMemoryMoodleCacheStore()
      ..courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Beispielkurs Informatik'),
      ]
      // A recent attempt suppresses the automatic sync in this test.
      ..marks = MoodleSyncMarks(lastAttempt: t0);

    await pumpScreen(
      tester,
      const MoodleScreen(),
      overrides: _overrides(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Beispielkurs Informatik'), findsOneWidget);
    final Icon courseIcon = tester.widget<Icon>(
      find.byIcon(AppIcons.book_outlined),
    );
    expect(courseIcon.color, AppColors.light.primary);
  });

  testWidgets('a failed disconnect stays connected and explains retry', (
    WidgetTester tester,
  ) async {
    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');
    final cache = InMemoryMoodleCacheStore()
      ..courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Rechnernetze'),
      ]
      ..marks = MoodleSyncMarks(lastAttempt: t0)
      ..clearError = StateError('cache remains');

    await pumpScreen(
      tester,
      const MoodleScreen(),
      overrides: _overrides(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moodle-Verbindung und lokale Daten löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Moodle-Verbindung und lokale Daten konnten nicht vollständig '
        'gelöscht werden. Bitte versuche es erneut.',
      ),
      findsOneWidget,
    );
    expect(find.text('Rechnernetze'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('course tiles omit Moodle completion progress', (
    WidgetTester tester,
  ) async {
    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');
    final cache = InMemoryMoodleCacheStore()
      ..courses = <MoodleCourse>[
        const MoodleCourse(
          id: 1,
          fullName: 'Beispielkurs Informatik',
          shortName: 'INF',
          progress: 73,
        ),
      ]
      ..marks = MoodleSyncMarks(lastAttempt: t0);

    await pumpScreen(
      tester,
      const MoodleScreen(),
      overrides: _overrides(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('INF'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('course book icon follows the dark brand colour', (
    WidgetTester tester,
  ) async {
    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');
    final cache = InMemoryMoodleCacheStore()
      ..courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Beispielkurs Informatik'),
      ]
      ..marks = MoodleSyncMarks(lastAttempt: t0);

    await pumpScreen(
      tester,
      const MoodleScreen(),
      themeMode: ThemeMode.dark,
      overrides: _overrides(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    final Icon courseIcon = tester.widget<Icon>(
      find.byIcon(AppIcons.book_outlined),
    );
    expect(courseIcon.color, AppColors.dark.primary);
  });

  testWidgets('the local search filters the loaded courses', (
    WidgetTester tester,
  ) async {
    // Purely local: the fake API records every call, and none may happen while
    // typing. Moodle data never leaves the device.
    final api = FakeMoodleApiClient();
    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');
    final cache = InMemoryMoodleCacheStore()
      ..courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Einführung in die Programmierung'),
        const MoodleCourse(id: 2, fullName: 'Rechnernetze', shortName: 'RN'),
      ]
      ..marks = MoodleSyncMarks(lastAttempt: t0);

    await pumpScreen(
      tester,
      const MoodleScreen(),
      overrides: _overrides(
        api: api,
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kurse durchsuchen'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'einfuehrung');
    await tester.pumpAndSettle();

    expect(find.text('Einführung in die Programmierung'), findsOneWidget);
    expect(find.text('Rechnernetze'), findsNothing);
  });

  testWidgets('a search without matches says so instead of showing nothing', (
    WidgetTester tester,
  ) async {
    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');
    final cache = InMemoryMoodleCacheStore()
      ..courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Rechnernetze'),
      ]
      ..marks = MoodleSyncMarks(lastAttempt: t0);

    await pumpScreen(
      tester,
      const MoodleScreen(),
      overrides: _overrides(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kurse durchsuchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'quantenphysik');
    await tester.pumpAndSettle();

    expect(find.text('Kein passender Kurs'), findsOneWidget);
  });

  testWidgets('closing the search restores the whole list', (
    WidgetTester tester,
  ) async {
    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');
    final cache = InMemoryMoodleCacheStore()
      ..courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Rechnernetze'),
      ]
      ..marks = MoodleSyncMarks(lastAttempt: t0);

    await pumpScreen(
      tester,
      const MoodleScreen(),
      overrides: _overrides(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: cache,
        clock: MutableClock(t0),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kurse durchsuchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'quantenphysik');
    await tester.pumpAndSettle();
    expect(find.text('Rechnernetze'), findsNothing);

    // Closing clears the term, so a forgotten filter cannot hide everything.
    // The toggle renames itself while the search is open — one button doing
    // two opposite things must not claim to do only one of them.
    await tester.tap(find.byTooltip('Suche schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Rechnernetze'), findsOneWidget);
  });
}

/// The three tab titles must stay readable where they are hardest to fit.
void _courseTabTests() {
  final DateTime t0 = DateTime.utc(2026, 7, 26, 12);

  Future<void> pumpCourse(
    WidgetTester tester, {
    required Size surface,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');

    await pumpScreen(
      tester,
      const MoodleCourseScreen(courseId: 1),
      textScaler: textScaler,
      overrides: _overrides(
        api: FakeMoodleApiClient(),
        tokens: tokens,
        cache: InMemoryMoodleCacheStore(),
        clock: MutableClock(t0),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('all three titles are written out on a narrow phone', (
    WidgetTester tester,
  ) async {
    await pumpCourse(tester, surface: const Size(320, 640));

    expect(find.text('Inhalte'), findsOneWidget);
    expect(find.text('Aufgaben'), findsOneWidget);
    // The long one: three equal thirds of 320 px cannot hold it.
    expect(find.text('Ankündigungen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('and survive doubled text', (WidgetTester tester) async {
    await pumpCourse(
      tester,
      surface: const Size(320, 900),
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('Ankündigungen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('course screen layout matrix has no clipped primary action', (
    WidgetTester tester,
  ) async {
    for (final (Size size, TextScaler scaler) in <(Size, TextScaler)>[
      (const Size(320, 640), TextScaler.noScaling),
      (const Size(360, 800), const TextScaler.linear(1.3)),
      (const Size(800, 360), TextScaler.noScaling),
      (const Size(320, 900), const TextScaler.linear(2)),
    ]) {
      await pumpCourse(tester, surface: size, textScaler: scaler);

      expect(find.byTooltip('Aktualisieren'), findsOneWidget);
      expect(find.text('Inhalte'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size at $scaler');
    }
  });

  testWidgets('the bar scrolls rather than shrinking the labels', (
    WidgetTester tester,
  ) async {
    await pumpCourse(tester, surface: const Size(320, 640));
    final TabBar bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.isScrollable, isTrue);
  });
}

/// Downloads run through the real downloader on a scripted connection.
void _fileDownloadTests() {
  final DateTime t0 = DateTime.utc(2026, 7, 26, 12);
  const String fileUrl =
      'https://moodle.hs-anhalt.de/webservice/pluginfile.php/1/mod_resource/content/1/uebung1.pdf';

  testWidgets('cancelling a hung download unlocks the tile without an error', (
    WidgetTester tester,
  ) async {
    // One chunk, then the connection goes silent.
    final StreamController<Uint8List> body = StreamController<Uint8List>();
    // Not awaited: `done` only completes once a listener sees it.
    addTearDown(() => unawaited(body.close()));
    final _StallingAdapter adapter = _StallingAdapter(body);
    final tokens = InMemoryMoodleTokenStore()
      ..token = const MoodleToken(value: 'tok', userId: 7, username: 'demo');
    final cache = InMemoryMoodleCacheStore()
      ..courses = <MoodleCourse>[
        const MoodleCourse(id: 1, fullName: 'Beispielkurs Informatik'),
      ];
    cache.sections[1] = const <MoodleSection>[
      MoodleSection(
        name: 'Allgemeines',
        modules: <MoodleModule>[
          MoodleModule(
            id: 5001,
            name: 'Übungsblatt 1',
            type: MoodleModuleType.resource,
            files: <MoodleFile>[
              MoodleFile(
                fileName: 'uebung1.pdf',
                fileUrl: fileUrl,
                mimeType: 'application/pdf',
                fileSize: 64,
              ),
            ],
          ),
        ],
      ),
    ];

    await pumpScreen(
      tester,
      const MoodleCourseScreen(courseId: 1),
      overrides: <Override>[
        ..._overrides(
          api: FakeMoodleApiClient(),
          tokens: tokens,
          cache: cache,
          clock: MutableClock(t0),
        ),
        moodleFileDownloaderProvider.overrideWithValue(
          MoodleFileDownloaderImpl(dio: Dio()..httpClientAdapter = adapter),
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('uebung1.pdf'));
    body.add(Uint8List.fromList(List<int>.filled(16, 65)));
    // Let the request reach the connection and the first chunk arrive.
    for (
      int i = 0;
      i < 20 && find.text('Wird geladen: 25 %').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(adapter.requests, 1);
    expect(find.text('Wird geladen: 25 %'), findsOneWidget);
    expect(find.byTooltip('Download abbrechen'), findsOneWidget);

    await tester.tap(find.byTooltip('Download abbrechen'));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // A deliberate stop is not a failure, and the tile is usable again.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Die Datei konnte nicht geladen werden.'), findsNothing);
    expect(find.byTooltip('Download abbrechen'), findsNothing);
    expect(find.byIcon(AppIcons.download_outlined), findsOneWidget);
    expect(adapter.requests, 1);
    expect(tester.takeException(), isNull);
  });
}

/// Answers with headers and whatever [body] emits — and nothing more.
class _StallingAdapter implements HttpClientAdapter {
  _StallingAdapter(this.body);

  final StreamController<Uint8List> body;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody(
      body.stream,
      200,
      headers: <String, List<String>>{
        Headers.contentLengthHeader: <String>['64'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
