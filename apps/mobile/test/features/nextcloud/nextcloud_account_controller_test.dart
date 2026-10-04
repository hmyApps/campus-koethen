// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/features/nextcloud/application/nextcloud_account_controller.dart';
import 'package:campus_koethen/features/nextcloud/application/nextcloud_providers.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_account.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_entry.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_failure.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_gateway.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const NextcloudCredential _credential = NextcloudCredential(
  server: 'https://cloud.hs-anhalt.de',
  loginName: 'student',
  userId: 'dav-user',
  appPassword: 'secret',
);

void main() {
  test(
    'browser login persists credential but exposes only public account',
    () async {
      final _MemoryStore store = _MemoryStore();
      final _Gateway gateway = _Gateway();
      final ProviderContainer container = _container(store, gateway);
      addTearDown(container.dispose);
      await container.read(nextcloudAccountControllerProvider.future);

      await container
          .read(nextcloudAccountControllerProvider.notifier)
          .connect();

      expect(store.value, _credential);
      expect(
        container.read(nextcloudAccountControllerProvider).value,
        _credential.toAccount(),
      );
      expect(gateway.launched, isTrue);
    },
  );

  test(
    'cancel prevents a late login result from recreating credentials',
    () async {
      final _MemoryStore store = _MemoryStore();
      final _Gateway gateway = _Gateway(blockLogin: true);
      final ProviderContainer container = _container(store, gateway);
      addTearDown(container.dispose);
      await container.read(nextcloudAccountControllerProvider.future);

      final Future<void> connection = container
          .read(nextcloudAccountControllerProvider.notifier)
          .connect();
      await gateway.completeLoginEntered.future;
      container
          .read(nextcloudAccountControllerProvider.notifier)
          .cancelPendingLogin();
      gateway.releaseLogin.complete();
      await connection;

      expect(gateway.revokeCalls, 1);
      expect(store.value, isNull);
      expect(container.read(nextcloudAccountControllerProvider).value, isNull);
    },
  );

  test(
    'failed secure persistence revokes the newly issued credential',
    () async {
      final _MemoryStore store = _MemoryStore(writeFails: true);
      final _Gateway gateway = _Gateway();
      final ProviderContainer container = _container(store, gateway);
      addTearDown(container.dispose);
      await container.read(nextcloudAccountControllerProvider.future);

      await container
          .read(nextcloudAccountControllerProvider.notifier)
          .connect();

      expect(gateway.revokeCalls, 1);
      expect(store.value, isNull);
      expect(
        container.read(nextcloudAccountControllerProvider).hasError,
        isTrue,
      );
    },
  );

  test(
    'disconnect clears local credential even when remote revoke fails',
    () async {
      final _MemoryStore store = _MemoryStore()..value = _credential;
      final _Gateway gateway = _Gateway(revokeFails: true);
      final ProviderContainer container = _container(store, gateway);
      addTearDown(container.dispose);
      await container.read(nextcloudAccountControllerProvider.future);

      await container
          .read(nextcloudAccountControllerProvider.notifier)
          .disconnect();

      expect(gateway.revokeCalls, 1);
      expect(store.value, isNull);
      expect(container.read(nextcloudAccountControllerProvider).value, isNull);
    },
  );

  test('a late file response is discarded after the session changes', () async {
    final _MemoryStore store = _MemoryStore()..value = _credential;
    final _Gateway gateway = _Gateway(blockDownload: true);
    final ProviderContainer container = _container(store, gateway);
    addTearDown(container.dispose);
    await container.read(nextcloudAccountControllerProvider.future);

    final Future<AppDocument> download = container
        .read(nextcloudFileServiceProvider)
        .download(
          const NextcloudEntry(
            path: '/notes.txt',
            name: 'notes.txt',
            isDirectory: false,
          ),
        );
    await gateway.downloadEntered.future;
    container.read(nextcloudSessionGenerationProvider.notifier).advance();
    gateway.releaseDownload.complete();

    await expectLater(
      download,
      throwsA(const NextcloudFailure(NextcloudFailureKind.notConnected)),
    );
  });
}

ProviderContainer _container(_MemoryStore store, _Gateway gateway) =>
    ProviderContainer(
      overrides: [
        nextcloudCredentialStoreProvider.overrideWithValue(store),
        nextcloudGatewayProvider.overrideWithValue(gateway),
        nextcloudLoginLauncherProvider.overrideWithValue(
          _Launcher(() => gateway.launched = true),
        ),
      ],
    );

class _MemoryStore implements NextcloudCredentialStore {
  _MemoryStore({this.writeFails = false});

  final bool writeFails;
  NextcloudCredential? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<NextcloudCredential?> read() async => value;

  @override
  Future<void> write(NextcloudCredential credential) async {
    if (writeFails) throw StateError('secure store unavailable');
    value = credential;
  }
}

class _Launcher implements NextcloudLoginLauncher {
  const _Launcher(this.onLaunch);
  final void Function() onLaunch;

  @override
  Future<bool> open(Uri uri) async {
    onLaunch();
    return true;
  }
}

class _Gateway implements NextcloudGateway {
  _Gateway({
    this.blockLogin = false,
    this.blockDownload = false,
    this.revokeFails = false,
  });

  final bool blockLogin;
  final bool blockDownload;
  final bool revokeFails;
  final Completer<void> completeLoginEntered = Completer<void>();
  final Completer<void> releaseLogin = Completer<void>();
  final Completer<void> downloadEntered = Completer<void>();
  final Completer<void> releaseDownload = Completer<void>();
  var launched = false;
  var revokeCalls = 0;

  @override
  Future<NextcloudLoginStart> startLogin() async => NextcloudLoginStart(
    loginUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/flow/test'),
    pollUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/poll'),
    pollToken: 'token',
  );

  @override
  Future<NextcloudCredential> completeLogin(
    NextcloudLoginStart start, {
    required Future<void> canceled,
  }) async {
    if (!completeLoginEntered.isCompleted) completeLoginEntered.complete();
    if (blockLogin) await releaseLogin.future;
    return _credential;
  }

  @override
  Future<void> revoke(NextcloudCredential credential) async {
    revokeCalls++;
    if (revokeFails) throw StateError('remote unavailable');
  }

  @override
  Future<List<NextcloudEntry>> listFolder(
    NextcloudCredential credential,
    String path,
  ) async => const <NextcloudEntry>[];

  @override
  Future<AppDocument> downloadFile(
    NextcloudCredential credential,
    NextcloudEntry entry,
  ) async {
    if (!downloadEntered.isCompleted) downloadEntered.complete();
    if (blockDownload) await releaseDownload.future;
    return AppDocument(
      filename: entry.name,
      mediaType: 'text/plain',
      bytes: Uint8List(0),
    );
  }
}
