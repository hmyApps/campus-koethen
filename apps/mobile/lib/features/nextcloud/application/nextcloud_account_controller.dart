// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../university_account/application/university_service_connector.dart';
import '../domain/nextcloud_account.dart';
import '../domain/nextcloud_failure.dart';
import '../domain/nextcloud_gateway.dart';
import 'nextcloud_providers.dart';

abstract interface class NextcloudLoginLauncher {
  Future<bool> open(Uri uri);
}

class ExternalNextcloudLoginLauncher implements NextcloudLoginLauncher {
  const ExternalNextcloudLoginLauncher();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

final Provider<NextcloudLoginLauncher> nextcloudLoginLauncherProvider =
    Provider<NextcloudLoginLauncher>(
      (Ref ref) => const ExternalNextcloudLoginLauncher(),
    );

class NextcloudAccountController extends AsyncNotifier<NextcloudAccount?> {
  Completer<void>? _loginCancellation;
  NextcloudAccount? _accountBeforeLogin;
  var _generation = 0;

  bool get loginPending => _loginCancellation != null;

  @override
  Future<NextcloudAccount?> build() async =>
      (await ref.read(nextcloudCredentialStoreProvider).read())?.toAccount();

  Future<void> connect() async {
    if (_loginCancellation != null) return;
    if (state.value != null) return;
    final int generation = ++_generation;
    final Completer<void> cancellation = Completer<void>();
    _loginCancellation = cancellation;
    _accountBeforeLogin = state.value;
    state = const AsyncLoading<NextcloudAccount?>();

    try {
      await ref.read(universityServiceOperationGateProvider).run<void>(
        () async {
          final NextcloudGateway gateway = ref.read(nextcloudGatewayProvider);
          final NextcloudLoginStart start = await gateway.startLogin();
          final bool opened;
          try {
            opened = await ref
                .read(nextcloudLoginLauncherProvider)
                .open(start.loginUri);
          } catch (_) {
            throw const NextcloudFailure(
              NextcloudFailureKind.browserLaunchFailed,
            );
          }
          if (!opened) {
            throw const NextcloudFailure(
              NextcloudFailureKind.browserLaunchFailed,
            );
          }
          final NextcloudCredential credential = await gateway.completeLogin(
            start,
            canceled: cancellation.future,
          );
          if (generation != _generation || cancellation.isCompleted) {
            await _discardIssuedCredential(credential);
            return;
          }
          try {
            await ref.read(nextcloudCredentialStoreProvider).write(credential);
          } catch (_) {
            await _discardIssuedCredential(credential, clearLocal: true);
            rethrow;
          }
          if (generation != _generation || cancellation.isCompleted) {
            await _discardIssuedCredential(credential, clearLocal: true);
            return;
          }
          ref.read(nextcloudSessionGenerationProvider.notifier).advance();
          state = AsyncData<NextcloudAccount?>(credential.toAccount());
        },
      );
    } on NextcloudFailure catch (error, stackTrace) {
      if (error.kind == NextcloudFailureKind.canceled ||
          generation != _generation) {
        state = AsyncData<NextcloudAccount?>(_accountBeforeLogin);
      } else {
        state = AsyncError<NextcloudAccount?>(error, stackTrace);
      }
    } catch (error, stackTrace) {
      if (generation == _generation) {
        state = AsyncError<NextcloudAccount?>(error, stackTrace);
      }
    } finally {
      if (identical(_loginCancellation, cancellation)) {
        _loginCancellation = null;
        _accountBeforeLogin = null;
      }
    }
  }

  void cancelPendingLogin() {
    final Completer<void>? cancellation = _loginCancellation;
    if (cancellation == null) return;
    _generation++;
    if (!cancellation.isCompleted) cancellation.complete();
    state = AsyncData<NextcloudAccount?>(_accountBeforeLogin);
  }

  Future<void> _discardIssuedCredential(
    NextcloudCredential credential, {
    bool clearLocal = false,
  }) async {
    if (clearLocal) {
      try {
        await ref.read(nextcloudCredentialStoreProvider).clear();
      } catch (_) {
        // Continue with server-side revocation even if the local secure
        // backend is already unavailable.
      }
    }
    try {
      await ref.read(nextcloudGatewayProvider).revoke(credential);
    } catch (_) {
      // Compensation is best effort. The credential was never exposed as a
      // connected account and local cleanup above remains authoritative.
    }
  }

  /// Revocation is best effort, but the local credential wipe is mandatory.
  Future<void> disconnect() async {
    cancelPendingLogin();
    final NextcloudCredentialStore store = ref.read(
      nextcloudCredentialStoreProvider,
    );
    NextcloudCredential? credential;
    try {
      credential = await store.read();
    } catch (_) {
      // Even if the secure backend cannot read a coherent credential, attempt
      // its canonical verified wipe below instead of leaving a secret behind.
    }
    if (credential != null) {
      try {
        await ref.read(nextcloudGatewayProvider).revoke(credential);
      } catch (_) {
        // A server outage must not keep a bearer credential on the device.
      }
    }
    await store.clear();
    ref.read(nextcloudSessionGenerationProvider.notifier).advance();
    state = const AsyncData<NextcloudAccount?>(null);
  }
}

final AsyncNotifierProvider<NextcloudAccountController, NextcloudAccount?>
nextcloudAccountControllerProvider =
    AsyncNotifierProvider<NextcloudAccountController, NextcloudAccount?>(
      NextcloudAccountController.new,
      retry: (_, _) => null,
    );
