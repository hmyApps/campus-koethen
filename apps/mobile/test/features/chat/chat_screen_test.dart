// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/chat/application/chat_providers.dart';
import 'package:campus_koethen/features/chat/domain/chat_models.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:campus_koethen/features/chat/domain/matrix_homeserver.dart';
import 'package:campus_koethen/features/chat/presentation/chat_room_screen.dart';
import 'package:campus_koethen/features/chat/presentation/chat_screen.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_matrix_gateway.dart';
import '../../support/pump_app.dart';

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('de'));
  final MatrixHomeserver server = MatrixHomeserver.parse(
    'https://matrix.example.test',
  )!;
  late FakeMatrixGateway gateway;

  setUp(() => gateway = FakeMatrixGateway());

  Future<void> pumpChat(
    WidgetTester tester, {
    MatrixHomeserver? homeserver,
    Widget screen = const ChatScreen(),
  }) async {
    await pumpScreen(
      tester,
      screen,
      overrides: [
        matrixHomeserverProvider.overrideWithValue(homeserver),
        matrixGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await tester.pumpAndSettle();
  }

  final ChatMessage peerMessage = ChatMessage(
    id: r'$demo-1',
    senderName: 'Demo-Kontakt',
    isMine: false,
    kind: ChatMessageKind.text,
    body: 'Demo-Nachricht',
    timestamp: _demoTime,
  );

  group('ChatScreen', () {
    testWidgets('says so when this build has no homeserver', (
      WidgetTester tester,
    ) async {
      await pumpChat(tester);

      expect(find.text(l10n.chatNotConfigured), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('signed out, it asks for the Matrix login and names the '
        'server it talks to', (WidgetTester tester) async {
      await pumpChat(tester, homeserver: server);

      expect(find.text(l10n.chatLoginIntro(server.host)), findsOneWidget);
      expect(find.text(l10n.chatLoginTestNotice), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('an incomplete form is not sent', (WidgetTester tester) async {
      await pumpChat(tester, homeserver: server);

      await tester.tap(find.text(l10n.chatLoginAction));
      await tester.pumpAndSettle();

      expect(find.text(l10n.chatLoginMissingFields), findsOneWidget);
      expect(gateway.logins, isEmpty);
    });

    testWidgets('a wrong password is explained and the password field '
        'emptied', (WidgetTester tester) async {
      gateway.loginFailure = const MatrixFailure(
        MatrixFailureKind.invalidCredentials,
      );
      await pumpChat(tester, homeserver: server);

      await tester.enterText(find.byType(TextField).first, 'demo-user');
      await tester.enterText(find.byType(TextField).last, 'wrong');
      await tester.tap(find.text(l10n.chatLoginAction));
      await tester.pumpAndSettle();

      expect(gateway.logins, <(String, String)>[('demo-user', 'wrong')]);
      expect(find.text(l10n.chatErrorInvalidCredentials), findsOneWidget);
      expect(find.text('wrong'), findsNothing);
      expect(find.text('demo-user'), findsOneWidget);
    });

    testWidgets('signing in shows the conversations', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      gateway.roomList = <ChatRoomSummary>[
        ChatRoomSummary(
          id: '!demo:matrix.example.test',
          title: 'Demo-Gruppe',
          isDirect: false,
          isEncrypted: true,
          isInvite: false,
          unreadCount: 3,
          lastMessage: peerMessage,
        ),
      ];
      await pumpChat(tester, homeserver: server);

      await tester.enterText(find.byType(TextField).first, 'demo-user');
      await tester.enterText(find.byType(TextField).last, 'demo-password');
      await tester.tap(find.text(l10n.chatLoginAction));
      await tester.pumpAndSettle();

      expect(find.text('Demo-Gruppe'), findsOneWidget);
      expect(
        find.text(l10n.chatPreviewLine('Demo-Kontakt', 'Demo-Nachricht')),
        findsOneWidget,
      );
      // ListTile merges its parts into one node; the count is part of it.
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(l10n.chatUnreadCount(3)))),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('invitations can be accepted or declined', (
      WidgetTester tester,
    ) async {
      gateway.stored = FakeMatrixGateway.demoAccount;
      gateway.roomList = <ChatRoomSummary>[
        const ChatRoomSummary(
          id: '!invite:matrix.example.test',
          title: 'Demo-Einladung',
          isDirect: false,
          isEncrypted: false,
          isInvite: true,
          unreadCount: 0,
        ),
      ];
      await pumpChat(tester, homeserver: server);

      expect(
        find.textContaining(
          RegExp(l10n.chatInvitesHeader, caseSensitive: false),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.chatInviteAccept));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.chatInviteDecline));
      await tester.pumpAndSettle();

      expect(gateway.accepted, <String>['!invite:matrix.example.test']);
      expect(gateway.declined, <String>['!invite:matrix.example.test']);
    });

    testWidgets('a room without a name gets a placeholder, not an ID', (
      WidgetTester tester,
    ) async {
      gateway.stored = FakeMatrixGateway.demoAccount;
      gateway.roomList = <ChatRoomSummary>[
        const ChatRoomSummary(
          id: '!unnamed:matrix.example.test',
          isDirect: false,
          isEncrypted: true,
          isInvite: false,
          unreadCount: 0,
        ),
      ];
      await pumpChat(tester, homeserver: server);

      expect(find.text(l10n.chatUntitledRoom), findsOneWidget);
      expect(find.textContaining('!unnamed'), findsNothing);
    });

    testWidgets('signing out asks first, then wipes and returns to the login', (
      WidgetTester tester,
    ) async {
      gateway.stored = FakeMatrixGateway.demoAccount;
      await pumpChat(tester, homeserver: server);

      await tester.tap(find.byTooltip(l10n.chatAccountMenu));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.chatSignedInAs(FakeMatrixGateway.demoAccount.userId)),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.chatLogout));
      await tester.pumpAndSettle();
      expect(find.text(l10n.chatLogoutConfirmMessage), findsOneWidget);
      await tester.tap(find.text(l10n.chatLogoutConfirmAction));
      await tester.pumpAndSettle();

      expect(gateway.logouts, 1);
      expect(find.text(l10n.chatLoginAction), findsOneWidget);
    });

    testWidgets('an unreadable local database offers deleting it', (
      WidgetTester tester,
    ) async {
      gateway.restoreFailure = const MatrixFailure(
        MatrixFailureKind.databaseUnavailable,
      );
      await pumpChat(tester, homeserver: server);

      expect(find.text(l10n.chatErrorDatabase), findsOneWidget);
      await tester.dragUntilVisible(
        find.text(l10n.chatResetLocalData),
        find.byType(ListView),
        const Offset(0, -100),
      );
      await tester.tap(find.text(l10n.chatResetLocalData));
      await tester.pumpAndSettle();

      expect(gateway.logouts, 1);
    });
  });

  group('ChatRoomScreen', () {
    const String roomId = '!demo:matrix.example.test';

    setUp(() {
      gateway.stored = FakeMatrixGateway.demoAccount;
      gateway.roomList = <ChatRoomSummary>[
        const ChatRoomSummary(
          id: roomId,
          title: 'Demo-Gruppe',
          isDirect: false,
          isEncrypted: true,
          isInvite: false,
          unreadCount: 0,
        ),
      ];
    });

    testWidgets('shows the messages, what cannot be read and the encryption', (
      WidgetTester tester,
    ) async {
      gateway.timelines[roomId] = FakeChatRoomTimeline(<ChatMessage>[
        ChatMessage(
          id: r'$demo-2',
          senderName: 'Demo-Kontakt',
          isMine: false,
          kind: ChatMessageKind.undecryptable,
          body: '',
          timestamp: _demoTime,
        ),
        peerMessage,
      ]);
      await pumpChat(
        tester,
        homeserver: server,
        screen: const ChatRoomScreen(roomId: roomId),
      );

      expect(find.text('Demo-Gruppe'), findsOneWidget);
      expect(find.text(l10n.chatEncrypted), findsOneWidget);
      expect(find.text('Demo-Nachricht'), findsOneWidget);
      expect(find.text(l10n.chatMessageUndecryptable), findsOneWidget);
      expect(gateway.timelines[roomId]!.markReadCalls, greaterThan(0));
    });

    testWidgets('sends what was typed', (WidgetTester tester) async {
      gateway.timelines[roomId] = FakeChatRoomTimeline(<ChatMessage>[]);
      await pumpChat(
        tester,
        homeserver: server,
        screen: const ChatRoomScreen(roomId: roomId),
      );

      await tester.enterText(find.byType(TextField), 'Demo-Antwort');
      await tester.tap(find.byTooltip(l10n.chatSend));
      await tester.pumpAndSettle();

      expect(gateway.sent, <(String, String)>[(roomId, 'Demo-Antwort')]);
      expect(find.text('Demo-Antwort'), findsNothing);
    });

    testWidgets('a failed send hands the text back with the reason', (
      WidgetTester tester,
    ) async {
      gateway.sendFailure = const MatrixFailure(MatrixFailureKind.sendFailed);
      gateway.timelines[roomId] = FakeChatRoomTimeline(<ChatMessage>[]);
      await pumpChat(
        tester,
        homeserver: server,
        screen: const ChatRoomScreen(roomId: roomId),
      );

      await tester.enterText(find.byType(TextField), 'Demo-Antwort');
      await tester.tap(find.byTooltip(l10n.chatSend));
      await tester.pumpAndSettle();

      expect(find.text('Demo-Antwort'), findsOneWidget);
      expect(find.text(l10n.chatErrorSendFailed), findsOneWidget);
    });

    testWidgets('without a room ID it says the conversation is unavailable', (
      WidgetTester tester,
    ) async {
      await pumpChat(
        tester,
        homeserver: server,
        screen: const ChatRoomScreen(roomId: null),
      );

      expect(find.text(l10n.chatRoomUnavailable), findsOneWidget);
    });

    testWidgets('closes the timeline when left', (WidgetTester tester) async {
      final FakeChatRoomTimeline timeline = FakeChatRoomTimeline(
        <ChatMessage>[],
      );
      gateway.timelines[roomId] = timeline;
      await pumpChat(
        tester,
        homeserver: server,
        screen: const ChatRoomScreen(roomId: roomId),
      );

      await tester.pumpWidget(const SizedBox.shrink());

      expect(timeline.closed, isTrue);
    });
  });
}

final DateTime _demoTime = DateTime.utc(2026, 10, 11, 12);
