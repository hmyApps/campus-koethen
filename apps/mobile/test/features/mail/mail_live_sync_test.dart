// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/mail/application/mail_account_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/application/mail_sync_controller.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_gateway.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_mail.dart';

const MailCredentials _creds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

/// A signed-in container whose live controller has made its first connect.
///
/// Everything runs inside [async] so the reconnect timers are virtual.
({ProviderContainer container, FakeMailGateway gateway}) _connected(
  FakeAsync async,
) {
  final InMemoryMailCredentialStore store = InMemoryMailCredentialStore()
    ..write(_creds);
  final FakeMailGateway gateway = FakeMailGateway();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      mailGatewayProvider.overrideWithValue(gateway),
      mailCredentialStoreProvider.overrideWithValue(store),
      mailCacheStoreProvider.overrideWithValue(MemoryMailCache()),
    ],
  );
  container.read(mailAccountControllerProvider);
  async.flushMicrotasks();
  unawaited(container.read(mailLiveSyncControllerProvider.notifier).start());
  async.flushMicrotasks();
  return (container: container, gateway: gateway);
}

MailLiveSyncStatus _live(ProviderContainer container) =>
    container.read(mailLiveSyncControllerProvider);

void main() {
  group('mailLiveRetryDelay', () {
    test('doubles from 15 seconds and is capped at 30 minutes', () {
      expect(mailLiveRetryDelay(0), const Duration(seconds: 15));
      expect(mailLiveRetryDelay(1), const Duration(seconds: 30));
      expect(mailLiveRetryDelay(2), const Duration(minutes: 1));
      expect(mailLiveRetryDelay(6), const Duration(minutes: 16));
      expect(mailLiveRetryDelay(7), const Duration(minutes: 30));
      expect(mailLiveRetryDelay(500), const Duration(minutes: 30));
    });
  });

  group('MailLiveSyncController reconnects', () {
    test('a rejected password stops the live connection for the session '
        'instead of logging in again every 15 seconds', () {
      fakeAsync((FakeAsync async) {
        final (:container, :gateway) = _connected(async);
        expect(gateway.watchInboxCalls, 1);

        gateway.liveSignals.addError(
          const MailFailure(MailFailureKind.invalidCredentials),
        );
        async.flushMicrotasks();

        expect(_live(container).connection, MailLiveConnection.authRequired);
        expect(
          (_live(container).error! as MailFailure).kind,
          MailFailureKind.invalidCredentials,
        );
        async.elapse(const Duration(hours: 3));
        expect(gateway.watchInboxCalls, 1, reason: 'no automatic re-login');

        // Pausing and resuming the app must not retry the rejected password.
        final MailLiveSyncController live = container.read(
          mailLiveSyncControllerProvider.notifier,
        );
        unawaited(live.stop());
        unawaited(live.start());
        async.elapse(const Duration(minutes: 5));
        expect(gateway.watchInboxCalls, 1);
        expect(_live(container).connection, MailLiveConnection.authRequired);
        container.dispose();
      });
    });

    test('a TLS failure is not retried automatically', () {
      fakeAsync((FakeAsync async) {
        final (:container, :gateway) = _connected(async);

        gateway.liveSignals.addError(const MailFailure(MailFailureKind.tls));
        async.flushMicrotasks();

        expect(_live(container).connection, MailLiveConnection.authRequired);
        async.elapse(const Duration(hours: 3));
        expect(gateway.watchInboxCalls, 1);
        container.dispose();
      });
    });

    test('transient failures back off exponentially', () {
      fakeAsync((FakeAsync async) {
        final (:container, :gateway) = _connected(async);
        const MailFailure unreachable = MailFailure(
          MailFailureKind.serverUnreachable,
        );

        gateway.liveSignals.addError(unreachable);
        async.flushMicrotasks();
        expect(_live(container).connection, MailLiveConnection.retrying);
        async.elapse(const Duration(seconds: 14));
        expect(gateway.watchInboxCalls, 1);
        async.elapse(const Duration(seconds: 1));
        expect(gateway.watchInboxCalls, 2);

        gateway.liveSignals.addError(unreachable);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 29));
        expect(gateway.watchInboxCalls, 2, reason: 'second delay is 30 s');
        async.elapse(const Duration(seconds: 1));
        expect(gateway.watchInboxCalls, 3);

        gateway.liveSignals.addError(unreachable);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 59));
        expect(gateway.watchInboxCalls, 3, reason: 'third delay is 60 s');
        async.elapse(const Duration(seconds: 1));
        expect(gateway.watchInboxCalls, 4);
        container.dispose();
      });
    });

    test('a connection that stays up resets the backoff', () {
      fakeAsync((FakeAsync async) {
        final (:container, :gateway) = _connected(async);
        const MailFailure unreachable = MailFailure(
          MailFailureKind.serverUnreachable,
        );
        gateway.liveSignals.addError(unreachable);
        async.elapse(const Duration(seconds: 15));
        gateway.liveSignals.addError(unreachable);
        async.elapse(const Duration(seconds: 30));
        expect(gateway.watchInboxCalls, 3);

        gateway.liveSignals.add(MailLiveSignal.connected);
        async.elapse(kMailLiveStableAfter);
        gateway.liveSignals.addError(unreachable);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 15));
        expect(gateway.watchInboxCalls, 4);
        container.dispose();
      });
    });

    test('a connection that drops right after login keeps backing off', () {
      fakeAsync((FakeAsync async) {
        final (:container, :gateway) = _connected(async);
        const MailFailure unreachable = MailFailure(
          MailFailureKind.serverUnreachable,
        );
        gateway.liveSignals.addError(unreachable);
        async.elapse(const Duration(seconds: 15));
        expect(gateway.watchInboxCalls, 2);

        gateway.liveSignals.add(MailLiveSignal.connected);
        async.flushMicrotasks();
        gateway.liveSignals.addError(unreachable);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 29));
        expect(gateway.watchInboxCalls, 2);
        async.elapse(const Duration(seconds: 1));
        expect(gateway.watchInboxCalls, 3);
        container.dispose();
      });
    });
  });

  group('MailLiveSyncController after a new sign-in', () {
    Future<({ProviderContainer container, FakeMailGateway gateway})>
    liveConnected() async {
      final InMemoryMailCredentialStore store = InMemoryMailCredentialStore()
        ..write(_creds);
      final FakeMailGateway gateway = FakeMailGateway();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          mailGatewayProvider.overrideWithValue(gateway),
          mailCredentialStoreProvider.overrideWithValue(store),
          mailCacheStoreProvider.overrideWithValue(MemoryMailCache()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mailAccountControllerProvider.future);
      await container.read(mailLiveSyncControllerProvider.notifier).start();
      gateway.liveSignals.add(MailLiveSignal.connected);
      await pumpEventQueue();
      expect(gateway.watchInboxCalls, 1);
      return (container: container, gateway: gateway);
    }

    Future<void> signInAgain(ProviderContainer container) async {
      await container
          .read(mailAccountControllerProvider.notifier)
          .signIn(email: _creds.emailAddress, password: 'new-pw');
      await pumpEventQueue();
    }

    test('reconnects the live connection with the new session', () async {
      final (:container, :gateway) = await liveConnected();

      await signInAgain(container);

      expect(gateway.watchInboxCalls, 2);
      expect(
        _live(container).connection,
        isNot(MailLiveConnection.stopped),
        reason: 'IDLE must not wait for the next app resume',
      );
    });

    test('a new sign-in lifts a rejected-password stop', () async {
      final (:container, :gateway) = await liveConnected();
      gateway.liveSignals.addError(
        const MailFailure(MailFailureKind.invalidCredentials),
      );
      await pumpEventQueue();
      expect(_live(container).connection, MailLiveConnection.authRequired);

      await signInAgain(container);

      expect(gateway.watchInboxCalls, 2);
      expect(_live(container).connection, MailLiveConnection.connecting);
    });

    test('does not connect while the app is in the background', () async {
      final (:container, :gateway) = await liveConnected();
      await container.read(mailLiveSyncControllerProvider.notifier).stop();

      await signInAgain(container);

      expect(gateway.watchInboxCalls, 1);
      expect(_live(container).connection, MailLiveConnection.stopped);
    });
  });
}
