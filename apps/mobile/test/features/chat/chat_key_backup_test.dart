// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/chat/application/chat_providers.dart';
import 'package:campus_koethen/features/chat/domain/chat_key_backup.dart';
import 'package:campus_koethen/features/chat/domain/chat_models.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:campus_koethen/features/chat/domain/matrix_homeserver.dart';
import 'package:campus_koethen/features/chat/presentation/chat_key_backup_screen.dart';
import 'package:campus_koethen/features/chat/presentation/chat_screen.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_matrix_gateway.dart';
import '../../support/pump_app.dart';

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('de'));
  late FakeMatrixGateway gateway;

  setUp(
    () => gateway = FakeMatrixGateway(stored: FakeMatrixGateway.demoAccount),
  );

  List<Override> overrides() => [
    matrixHomeserverProvider.overrideWithValue(
      MatrixHomeserver.parse('https://matrix.example.test'),
    ),
    matrixGatewayProvider.overrideWithValue(gateway),
  ];

  group('ChatKeyBackupController', () {
    ProviderContainer containerFor() {
      final ProviderContainer container = ProviderContainer(
        overrides: overrides(),
      );
      addTearDown(container.dispose);
      // Riverpod pauses providers nobody listens to.
      final ProviderSubscription<AsyncValue<ChatKeyBackupState?>> listener =
          container.listen(chatKeyBackupControllerProvider, (_, _) {});
      addTearDown(listener.close);
      return container;
    }

    test('has no state while signed out', () async {
      gateway.stored = null;
      expect(
        await containerFor().read(chatKeyBackupControllerProvider.future),
        isNull,
      );
    });

    test('reads the state of the signed-in account', () async {
      gateway.backupState = ChatKeyBackupState.locked;
      expect(
        await containerFor().read(chatKeyBackupControllerProvider.future),
        ChatKeyBackupState.locked,
      );
    });

    test('set-up hands out the recovery key and ends ready', () async {
      final ProviderContainer container = containerFor();
      await container.read(chatKeyBackupControllerProvider.future);

      final String key = await container
          .read(chatKeyBackupControllerProvider.notifier)
          .setUp();

      expect(key, gateway.recoveryKey);
      expect(
        container.read(chatKeyBackupControllerProvider).value,
        ChatKeyBackupState.ready,
      );
    });
  });

  group('ChatKeyBackupScreen', () {
    Future<void> pumpBackup(WidgetTester tester) async {
      await pumpScreen(
        tester,
        const ChatKeyBackupScreen(),
        overrides: overrides(),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows a new recovery key once and only lets go after '
        'its safekeeping is confirmed', (WidgetTester tester) async {
      await pumpBackup(tester);

      expect(find.text(l10n.chatKeyBackupNotSetUpBody), findsOneWidget);
      await tester.tap(find.text(l10n.chatKeyBackupSetUpAction));
      await tester.pumpAndSettle();

      expect(find.text(gateway.recoveryKey), findsOneWidget);
      final Finder done = find.widgetWithText(
        FilledButton,
        l10n.chatRecoveryKeyDone,
      );
      expect(tester.widget<FilledButton>(done).onPressed, isNull);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);

      await tester.tap(find.text(l10n.chatRecoveryKeySavedConfirm));
      await tester.pumpAndSettle();
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(find.text(gateway.recoveryKey), findsNothing);
      expect(find.text(l10n.chatKeyBackupReady), findsOneWidget);
    });

    testWidgets('asks for the password only when the server wants it, and '
        'uses it once', (WidgetTester tester) async {
      gateway.backupFailure = const MatrixFailure(
        MatrixFailureKind.passwordRequired,
      );
      await pumpBackup(tester);

      await tester.tap(find.text(l10n.chatKeyBackupSetUpAction));
      await tester.pumpAndSettle();
      expect(find.text(l10n.chatKeyBackupPasswordPrompt), findsOneWidget);

      gateway.backupFailure = null;
      await tester.enterText(find.byType(TextField), 'demo-password');
      await tester.tap(find.text(l10n.chatKeyBackupSetUpAction));
      await tester.pumpAndSettle();

      expect(gateway.backupPasswords, <String?>[null, 'demo-password']);
      expect(find.text(gateway.recoveryKey), findsOneWidget);
      expect(find.text('demo-password'), findsNothing);
    });

    testWidgets('unlocks with the recovery key', (WidgetTester tester) async {
      gateway.backupState = ChatKeyBackupState.locked;
      await pumpBackup(tester);

      await tester.enterText(find.byType(TextField), 'EsTd emoD');
      await tester.tap(find.text(l10n.chatKeyBackupUnlockAction));
      await tester.pumpAndSettle();

      expect(gateway.unlockAttempts, <String>['EsTd emoD']);
      expect(find.text(l10n.chatKeyBackupReady), findsOneWidget);
    });

    testWidgets('a wrong recovery key is explained', (
      WidgetTester tester,
    ) async {
      gateway.backupState = ChatKeyBackupState.locked;
      gateway.backupFailure = const MatrixFailure(
        MatrixFailureKind.invalidRecoveryKey,
      );
      await pumpBackup(tester);

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text(l10n.chatKeyBackupUnlockAction));
      await tester.pumpAndSettle();

      expect(find.text(l10n.chatErrorInvalidRecoveryKey), findsOneWidget);
    });

    testWidgets('a lost key is reset only after a warning and with the '
        'password', (WidgetTester tester) async {
      gateway.backupState = ChatKeyBackupState.locked;
      await pumpBackup(tester);

      await tester.tap(find.text(l10n.chatKeyBackupLostKey));
      await tester.pumpAndSettle();
      expect(find.text(l10n.chatKeyBackupResetTitle), findsOneWidget);
      await tester.tap(find.text(l10n.chatKeyBackupResetAction).last);
      await tester.pumpAndSettle();

      // Without a password nothing is sent.
      await tester.tap(find.text(l10n.chatKeyBackupResetAction));
      await tester.pumpAndSettle();
      expect(gateway.backupPasswords, isEmpty);
      expect(find.text(l10n.chatErrorPasswordRequired), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'demo-password');
      await tester.tap(find.text(l10n.chatKeyBackupResetAction));
      await tester.pumpAndSettle();

      expect(gateway.backupPasswords, <String?>['demo-password']);
      expect(find.text(gateway.recoveryKey), findsOneWidget);
    });
  });

  testWidgets('the conversations point to a missing key backup', (
    WidgetTester tester,
  ) async {
    gateway.roomList = <ChatRoomSummary>[
      const ChatRoomSummary(
        id: '!demo:matrix.example.test',
        title: 'Demo-Gruppe',
        isDirect: false,
        isEncrypted: true,
        isInvite: false,
        unreadCount: 0,
      ),
    ];
    await pumpScreen(tester, const ChatScreen(), overrides: overrides());
    await tester.pumpAndSettle();

    expect(find.text(l10n.chatKeyBackupBannerSetUp), findsOneWidget);
  });
}
