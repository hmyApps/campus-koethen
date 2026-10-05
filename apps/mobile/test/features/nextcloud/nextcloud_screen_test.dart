// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/core/documents/document_viewer_screen.dart';
import 'package:campus_koethen/features/nextcloud/application/nextcloud_providers.dart';
import 'package:campus_koethen/features/nextcloud/data/nextcloud_public_link_sharer.dart';
import 'package:campus_koethen/features/nextcloud/data/nextcloud_upload_picker.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_account.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_entry.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_gateway.dart';
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

  testWidgets('uploads a picked file into the visible folder', (
    WidgetTester tester,
  ) async {
    final InMemoryNextcloudCredentialStore store =
        InMemoryNextcloudCredentialStore()..value = _credential;
    final FakeNextcloudGateway gateway = FakeNextcloudGateway();
    await pumpScreen(
      tester,
      const NextcloudScreen(),
      overrides: [
        nextcloudCredentialStoreProvider.overrideWithValue(store),
        nextcloudGatewayProvider.overrideWithValue(gateway),
        nextcloudUploadPickerProvider.overrideWithValue(
          _UploadPicker(
            NextcloudUploadFile(
              filename: 'upload.txt',
              mediaType: 'text/plain',
              length: 3,
              openRead: () =>
                  Stream<Uint8List>.value(Uint8List.fromList(<int>[1, 2, 3])),
            ),
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Datei hochladen'));
    await tester.pumpAndSettle();

    expect(gateway.uploadedDirectories, <String>['/']);
    expect(find.text('upload.txt wurde hochgeladen.'), findsOneWidget);
  });

  testWidgets('creates a public link only after explicit confirmation', (
    WidgetTester tester,
  ) async {
    final InMemoryNextcloudCredentialStore store =
        InMemoryNextcloudCredentialStore()..value = _credential;
    final FakeNextcloudGateway gateway = FakeNextcloudGateway()
      ..entries = const <NextcloudEntry>[
        NextcloudEntry(
          path: '/notes.txt',
          name: 'notes.txt',
          isDirectory: false,
        ),
      ];
    final _LinkSharer sharer = _LinkSharer();
    await pumpScreen(
      tester,
      const NextcloudScreen(),
      overrides: [
        nextcloudCredentialStoreProvider.overrideWithValue(store),
        nextcloudGatewayProvider.overrideWithValue(gateway),
        nextcloudPublicLinkSharerProvider.overrideWithValue(sharer),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Aktionen für notes.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Öffentlichen Link teilen'));
    await tester.pumpAndSettle();

    expect(gateway.sharedPaths, isEmpty);
    expect(find.textContaining('Jede Person mit dem Link'), findsOneWidget);

    await tester.tap(find.text('Link erstellen und teilen'));
    await tester.pumpAndSettle();

    expect(gateway.sharedPaths, <String>['/notes.txt']);
    expect(sharer.links, <Uri>[gateway.shareLink]);
  });

  testWidgets('deletes a folder only after warning about recursive deletion', (
    WidgetTester tester,
  ) async {
    final InMemoryNextcloudCredentialStore store =
        InMemoryNextcloudCredentialStore()..value = _credential;
    final FakeNextcloudGateway gateway = FakeNextcloudGateway()
      ..entries = const <NextcloudEntry>[
        NextcloudEntry(path: '/Archive', name: 'Archive', isDirectory: true),
      ];
    final InMemoryNextcloudFavouriteStore favourites =
        InMemoryNextcloudFavouriteStore()
          ..value = <String>{'/Archive', '/Archive/old.txt'};
    await pumpScreen(
      tester,
      const NextcloudScreen(),
      overrides: [
        nextcloudCredentialStoreProvider.overrideWithValue(store),
        nextcloudGatewayProvider.overrideWithValue(gateway),
        nextcloudFavouriteStoreProvider.overrideWithValue(favourites),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Aktionen für Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();

    expect(gateway.deletedPaths, isEmpty);
    expect(find.textContaining('alle enthaltenen Dateien'), findsOneWidget);

    await tester.tap(find.text('Dauerhaft löschen'));
    await tester.pumpAndSettle();

    expect(gateway.deletedPaths, <String>['/Archive']);
    expect(favourites.value, isEmpty);
  });
}

class _UploadPicker implements NextcloudUploadPicker {
  const _UploadPicker(this.file);

  final NextcloudUploadFile? file;

  @override
  Future<NextcloudUploadFile?> pickFile() async => file;
}

class _LinkSharer implements NextcloudPublicLinkSharer {
  final List<Uri> links = <Uri>[];

  @override
  Future<void> share(Uri link) async => links.add(link);
}
