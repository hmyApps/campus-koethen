// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:campus_koethen/core/documents/document_viewer_screen.dart';
import 'package:campus_koethen/core/links/safe_link_launcher.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_inbox_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/data/mail_attachment_picker.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/data/mail_local_data_coordinator.dart';
import 'package:campus_koethen/features/mail/domain/mail_cache_store.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_folder.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/features/mail/presentation/compose_draft.dart';
import 'package:campus_koethen/features/mail/presentation/mail_compose_screen.dart';
import 'package:campus_koethen/features/mail/presentation/mail_message_screen.dart';
import 'package:campus_koethen/features/mail/presentation/mail_screen.dart';
import 'package:campus_koethen/features/mail/presentation/mail_search_screen.dart';
import 'package:campus_koethen/features/mail/presentation/mail_setup_screen.dart';
import 'package:campus_koethen/features/more/presentation/more_screen.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:campus_koethen/core/widgets/screen_scaffold.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/fake_mail.dart';
import '../../support/pump_app.dart';

const MailCredentials _creds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

List<Override> _mail(
  FakeMailGateway gateway,
  InMemoryMailCredentialStore store, {
  MailCacheStore? cache,
}) {
  final MailCacheStore resolvedCache = cache ?? MemoryMailCache();
  return <Override>[
    mailGatewayProvider.overrideWithValue(gateway),
    mailCredentialStoreProvider.overrideWithValue(store),
    mailCacheStoreProvider.overrideWithValue(resolvedCache),
    mailLocalDataCoordinatorProvider.overrideWithValue(
      MailLocalDataCoordinator(
        credentials: store,
        cache: resolvedCache,
        wipeIntent: MemoryMailWipeIntentStore(),
      ),
    ),
  ];
}

/// The sign-in form is a tall, scrolling [ListView]. A tall surface keeps every
/// field and button laid out and hittable, so tests need no manual scrolling.
void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A valid 1×1 transparent PNG, so Image.memory decodes without error.
const List<int> _pngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

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

class _FakeLauncher implements SafeLinkLauncher {
  final List<String> opened = <String>[];

  @override
  Future<LinkLaunchResult> open(String? rawUrl) async {
    if (rawUrl != null) opened.add(rawUrl);
    return LinkLaunchResult.opened;
  }
}

MailMessageHeader _header({String id = '1'}) => MailMessageHeader(
  id: id,
  subject: 'Hallo Welt',
  from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
  date: DateTime.utc(2026, 7, 20, 9, 30),
  isSeen: false,
  hasAttachments: false,
);

void main() {
  group('MoreScreen', () {
    testWidgets('does not repeat mail, which is a default tab', (
      WidgetTester tester,
    ) async {
      // Mail moved into the bottom bar, so the hub must not list it a second
      // time. Settings can never be pinned and is therefore always here.
      await pumpScreen(tester, const MoreScreen());
      await tester.pumpAndSettle();

      expect(find.text('Studentische E-Mail'), findsNothing);
      // "App" is the last category of the hub and sits below the fold on a
      // test viewport, so the row has to be scrolled to before it exists.
      await tester.scrollUntilVisible(
        find.text('Einstellungen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Einstellungen'), findsOneWidget);
    });
  });

  group('mail gate', () {
    testWidgets('shows the sign-in screen when signed out', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(FakeMailGateway(), InMemoryMailCredentialStore()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verbindung prüfen und anmelden'), findsOneWidget);
      expect(find.text('E-Mail-Adresse'), findsOneWidget);
    });

    testWidgets('offers automatic attachment downloads during mail setup', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final container = await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(FakeMailGateway(), InMemoryMailCredentialStore()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Anhänge herunterladen'), findsOneWidget);
      expect(container.read(settingsProvider).mailDownloadAttachments, isFalse);

      await tester.tap(find.text('Anhänge herunterladen'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).mailDownloadAttachments, isTrue);
    });

    testWidgets('offers the Exchange calendar as an explicit opt-in', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final container = await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(FakeMailGateway(), InMemoryMailCredentialStore()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Exchange-Termine'), findsOneWidget);
      expect(
        container.read(settingsProvider).mailExchangeCalendarEnabled,
        isFalse,
      );

      await tester.tap(find.text('Exchange-Termine'));
      await tester.pumpAndSettle();

      expect(
        container.read(settingsProvider).mailExchangeCalendarEnabled,
        isTrue,
      );
    });

    testWidgets('shows the cached inbox when an account is stored', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      // The INBOX is served from the offline cache — pre-populate it.
      final MemoryMailCache cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_header()]);
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(FakeMailGateway(), store, cache: cache),
      );
      await tester.pumpAndSettle();

      expect(find.text('Posteingang'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Hallo Welt'), findsOneWidget);
    });

    testWidgets('offers loading 100 older messages at the end of the inbox', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final store = InMemoryMailCredentialStore()..write(_creds);
      final MemoryMailCache cache = MemoryMailCache();
      await cache.saveHeaders(
        List<MailMessageHeader>.generate(
          50,
          (int index) => _header(id: '${150 - index}'),
        ),
      );
      final gateway = FakeMailGateway(
        olderInbox: <MailMessageHeader>[_header(id: '100')],
      );
      final container = await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(gateway, store, cache: cache),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('100 ältere E-Mails laden'),
        500,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('100 ältere E-Mails laden'), findsOneWidget);

      await tester.tap(find.text('100 ältere E-Mails laden'));
      await tester.pumpAndSettle();

      expect(gateway.lastFetchHeadersBeforeId, '101');
      expect(gateway.lastFetchHeadersLimit, 100);
      expect(await cache.readHeaders(), hasLength(51));
      expect(container.read(mailPaginationProvider).hasMore, isFalse);
    });
  });

  group('sign in flow', () {
    testWidgets('rejects an invalid address without calling the server', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final gateway = FakeMailGateway();
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(gateway, InMemoryMailCredentialStore()),
      );
      await tester.pumpAndSettle();

      // Field order: Name, Email, Password.
      await tester.enterText(find.byType(TextFormField).at(1), 'not-an-email');
      await tester.tap(find.text('Verbindung prüfen und anmelden'));
      await tester.pumpAndSettle();

      expect(
        find.text('Bitte gib eine gültige E-Mail-Adresse ein.'),
        findsOneWidget,
      );
      expect(gateway.verifyCalls, 0);
    });

    testWidgets('signs in and reveals the inbox', (WidgetTester tester) async {
      _tallSurface(tester);
      final store = InMemoryMailCredentialStore();
      final gateway = FakeMailGateway(inbox: <MailMessageHeader>[_header()]);
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      // Field order: Name, Email, Password.
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Max Mustermensch',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'stud@hs-anhalt.de',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'pw');
      await tester.tap(find.text('Verbindung prüfen und anmelden'));
      await tester.pumpAndSettle();

      expect(gateway.verifyCalls, 1);
      expect(store.writes, 1);
      expect(store.lastWritten?.displayName, 'Max Mustermensch');
      // The gate switched to the inbox (its masthead names the folder).
      expect(
        find.descendant(
          of: find.byType(ScreenHeader),
          matching: find.text('Posteingang'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows a loading state while verifying', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final gateway = FakeMailGateway(
        verifyGate: Completer<void>(),
        verifyStarted: Completer<void>(),
      );
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(gateway, InMemoryMailCredentialStore()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'stud@hs-anhalt.de',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'pw');
      await tester.tap(find.text('Verbindung prüfen und anmelden'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Verbindung wird geprüft …'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Verbindung wird geprüft …'),
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
            .widget<EditableText>(find.byType(EditableText).at(2))
            .focusNode
            .hasFocus,
        isFalse,
      );
      expect(
        tester
            .widgetList<PopScope>(find.byType(PopScope))
            .any((PopScope scope) => !scope.canPop),
        isTrue,
      );

      gateway.verifyGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a stalled verification releases the form with a timeout', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final gateway = FakeMailGateway(verifyGate: Completer<void>());
      final store = InMemoryMailCredentialStore();
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'stud@hs-anhalt.de',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'pw');
      await tester.tap(find.text('Verbindung prüfen und anmelden'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(
        find.text('Zeitüberschreitung bei der Verbindung zum Mailserver.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(store.writes, 0);
    });

    testWidgets('a distinguishable error is shown and allows a retry', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final gateway = FakeMailGateway(
        verifyError: const MailFailure(MailFailureKind.serverUnreachable),
      );
      final store = InMemoryMailCredentialStore();
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'stud@hs-anhalt.de',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'pw');
      await tester.tap(find.text('Verbindung prüfen und anmelden'));
      await tester.pumpAndSettle();

      expect(
        find.text('Der Mailserver ist derzeit nicht erreichbar.'),
        findsOneWidget,
      );
      expect(store.writes, 0);
      // No stuck spinner and the form stays interactive for a retry.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gateway.verifyError = null;
      await tester.tap(find.text('Verbindung prüfen und anmelden'));
      await tester.pumpAndSettle();

      expect(store.writes, 1);
    });

    testWidgets(
      'leaving the screen mid sign-in keeps a late failure off the next screen',
      (WidgetTester tester) async {
        _tallSurface(tester);
        final gateway = FakeMailGateway(
          verifyGate: Completer<void>(),
          verifyStarted: Completer<void>(),
          verifyError: const MailFailure(MailFailureKind.timeout),
        );
        final store = InMemoryMailCredentialStore();
        final ValueNotifier<bool> showSetup = ValueNotifier<bool>(true);
        final container = await pumpScreen(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: showSetup,
            builder: (BuildContext context, bool show, _) => show
                ? const MailSetupScreen()
                : const Scaffold(body: Text('Woanders im Campus')),
          ),
          overrides: _mail(gateway, store),
        );
        await tester.pumpAndSettle();
        addTearDown(container.dispose);

        await tester.enterText(
          find.byType(TextFormField).at(1),
          'stud@hs-anhalt.de',
        );
        await tester.enterText(find.byType(TextFormField).at(2), 'pw');
        await tester.tap(find.text('Verbindung prüfen und anmelden'));
        await tester.pump();

        // The user leaves the sign-in screen while verification is still
        // hanging on the server.
        showSetup.value = false;
        await tester.pumpAndSettle();
        expect(find.text('Woanders im Campus'), findsOneWidget);

        // The verification now fails, long after the screen was abandoned.
        gateway.verifyGate!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('Woanders im Campus'), findsOneWidget);
        expect(store.writes, 0);
      },
    );
  });

  group('university identity reuse', () {
    testWidgets(
      'ticking "also use for other services" retains the identity centrally',
      (WidgetTester tester) async {
        _tallSurface(tester);
        final store = InMemoryMailCredentialStore();
        final gateway = FakeMailGateway();
        final identityStore = _MemoryIdentityStore();
        await pumpScreen(
          tester,
          const MailSetupScreen(),
          overrides: _mail(gateway, store),
          universityIdentityStore: identityStore,
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(1),
          'stud@hs-anhalt.de',
        );
        await tester.enterText(find.byType(TextFormField).at(2), 'pw');
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verbindung prüfen und anmelden'));
        await tester.pumpAndSettle();

        expect(identityStore.writes, 1);
        expect(identityStore.value?.identifier, 'stud@hs-anhalt.de');
        expect(identityStore.value?.password, 'pw');
      },
    );

    testWidgets(
      'does not retain centrally when the reuse box is left unticked',
      (WidgetTester tester) async {
        _tallSurface(tester);
        final identityStore = _MemoryIdentityStore();
        await pumpScreen(
          tester,
          const MailSetupScreen(),
          overrides: _mail(FakeMailGateway(), InMemoryMailCredentialStore()),
          universityIdentityStore: identityStore,
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(1),
          'stud@hs-anhalt.de',
        );
        await tester.enterText(find.byType(TextFormField).at(2), 'pw');
        await tester.tap(find.text('Verbindung prüfen und anmelden'));
        await tester.pumpAndSettle();

        expect(identityStore.writes, 0);
      },
    );

    testWidgets('hides the reuse offer once a central identity is stored', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      await pumpScreen(
        tester,
        const MailSetupScreen(),
        overrides: _mail(FakeMailGateway(), InMemoryMailCredentialStore()),
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

  group('inbox actions', () {
    testWidgets('removing the account returns to the sign-in screen', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final store = InMemoryMailCredentialStore()..write(_creds);
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(
          FakeMailGateway(inbox: <MailMessageHeader>[_header()]),
          store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('E-Mail-Verbindung und lokale Daten löschen'));
      await tester.pumpAndSettle();
      // Confirm in the dialog.
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();

      expect(store.clears, greaterThanOrEqualTo(1));
      expect(find.text('Verbindung prüfen und anmelden'), findsOneWidget);
    });
  });

  group('message detail', () {
    testWidgets('renders the plain-text body and marks it seen', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        detail: MailMessageDetail(
          id: '1',
          subject: 'Betreff',
          from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
          to: const <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
          date: null,
          body: 'Dies ist der Nachrichtentext.',
          attachments: <MailAttachment>[
            MailAttachment(
              filename: 'bericht.pdf',
              mediaType: 'application/pdf',
              sizeBytes: 2048,
            ),
            MailAttachment(
              filename: 'bild.png',
              mediaType: 'image/png',
              bytes: Uint8List.fromList(_pngBytes),
            ),
          ],
        ),
      );
      await pumpScreen(
        tester,
        const MailMessageScreen(id: '1'),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      expect(find.text('Betreff'), findsOneWidget);
      expect(find.text('Dies ist der Nachrichtentext.'), findsOneWidget);
      expect(find.byIcon(AppIcons.image_not_supported_outlined), findsNothing);
      expect(gateway.markedSeen, contains('1'));
      // Attachments are listed; the image previews inline automatically.
      expect(find.text('Anhänge'), findsOneWidget);
      expect(find.text('bericht.pdf'), findsOneWidget);
      expect(find.text('bild.png'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets(
      'renders image attachments inline automatically for external senders',
      (WidgetTester tester) async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final gateway = FakeMailGateway(
          detail: MailMessageDetail(
            id: '1',
            subject: 'Werbung',
            from: const MailAddress(email: 'promo@example.com'),
            to: const <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
            date: null,
            body: 'Body',
            attachments: <MailAttachment>[
              MailAttachment(
                filename: 'bild.png',
                mediaType: 'image/png',
                bytes: Uint8List.fromList(_pngBytes),
              ),
            ],
          ),
        );
        await pumpScreen(
          tester,
          const MailMessageScreen(id: '1'),
          overrides: _mail(gateway, store),
        );
        await tester.pumpAndSettle();

        // The image is shown automatically without a manual load step.
        expect(find.text('Bild laden'), findsNothing);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'downloads a missing attachment on demand, caches it and opens it',
      (WidgetTester tester) async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final cache = MemoryMailCache();
        await cache.saveMessage(
          const MailMessageDetail(
            id: '1',
            subject: 'Unterlagen',
            from: MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
            to: <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
            date: null,
            body: 'Im Anhang.',
            attachments: <MailAttachment>[
              MailAttachment(
                filename: 'hinweise.txt',
                mediaType: 'text/plain',
                sizeBytes: 3,
              ),
            ],
          ),
        );
        final downloaded = Uint8List.fromList(<int>[65, 66, 67]);
        final gateway = FakeMailGateway(
          detail: MailMessageDetail(
            id: '1',
            subject: 'Unterlagen',
            from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
            to: const <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
            date: null,
            body: 'Im Anhang.',
            attachments: <MailAttachment>[
              MailAttachment(
                filename: 'hinweise.txt',
                mediaType: 'text/plain',
                sizeBytes: downloaded.length,
                bytes: downloaded,
              ),
            ],
          ),
        );

        await pumpScreen(
          tester,
          const MailMessageScreen(id: '1'),
          overrides: _mail(gateway, store, cache: cache),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('hinweise.txt'));
        await tester.pumpAndSettle();

        expect(gateway.lastIncludeAttachmentBytes, isTrue);
        expect(find.byType(DocumentViewerScreen), findsOneWidget);
        expect(
          (await cache.readMessage('1'))!.attachments.single.bytes,
          downloaded,
        );
      },
    );

    testWidgets('an https link in the body opens via the safe launcher', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        detail: MailMessageDetail(
          id: '1',
          subject: 'Betreff',
          from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
          to: const <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
          date: null,
          body: 'Siehe https://hs-anhalt.de/mensa für Details.',
        ),
      );
      final _FakeLauncher launcher = _FakeLauncher();
      await pumpScreen(
        tester,
        const MailMessageScreen(id: '1'),
        overrides: <Override>[
          ..._mail(gateway, store),
          linkLauncherProvider.overrideWithValue(launcher),
        ],
      );
      await tester.pumpAndSettle();

      final SelectableText body = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      TapGestureRecognizer? recognizer;
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == 'https://hs-anhalt.de/mensa' &&
              span.recognizer is TapGestureRecognizer) {
            recognizer = span.recognizer as TapGestureRecognizer;
          }
          span.children?.forEach(visit);
        }
      }

      visit(body.textSpan!);
      expect(recognizer, isNotNull);
      recognizer!.onTap!();
      await tester.pumpAndSettle();

      expect(launcher.opened, <String>['https://hs-anhalt.de/mensa']);
    });
  });

  group('folders', () {
    testWidgets('keeps Posteingang on the same header row as the actions', (
      WidgetTester tester,
    ) async {
      await (FontLoader('AlbertSans')
            ..addFont(rootBundle.load('assets/fonts/AlbertSans-Variable.ttf')))
          .load();
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = InMemoryMailCredentialStore()..write(_creds);
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(FakeMailGateway(), store),
      );
      await tester.pumpAndSettle();

      final Finder title = find.descendant(
        of: find.byType(ScreenHeader),
        matching: find.text('Posteingang'),
      );
      final Text titleText = tester.widget<Text>(title);
      expect(titleText.maxLines, 1);
      expect(titleText.softWrap, isFalse);
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      expect(
        (tester.getCenter(find.byTooltip('Ordner wählen')).dy -
                tester.getCenter(title).dy)
            .abs(),
        lessThan(30),
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Synchronisieren'), findsOneWidget);
    });

    testWidgets('truncates long folder names and retains the full name', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const String longName =
          'Sehr langer benutzerdefinierter Ordner für Studienunterlagen';
      final store = InMemoryMailCredentialStore()..write(_creds);
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(
          FakeMailGateway(
            folders: const <MailFolder>[
              MailFolder.inbox(),
              MailFolder(path: 'long', name: longName),
            ],
          ),
          store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Ordner wählen'));
      await tester.pumpAndSettle();
      final Text pickerName = tester.widget<Text>(find.text(longName));
      expect(pickerName.maxLines, 1);
      expect(pickerName.overflow, TextOverflow.ellipsis);

      await tester.tap(find.text(longName));
      await tester.pumpAndSettle();
      final Finder title = find.descendant(
        of: find.byType(ScreenHeader),
        matching: find.text(longName),
      );
      final Text titleText = tester.widget<Text>(title);
      expect(titleText.maxLines, 1);
      expect(titleText.overflow, TextOverflow.ellipsis);
      expect(find.byTooltip(longName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('folder picker lists mailboxes and switches the selection', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        inbox: <MailMessageHeader>[_header()],
        folders: const <MailFolder>[
          MailFolder.inbox(),
          MailFolder(path: 'Sent', name: 'Sent', role: MailFolderRole.sent),
        ],
      );
      await pumpScreen(
        tester,
        const MailScreen(),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      // Open the folder picker and choose "Sent" (localised to "Gesendet").
      await tester.tap(find.byIcon(AppIcons.folder_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Gesendet'), findsOneWidget);
      await tester.tap(find.text('Gesendet'));
      await tester.pumpAndSettle();

      // The list was re-fetched for the Sent mailbox and the title updated.
      expect(gateway.fetchedMailboxes, contains('Sent'));
      expect(
        find.descendant(
          of: find.byType(ScreenHeader),
          matching: find.text('Gesendet'),
        ),
        findsOneWidget,
      );
    });
  });

  group('search', () {
    MailMessageHeader hdr(String id, String subject, {String? name}) =>
        MailMessageHeader(
          id: id,
          subject: subject,
          from: MailAddress(email: 'buchhaltung@hs-anhalt.de', name: name),
          date: DateTime.utc(2026, 3, 1, 8),
          isSeen: true,
          hasAttachments: false,
        );

    MailMessageDetail dtl(String id, String subject, String body) =>
        MailMessageDetail(
          id: id,
          subject: subject,
          from: const MailAddress(
            email: 'buchhaltung@hs-anhalt.de',
            name: 'Buchhaltung',
          ),
          to: const <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
          date: DateTime.utc(2026, 3, 1, 8),
          body: body,
        );

    Future<MemoryMailCache> cachedInbox() async {
      final MemoryMailCache cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[
        hdr('1', 'Rechnung 2026', name: 'Buchhaltung'),
      ]);
      await cache.saveMessage(dtl('1', 'Rechnung 2026', 'Anbei die Rechnung.'));
      return cache;
    }

    Future<void> search(WidgetTester tester, String term) async {
      await tester.enterText(find.byType(TextField), term);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    testWidgets('shows a cached hit without contacting the server', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      await pumpScreen(
        tester,
        const MailSearchScreen(),
        overrides: _mail(gateway, store, cache: await cachedInbox()),
      );
      await tester.pumpAndSettle();

      await search(tester, 'rechnung');

      expect(find.text('Rechnung 2026'), findsOneWidget);
      expect(gateway.lastSearchQuery, isNull, reason: 'offline-capable');
      expect(find.text('Zusätzlich auf dem Server suchen'), findsOneWidget);
    });

    testWidgets('builds long cached search results lazily', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[
        for (int index = 0; index < 80; index++)
          hdr('$index', 'Rechnung $index'),
      ]);

      await pumpScreen(
        tester,
        const MailSearchScreen(),
        overrides: _mail(FakeMailGateway(), store, cache: cache),
      );
      await tester.pumpAndSettle();
      await search(tester, 'rechnung');

      expect(find.text('Rechnung 0'), findsOneWidget);
      expect(
        find.text('Rechnung 79'),
        findsNothing,
        reason: 'off-screen mail tiles must not be built eagerly',
      );

      await tester.scrollUntilVisible(
        find.text('Rechnung 79'),
        500,
        scrollable: find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Rechnung 79'), findsOneWidget);
    });

    testWidgets('adds server hits on request, without duplicates', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        searchResults: <MailMessageHeader>[
          hdr('1', 'Rechnung 2026', name: 'Buchhaltung'),
          hdr('9', 'Rechnung 2025', name: 'Archiv'),
        ],
      );
      await pumpScreen(
        tester,
        const MailSearchScreen(),
        overrides: _mail(gateway, store, cache: await cachedInbox()),
      );
      await tester.pumpAndSettle();
      await search(tester, 'rechnung');

      await tester.tap(find.text('Zusätzlich auf dem Server suchen'));
      await tester.pumpAndSettle();

      expect(gateway.lastSearchQuery, 'rechnung');
      expect(find.text('Rechnung 2025'), findsOneWidget);
      expect(
        find.text('Rechnung 2026'),
        findsOneWidget,
        reason: 'the cached hit is not repeated as a server hit',
      );
      // The section eyebrow renders in capitals but keeps its accessible name.
      expect(
        find.bySemanticsLabel('Weitere Treffer vom Server'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Auf dem Gerät gefunden'), findsOneWidget);
    });

    testWidgets('keeps local hits when the server search fails, and retries', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        searchError: const MailFailure(MailFailureKind.serverUnreachable),
      );
      await pumpScreen(
        tester,
        const MailSearchScreen(),
        overrides: _mail(gateway, store, cache: await cachedInbox()),
      );
      await tester.pumpAndSettle();
      await search(tester, 'rechnung');

      await tester.tap(find.text('Zusätzlich auf dem Server suchen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Der Mailserver ist derzeit nicht erreichbar.'),
        findsOneWidget,
      );
      expect(
        find.text('Rechnung 2026'),
        findsOneWidget,
        reason: 'an IMAP failure never clears what the device already found',
      );

      gateway.searchError = null;
      gateway.searchResults = <MailMessageHeader>[
        hdr('9', 'Rechnung 2025', name: 'Archiv'),
      ];
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();

      expect(find.text('Rechnung 2025'), findsOneWidget);
      expect(find.text('Rechnung 2026'), findsOneWidget);
    });

    testWidgets('shows a clear state for zero hits', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        searchResults: const <MailMessageHeader>[],
      );
      await pumpScreen(
        tester,
        const MailSearchScreen(),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      await search(tester, 'nichts-passt');

      expect(find.text('Keine Treffer'), findsOneWidget);
      expect(
        find.text(
          'Auf dem Gerät wurde nichts gefunden. Du kannst zusätzlich auf dem '
          'Server suchen.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Zusätzlich auf dem Server suchen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Zu dieser Suche wurden keine Nachrichten gefunden.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'opening a hit not present in the local cache loads it from the server',
      (WidgetTester tester) async {
        // Regression for the search "open the correct, possibly non-cached
        // hit" requirement: MailMessageScreen must resolve a message that is
        // NOT pre-seeded in the offline cache by falling back to the gateway.
        final store = InMemoryMailCredentialStore()..write(_creds);
        final gateway = FakeMailGateway(
          detailsById: <String, MailMessageDetail>{
            '9': MailMessageDetail(
              id: '9',
              subject: 'Rechnung 2026',
              from: const MailAddress(email: 'buchhaltung@hs-anhalt.de'),
              to: const <MailAddress>[],
              cc: const <MailAddress>[],
              date: DateTime.utc(2026, 3, 1, 8),
              body: 'Anbei die Rechnung.',
            ),
          },
        );
        final MemoryMailCache cache = MemoryMailCache();
        await pumpScreen(
          tester,
          const MailMessageScreen(id: '9'),
          overrides: _mail(gateway, store, cache: cache),
        );
        await tester.pumpAndSettle();

        expect(find.text('Anbei die Rechnung.'), findsOneWidget);
        expect(gateway.markedSeen, contains('9'));
        expect(
          await cache.readMessage('9'),
          isNotNull,
          reason: 'a server-only hit is cached once opened',
        );
      },
    );
  });

  group('compose', () {
    testWidgets('rejects an invalid recipient without sending', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'nonsense');
      await tester.tap(find.byIcon(AppIcons.send_outlined));
      await tester.pumpAndSettle();

      expect(
        find.text('Bitte gib eine gültige Empfängeradresse ein.'),
        findsOneWidget,
      );
      expect(gateway.sendCalls, 0);
    });

    testWidgets('sends a message and confirms', (WidgetTester tester) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      // Field order: To, Cc, Subject, Body.
      await tester.enterText(find.byType(TextFormField).at(0), 'x@y.de');
      await tester.enterText(find.byType(TextFormField).at(2), 'Betreff');
      await tester.enterText(find.byType(TextFormField).at(3), 'Text');
      await tester.tap(find.byIcon(AppIcons.send_outlined));
      await tester.pumpAndSettle();

      expect(gateway.sendCalls, 1);
      expect(gateway.sent.single.to, <String>['x@y.de']);
      expect(find.text('Nachricht gesendet.'), findsOneWidget);
    });

    testWidgets('prefills recipients and subject from a reply draft', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      await pumpScreen(
        tester,
        const MailComposeScreen(
          draft: ComposeDraft(
            to: <String>['alice@hs-anhalt.de'],
            cc: <String>['bob@hs-anhalt.de'],
            subject: 'Re: Hallo',
          ),
        ),
        overrides: _mail(gateway, store),
      );
      await tester.pumpAndSettle();

      expect(find.text('alice@hs-anhalt.de'), findsOneWidget);
      expect(find.text('bob@hs-anhalt.de'), findsOneWidget);
      expect(find.text('Re: Hallo'), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.send_outlined));
      await tester.pumpAndSettle();

      expect(gateway.sent.single.to, <String>['alice@hs-anhalt.de']);
      expect(gateway.sent.single.cc, <String>['bob@hs-anhalt.de']);
    });
  });

  group('compose attachments', () {
    Future<void> fillRecipientAndSubject(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).at(0), 'x@y.de');
      await tester.enterText(find.byType(TextFormField).at(2), 'Anhang-Test');
      await tester.enterText(find.byType(TextFormField).at(3), 'Text');
    }

    testWidgets('picks a file and lists it with name and size', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      final picker = FakeMailAttachmentPicker(
        results: <MailFilePickResult>[
          MailFilesPicked(<PickedMailFile>[
            FakePickedMailFile(
              filename: 'foto.png',
              mediaType: 'image/png',
              bytes: Uint8List.fromList(_pngBytes),
            ),
          ]),
        ],
      );
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: <Override>[
          ..._mail(gateway, store),
          mailAttachmentPickerProvider.overrideWithValue(picker),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.attach_file));
      await tester.pumpAndSettle();

      expect(find.text('foto.png'), findsOneWidget);
      expect(picker.calls, 1);
    });

    testWidgets('rejects an oversized file before reading it', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final FakePickedMailFile file = FakePickedMailFile(
        filename: 'too-large.bin',
        mediaType: 'application/octet-stream',
        bytes: Uint8List(1),
        reportedSizeBytes: MailAttachmentLimits.maxFileBytes + 1,
      );
      final picker = FakeMailAttachmentPicker(
        results: <MailFilePickResult>[
          MailFilesPicked(<PickedMailFile>[file]),
        ],
      );
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: <Override>[
          ..._mail(FakeMailGateway(), store),
          mailAttachmentPickerProvider.overrideWithValue(picker),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.attach_file));
      await tester.pumpAndSettle();

      expect(find.text('too-large.bin'), findsNothing);
      expect(find.textContaining('20 MB'), findsOneWidget);
      expect(file.readCalls, 0);
    });

    testWidgets('removes a picked attachment before sending', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      final picker = FakeMailAttachmentPicker(
        results: <MailFilePickResult>[
          MailFilesPicked(<PickedMailFile>[
            FakePickedMailFile(
              filename: 'foto.png',
              mediaType: 'image/png',
              bytes: Uint8List.fromList(_pngBytes),
            ),
          ]),
        ],
      );
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: <Override>[
          ..._mail(gateway, store),
          mailAttachmentPickerProvider.overrideWithValue(picker),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.attach_file));
      await tester.pumpAndSettle();
      expect(find.text('foto.png'), findsOneWidget);

      final Finder removeButton = find.widgetWithIcon(
        IconButton,
        AppIcons.close,
      );
      await tester.ensureVisible(removeButton);
      await tester.drag(find.byType(ListView).last, const Offset(0, -80));
      await tester.pumpAndSettle();
      await tester.tap(removeButton);
      await tester.pumpAndSettle();

      expect(find.text('foto.png'), findsNothing);
    });

    testWidgets('a cancelled pick leaves the draft unchanged', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      final picker = FakeMailAttachmentPicker(
        results: const <MailFilePickResult>[MailFilePickCancelled()],
      );
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: <Override>[
          ..._mail(gateway, store),
          mailAttachmentPickerProvider.overrideWithValue(picker),
        ],
      );
      await tester.pumpAndSettle();
      await fillRecipientAndSubject(tester);

      await tester.tap(find.byIcon(AppIcons.attach_file));
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.close), findsNothing);
      expect(find.text('x@y.de'), findsOneWidget);
      expect(find.text('Anhang-Test'), findsOneWidget);
    });

    testWidgets('a sent message includes the picked attachment', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      final Uint8List bytes = Uint8List.fromList(_pngBytes);
      final picker = FakeMailAttachmentPicker(
        results: <MailFilePickResult>[
          MailFilesPicked(<PickedMailFile>[
            FakePickedMailFile(
              filename: 'foto.png',
              mediaType: 'image/png',
              bytes: bytes,
            ),
          ]),
        ],
      );
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: <Override>[
          ..._mail(gateway, store),
          mailAttachmentPickerProvider.overrideWithValue(picker),
        ],
      );
      await tester.pumpAndSettle();
      await fillRecipientAndSubject(tester);
      await tester.tap(find.byIcon(AppIcons.attach_file));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.send_outlined));
      await tester.pumpAndSettle();

      expect(gateway.sent.single.attachments, hasLength(1));
      expect(gateway.sent.single.attachments.single.filename, 'foto.png');
      expect(gateway.sent.single.attachments.single.mediaType, 'image/png');
      expect(gateway.sent.single.attachments.single.bytes, bytes);
    });

    testWidgets('a read failure at send time keeps the screen and draft intact', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      final picker = FakeMailAttachmentPicker(
        results: <MailFilePickResult>[
          MailFilesPicked(<PickedMailFile>[
            FakePickedMailFile(
              filename: 'foto.png',
              mediaType: 'image/png',
              bytes: Uint8List.fromList(_pngBytes),
              readError: Exception('vanished'),
            ),
          ]),
        ],
      );
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: <Override>[
          ..._mail(gateway, store),
          mailAttachmentPickerProvider.overrideWithValue(picker),
        ],
      );
      await tester.pumpAndSettle();
      await fillRecipientAndSubject(tester);
      await tester.tap(find.byIcon(AppIcons.attach_file));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.send_outlined));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Eine ausgewählte Datei konnte nicht gelesen werden. Bitte prüfe sie und versuche es erneut.',
        ),
        findsOneWidget,
      );
      expect(gateway.sendCalls, 0, reason: 'no automatic retry, no send');
      expect(find.byType(MailComposeScreen), findsOneWidget);
      expect(
        find.text('foto.png'),
        findsOneWidget,
        reason: 'attachment stays listed',
      );
      expect(
        find.text('x@y.de'),
        findsOneWidget,
        reason: 'recipient stays intact',
      );
    });

    testWidgets('sending disables attach and remove controls', (
      WidgetTester tester,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        sendGate: Completer<void>(),
        sendStarted: Completer<void>(),
      );
      final picker = FakeMailAttachmentPicker(
        results: <MailFilePickResult>[
          MailFilesPicked(<PickedMailFile>[
            FakePickedMailFile(
              filename: 'foto.png',
              mediaType: 'image/png',
              bytes: Uint8List.fromList(_pngBytes),
            ),
          ]),
        ],
      );
      await pumpScreen(
        tester,
        const MailComposeScreen(),
        overrides: <Override>[
          ..._mail(gateway, store),
          mailAttachmentPickerProvider.overrideWithValue(picker),
        ],
      );
      await tester.pumpAndSettle();
      await fillRecipientAndSubject(tester);
      await tester.tap(find.byIcon(AppIcons.attach_file));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.send_outlined));
      await gateway.sendStarted!.future;
      await tester.pump();

      final IconButton attachButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, AppIcons.attach_file),
      );
      expect(attachButton.onPressed, isNull);
      final IconButton removeButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, AppIcons.close),
      );
      expect(removeButton.onPressed, isNull);

      gateway.sendGate!.complete();
      await tester.pumpAndSettle();
    });
  });
}
