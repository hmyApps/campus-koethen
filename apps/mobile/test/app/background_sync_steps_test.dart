// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/app/background_sync_steps.dart';
import 'package:campus_koethen/core/background/background_sync_settings.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_settings_controller.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_mail.dart';
import '../support/fake_notification_gateway.dart';

const MailCredentials _creds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'demo-password',
);

MailMessageHeader _header(String id, {String subject = 'Demo-Betreff'}) =>
    MailMessageHeader(
      id: id,
      subject: subject,
      from: const MailAddress(email: 'absender@example.test', name: 'Demo'),
      date: DateTime.utc(2026, 10, 16, 9, int.parse(id)),
      isSeen: false,
      hasAttachments: false,
    );

void main() {
  late FakeMailGateway mail;
  late InMemoryMailCredentialStore credentials;
  late MemoryMailCache cache;
  late FakeNotificationGateway notifications;
  late InMemoryKeyValueStore store;

  setUp(() {
    mail = FakeMailGateway();
    credentials = InMemoryMailCredentialStore()..write(_creds);
    cache = MemoryMailCache(now: () => DateTime.utc(2026, 10, 16));
    notifications = FakeNotificationGateway();
    store = InMemoryKeyValueStore();
  });

  Future<ProviderContainer> containerFor({bool optedIn = true}) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        mailGatewayProvider.overrideWithValue(mail),
        mailCredentialStoreProvider.overrideWithValue(credentials),
        mailCacheStoreProvider.overrideWithValue(cache),
        keyValueStoreProvider.overrideWithValue(store),
        notificationGatewayProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    if (optedIn) {
      await container
          .read(notificationSettingsProvider.notifier)
          .setOptedIn(true);
    }
    return container;
  }

  /// A mailbox the app has seen before: only message 1 is known.
  Future<void> knowMessageOne() =>
      cache.saveHeaders(<MailMessageHeader>[_header('1')]);

  group('mail', () {
    test('a headless run shows the new message with sender and subject, and '
        'prepares the notifications itself', () async {
      await knowMessageOne();
      mail.inbox = <MailMessageHeader>[_header('2'), _header('1')];
      final ProviderContainer container = await containerFor();

      await BackgroundSyncSteps(container, ownsNotifications: true).mail();

      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.title, 'Demo');
      expect(notifications.shown.single.body, 'Demo-Betreff');
      expect(notifications.shown.single.category, NotificationCategory.newMail);
      expect(notifications.channels, isNotEmpty);
    });

    test(
      'inside the running app it only fetches: the host announces',
      () async {
        await knowMessageOne();
        mail.inbox = <MailMessageHeader>[_header('2'), _header('1')];
        final ProviderContainer container = await containerFor();

        await BackgroundSyncSteps(container, ownsNotifications: false).mail();

        expect(notifications.shown, isEmpty);
        expect(
          (await cache.readHeaders()).map((MailMessageHeader h) => h.id),
          <String>['2', '1'],
        );
      },
    );

    test('nothing is announced without the opt-in', () async {
      await knowMessageOne();
      mail.inbox = <MailMessageHeader>[_header('2'), _header('1')];
      final ProviderContainer container = await containerFor(optedIn: false);

      await BackgroundSyncSteps(container, ownsNotifications: true).mail();

      expect(notifications.shown, isEmpty);
    });

    test('a mailbox seen for the first time is no news', () async {
      mail.inbox = <MailMessageHeader>[_header('2'), _header('1')];
      final ProviderContainer container = await containerFor();

      await BackgroundSyncSteps(container, ownsNotifications: true).mail();

      expect(notifications.shown, isEmpty);
    });

    test('signed out, it does not even connect', () async {
      credentials = InMemoryMailCredentialStore();
      mail.fetchHeadersStarted = Completer<void>();
      final ProviderContainer container = await containerFor();

      await BackgroundSyncSteps(container, ownsNotifications: true).mail();

      expect(mail.fetchHeadersStarted!.isCompleted, isFalse);
    });

    test('a refused password is remembered, and the next run does not log '
        'in again', () async {
      mail.fetchInboxError = const MailFailure(
        MailFailureKind.invalidCredentials,
      );
      final ProviderContainer container = await containerFor();
      await BackgroundSyncSteps(container, ownsNotifications: true).mail();
      expect(BackgroundMailGuard(store).blocked, isTrue);

      mail
        ..fetchInboxError = null
        ..fetchHeadersStarted = Completer<void>();
      final ProviderContainer next = await containerFor();
      await BackgroundSyncSteps(next, ownsNotifications: true).mail();

      expect(mail.fetchHeadersStarted!.isCompleted, isFalse);
    });
  });
}
