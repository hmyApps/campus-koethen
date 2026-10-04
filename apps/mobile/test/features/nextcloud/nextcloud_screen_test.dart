// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/core/documents/document_viewer_screen.dart';
import 'package:campus_koethen/features/nextcloud/application/nextcloud_providers.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_account.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_entry.dart';
import 'package:campus_koethen/features/nextcloud/presentation/nextcloud_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_nextcloud.dart';
import '../../support/pump_app.dart';

const NextcloudCredential _credential = NextcloudCredential(
  server: 'https://cloud.hs-anhalt.de',
  loginName: 'student-login',
  userId: 'student-id',
  appPassword: 'secret',
);

void main() {
  testWidgets('shows signed-out browser-login explanation', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const NextcloudScreen(),
      overrides: [
        nextcloudCredentialStoreProvider.overrideWithValue(
          InMemoryNextcloudCredentialStore(),
        ),
        nextcloudGatewayProvider.overrideWithValue(FakeNextcloudGateway()),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Mit Nextcloud verbinden'), findsOneWidget);
    expect(find.textContaining('widerrufbares App-Passwort'), findsOneWidget);
  });

  testWidgets('navigates folders and opens a downloaded document in-app', (
    WidgetTester tester,
  ) async {
    final InMemoryNextcloudCredentialStore store =
        InMemoryNextcloudCredentialStore()..value = _credential;
    final FakeNextcloudGateway gateway = FakeNextcloudGateway()
      ..entries = const <NextcloudEntry>[
        NextcloudEntry(
          path: '/Documents',
          name: 'Documents',
          isDirectory: true,
        ),
        NextcloudEntry(
          path: '/hello.txt',
          name: 'hello.txt',
          isDirectory: false,
          sizeBytes: 5,
          mediaType: 'text/plain',
        ),
      ]
      ..document = AppDocument(
        filename: 'hello.txt',
        mediaType: 'text/plain',
        bytes: Uint8List.fromList(<int>[104, 101, 108, 108, 111]),
      );
    await pumpScreen(
      tester,
      const NextcloudScreen(),
      overrides: [
        nextcloudCredentialStoreProvider.overrideWithValue(store),
        nextcloudGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Verbunden als student-login'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('hello.txt'), findsOneWidget);

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(gateway.listedPaths, contains('/Documents'));
    expect(find.text('Zum übergeordneten Ordner'), findsOneWidget);

    await tester.tap(find.text('hello.txt'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentViewerScreen), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('does not overflow at narrow width and 200 percent text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final InMemoryNextcloudCredentialStore store =
        InMemoryNextcloudCredentialStore()..value = _credential;
    final FakeNextcloudGateway gateway = FakeNextcloudGateway()
      ..entries = const <NextcloudEntry>[
        NextcloudEntry(
          path: '/A very long folder name for accessibility testing',
          name: 'A very long folder name for accessibility testing',
          isDirectory: true,
        ),
      ];
    await pumpScreen(
      tester,
      const NextcloudScreen(),
      textScaler: const TextScaler.linear(2),
      overrides: [
        nextcloudCredentialStoreProvider.overrideWithValue(store),
        nextcloudGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
