// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/application/mail_account_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_inbox_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/application/mail_sync_controller.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_mail.dart';

const MailCredentials _creds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

const MailFailure _rejected = MailFailure(MailFailureKind.invalidCredentials);

Future<({ProviderContainer container, FakeMailGateway gateway})>
_signedIn() async {
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
  return (container: container, gateway: gateway);
}

/// Every sync starts with one INBOX header fetch, i.e. one IMAP login.
int _logins(FakeMailGateway gateway) => gateway.fetchedMailboxes.length;

MailFailureKind? _syncErrorKind(ProviderContainer container) {
  final Object? error = container.read(mailSyncControllerProvider).error;
  return error is MailFailure ? error.kind : null;
}

void main() {
  group('periodic mail sync after a rejected password', () {
    test('automatic syncs stop logging in once the server rejected the '
        'password', () async {
      final (:container, :gateway) = await _signedIn();
      final MailSyncController sync = container.read(
        mailSyncControllerProvider.notifier,
      );
      gateway.fetchInboxError = _rejected;

      await sync.syncNow();
      expect(_logins(gateway), 1);
      expect(_syncErrorKind(container), MailFailureKind.invalidCredentials);

      // The 10-minute scheduler keeps calling; none of these may reach the
      // server, each one would count against the central university login.
      await sync.syncNow();
      await sync.syncNow();
      expect(_logins(gateway), 1);
      expect(_syncErrorKind(container), MailFailureKind.invalidCredentials);
    });

    test('a user-initiated refresh still tries, and its success lifts the '
        'lock for automatic syncs', () async {
      final (:container, :gateway) = await _signedIn();
      final MailSyncController sync = container.read(
        mailSyncControllerProvider.notifier,
      );
      gateway.fetchInboxError = _rejected;
      await sync.syncNow();
      expect(_logins(gateway), 1);

      gateway.fetchInboxError = null;
      await container.read(mailInboxControllerProvider.notifier).refresh();
      expect(_logins(gateway), 2);
      expect(container.read(mailSyncControllerProvider).error, isNull);

      await sync.syncNow();
      expect(_logins(gateway), 3);
    });

    test('a rejection seen by the live connection also stops the periodic '
        'sync', () async {
      final (:container, :gateway) = await _signedIn();
      await container.read(mailLiveSyncControllerProvider.notifier).start();
      await pumpEventQueue();
      final int before = _logins(gateway);

      gateway.liveSignals.addError(_rejected);
      await pumpEventQueue();
      expect(
        container.read(mailLiveSyncControllerProvider).connection,
        MailLiveConnection.authRequired,
      );

      await container.read(mailSyncControllerProvider.notifier).syncNow();
      expect(_logins(gateway), before);
      expect(_syncErrorKind(container), MailFailureKind.invalidCredentials);
    });

    test('signing in again clears the lock', () async {
      final (:container, :gateway) = await _signedIn();
      final MailSyncController sync = container.read(
        mailSyncControllerProvider.notifier,
      );
      gateway.fetchInboxError = _rejected;
      await sync.syncNow();
      expect(_logins(gateway), 1);

      gateway.fetchInboxError = null;
      await container
          .read(mailAccountControllerProvider.notifier)
          .signIn(email: 'stud@hs-anhalt.de', password: 'new-pw');
      final int afterSignIn = _logins(gateway);

      await container.read(mailSyncControllerProvider.notifier).syncNow();
      expect(_logins(gateway), afterSignIn + 1);
    });
  });
}
