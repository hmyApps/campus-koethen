// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/chat/application/chat_providers.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:campus_koethen/features/chat/domain/matrix_homeserver.dart';
import 'package:campus_koethen/features/chat/presentation/chat_new_conversation_sheet.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_matrix_gateway.dart';
import '../../support/pump_app.dart';

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('de'));
  late FakeMatrixGateway gateway;
  String? result;
  bool closed = false;

  setUp(() {
    gateway = FakeMatrixGateway(stored: FakeMatrixGateway.demoAccount);
    result = null;
    closed = false;
  });

  Future<void> openSheet(WidgetTester tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              result = await showNewConversationSheet(context);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        matrixHomeserverProvider.overrideWithValue(
          MatrixHomeserver.parse('https://matrix.example.test'),
        ),
        matrixGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('starts a direct chat with what was typed and returns its room', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);

    expect(find.text(l10n.chatNewChatEncrypted), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'demo-peer');
    await tester.tap(find.text(l10n.chatStartAction));
    await tester.pumpAndSettle();

    expect(gateway.directChats, <String>['demo-peer']);
    expect(closed, isTrue);
    expect(result, gateway.createdRoomId);
  });

  testWidgets('creates a group with every listed member', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);

    await tester.tap(find.text(l10n.chatNewGroup));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Demo-Lerngruppe');
    await tester.enterText(
      find.byType(TextField).last,
      '@demo-a:matrix.example.test, @demo-b:matrix.example.test\ndemo-c',
    );
    await tester.tap(find.text(l10n.chatCreateGroupAction));
    await tester.pumpAndSettle();

    expect(gateway.groups.single.$1, 'Demo-Lerngruppe');
    expect(gateway.groups.single.$2, <String>[
      '@demo-a:matrix.example.test',
      '@demo-b:matrix.example.test',
      'demo-c',
    ]);
    expect(result, gateway.createdRoomId);
  });

  testWidgets('a refusal stays in the sheet with the reason', (
    WidgetTester tester,
  ) async {
    gateway.createFailure = const MatrixFailure(
      MatrixFailureKind.invalidUserId,
    );
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), 'demo peer');
    await tester.tap(find.text(l10n.chatStartAction));
    await tester.pumpAndSettle();

    expect(find.text(l10n.chatErrorInvalidUserId), findsOneWidget);
    expect(closed, isFalse);
  });
}
