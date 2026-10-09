// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:campus_koethen/features/mail/application/mail_account_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_compose_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_folders.dart';
import 'package:campus_koethen/features/mail/application/mail_inbox_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/application/mail_search_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_sync_controller.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_folder.dart';
import 'package:campus_koethen/features/mail/domain/mail_gateway.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_mail.dart';

const MailCredentials _creds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

ProviderContainer _container({
  required FakeMailGateway gateway,
  required InMemoryMailCredentialStore store,
  MemoryMailCache? cache,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      mailGatewayProvider.overrideWithValue(gateway),
      mailCredentialStoreProvider.overrideWithValue(store),
      if (cache != null) mailCacheStoreProvider.overrideWithValue(cache),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

MailMessageHeader _hdr(String id) => MailMessageHeader(
  id: id,
  subject: 'Subject $id',
  from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
  date: DateTime.utc(2026, 7, 20, 9, int.parse(id)),
  isSeen: false,
  hasAttachments: false,
);

MailMessageDetail _dtl(String id, {DateTime? date}) => MailMessageDetail(
  id: id,
  subject: 'Subject $id',
  from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
  to: const <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
  date: date ?? DateTime.utc(2026, 7, 20, 9, int.parse(id)),
  body: 'Body $id',
);

/// A header dated [date] instead of the recent default of [_hdr].
MailMessageHeader _hdrAt(String id, DateTime date) => MailMessageHeader(
  id: id,
  subject: 'Subject $id',
  from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
  date: date,
  isSeen: false,
  hasAttachments: false,
);

void main() {
  group('account load', () {
    test('starts signed out when the store is empty', () async {
      final container = _container(
        gateway: FakeMailGateway(),
        store: InMemoryMailCredentialStore(),
      );
      final MailAccountState state = await container.read(
        mailAccountControllerProvider.future,
      );
      expect(state.emailAddress, isNull);
      expect(state.isSignedIn, isFalse);
    });

    test(
      'restores a stored account on start (address only, no password in state)',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final container = _container(gateway: FakeMailGateway(), store: store);

        final MailAccountState state = await container.read(
          mailAccountControllerProvider.future,
        );
        expect(state.isSignedIn, isTrue);
        expect(state.emailAddress, 'stud@hs-anhalt.de');
        // The exposed state must never carry the password.
        expect(state.toString().contains('pw'), isFalse);
      },
    );
  });

  group('sign in', () {
    test('verifies IMAP+SMTP then stores credentials on success', () async {
      final gateway = FakeMailGateway();
      final store = InMemoryMailCredentialStore();
      final container = _container(gateway: gateway, store: store);
      final controller = container.read(mailAccountControllerProvider.notifier);

      await container.read(mailAccountControllerProvider.future);
      await controller.signIn(email: '  stud@hs-anhalt.de ', password: 'pw');

      expect(gateway.verifyCalls, 1);
      expect(store.writes, 1, reason: 'credentials stored only after verify');
      final state = container.read(mailAccountControllerProvider).requireValue;
      expect(state.isSignedIn, isTrue);
      expect(state.emailAddress, 'stud@hs-anhalt.de');
    });

    test(
      'stores an optional display name and exposes it in the state',
      () async {
        final gateway = FakeMailGateway();
        final store = InMemoryMailCredentialStore();
        final container = _container(gateway: gateway, store: store);
        final controller = container.read(
          mailAccountControllerProvider.notifier,
        );
        await container.read(mailAccountControllerProvider.future);

        await controller.signIn(
          email: 'stud@hs-anhalt.de',
          password: 'pw',
          displayName: '  Max Mustermensch  ',
        );

        final state = container
            .read(mailAccountControllerProvider)
            .requireValue;
        expect(state.displayName, 'Max Mustermensch', reason: 'trimmed');
        expect(await store.read(), isNotNull);
        expect((await store.read())!.displayName, 'Max Mustermensch');
        // The address stays the sole identity; the name is only cosmetic.
        expect(state.emailAddress, 'stud@hs-anhalt.de');
      },
    );

    test(
      'switching accounts invalidates memory and wipes the old cache',
      () async {
        final gateway = FakeMailGateway();
        final store = InMemoryMailCredentialStore()..write(_creds);
        final cache = MemoryMailCache();
        await cache.saveHeaders(<MailMessageHeader>[_hdr('1')]);
        final container = _container(
          gateway: gateway,
          store: store,
          cache: cache,
        );
        final controller = container.read(
          mailAccountControllerProvider.notifier,
        );
        await container.read(mailAccountControllerProvider.future);
        final int generationBefore = controller.sessionGeneration;

        await controller.signIn(
          email: 'other@hs-anhalt.de',
          password: 'new-pw',
        );

        expect(controller.sessionGeneration, greaterThan(generationBefore));
        expect(await cache.readHeaders(), isEmpty);
        expect(store.lastWritten?.emailAddress, 'other@hs-anhalt.de');
        expect(
          container
              .read(mailAccountControllerProvider)
              .requireValue
              .emailAddress,
          'other@hs-anhalt.de',
        );
      },
    );

    test(
      'a failed account-switch wipe never leaves the old mailbox shown as connected',
      () async {
        final store = InMemoryMailCredentialStore(clearAvailable: false)
          ..write(_creds);
        final container = _container(
          gateway: FakeMailGateway(),
          store: store,
          cache: MemoryMailCache(),
        );
        final controller = container.read(
          mailAccountControllerProvider.notifier,
        );
        await container.read(mailAccountControllerProvider.future);

        await expectLater(
          controller.signIn(email: 'other@hs-anhalt.de', password: 'new-pw'),
          throwsA(isA<MailFailure>()),
        );

        expect(container.read(mailAccountControllerProvider).hasError, isTrue);
      },
    );

    test('rejects an invalid email without ever calling the server', () async {
      final gateway = FakeMailGateway();
      final store = InMemoryMailCredentialStore();
      final container = _container(gateway: gateway, store: store);
      final controller = container.read(mailAccountControllerProvider.notifier);
      await container.read(mailAccountControllerProvider.future);

      await expectLater(
        controller.signIn(email: 'not-an-email', password: 'pw'),
        throwsA(
          isA<MailFailure>().having(
            (e) => e.kind,
            'kind',
            MailFailureKind.invalidEmail,
          ),
        ),
      );
      expect(gateway.verifyCalls, 0);
      expect(store.writes, 0);
    });

    test('does NOT store credentials when verification fails', () async {
      final gateway = FakeMailGateway(
        verifyError: const MailFailure(MailFailureKind.invalidCredentials),
      );
      final store = InMemoryMailCredentialStore();
      final container = _container(gateway: gateway, store: store);
      final controller = container.read(mailAccountControllerProvider.notifier);
      await container.read(mailAccountControllerProvider.future);

      await expectLater(
        controller.signIn(email: 'stud@hs-anhalt.de', password: 'wrong'),
        throwsA(isA<MailFailure>()),
      );
      expect(store.writes, 0);
      expect(
        container.read(mailAccountControllerProvider).requireValue.isSignedIn,
        isFalse,
      );
    });

    test('surfaces a secure-storage failure and stays signed out', () async {
      final gateway = FakeMailGateway();
      final store = InMemoryMailCredentialStore(available: false);
      final container = _container(gateway: gateway, store: store);
      final controller = container.read(mailAccountControllerProvider.notifier);
      await container.read(mailAccountControllerProvider.future);

      await expectLater(
        controller.signIn(email: 'stud@hs-anhalt.de', password: 'pw'),
        throwsA(
          isA<MailFailure>().having(
            (e) => e.kind,
            'kind',
            MailFailureKind.secureStorageUnavailable,
          ),
        ),
      );
      expect(
        container.read(mailAccountControllerProvider).requireValue.isSignedIn,
        isFalse,
      );
    });

    for (final MailFailureKind kind in <MailFailureKind>[
      MailFailureKind.timeout,
      MailFailureKind.serverUnreachable,
      MailFailureKind.tls,
      MailFailureKind.invalidCredentials,
    ]) {
      test(
        'surfaces a distinct ${kind.name} failure without storing',
        () async {
          final gateway = FakeMailGateway(verifyError: MailFailure(kind));
          final store = InMemoryMailCredentialStore();
          final container = _container(gateway: gateway, store: store);
          final controller = container.read(
            mailAccountControllerProvider.notifier,
          );
          await container.read(mailAccountControllerProvider.future);

          await expectLater(
            controller.signIn(email: 'stud@hs-anhalt.de', password: 'pw'),
            throwsA(isA<MailFailure>().having((e) => e.kind, 'kind', kind)),
          );
          expect(store.writes, 0);
          expect(
            container
                .read(mailAccountControllerProvider)
                .requireValue
                .isSignedIn,
            isFalse,
          );
        },
      );
    }

    test(
      'a hung verification never resolves until the connection settles',
      () async {
        final gateway = FakeMailGateway(
          verifyGate: Completer<void>(),
          verifyStarted: Completer<void>(),
        );
        final store = InMemoryMailCredentialStore();
        final container = _container(gateway: gateway, store: store);
        final controller = container.read(
          mailAccountControllerProvider.notifier,
        );
        await container.read(mailAccountControllerProvider.future);

        bool finished = false;
        final Future<void> signIn = controller
            .signIn(email: 'stud@hs-anhalt.de', password: 'pw')
            .whenComplete(() => finished = true);

        await gateway.verifyStarted!.future;
        expect(finished, isFalse, reason: 'still hanging on the server');
        expect(store.writes, 0);

        gateway.verifyGate!.complete();
        await signIn;
        expect(finished, isTrue);
        expect(store.writes, 1);
      },
    );

    test('a retry after a failed attempt can still succeed', () async {
      final gateway = FakeMailGateway(
        verifyError: const MailFailure(MailFailureKind.timeout),
      );
      final store = InMemoryMailCredentialStore();
      final container = _container(gateway: gateway, store: store);
      final controller = container.read(mailAccountControllerProvider.notifier);
      await container.read(mailAccountControllerProvider.future);

      await expectLater(
        controller.signIn(email: 'stud@hs-anhalt.de', password: 'pw'),
        throwsA(isA<MailFailure>()),
      );
      expect(store.writes, 0);

      gateway.verifyError = null;
      await controller.signIn(email: 'stud@hs-anhalt.de', password: 'pw');

      expect(store.writes, 1);
      expect(
        container.read(mailAccountControllerProvider).requireValue.isSignedIn,
        isTrue,
      );
    });
  });

  group('sign out', () {
    test('clears credentials completely', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final container = _container(gateway: FakeMailGateway(), store: store);
      final controller = container.read(mailAccountControllerProvider.notifier);
      await container.read(mailAccountControllerProvider.future);

      await controller.signOut();

      expect(store.clears, greaterThanOrEqualTo(1));
      expect(await store.read(), isNull);
      expect(
        container.read(mailAccountControllerProvider).requireValue.isSignedIn,
        isFalse,
      );
    });

    test(
      'keeps the session fenced and allows retry after a partial wipe',
      () async {
        final store = InMemoryMailCredentialStore(clearAvailable: false)
          ..write(_creds);
        final cache = MemoryMailCache();
        await cache.saveHeaders(<MailMessageHeader>[_hdr('1')]);
        final container = _container(
          gateway: FakeMailGateway(),
          store: store,
          cache: cache,
        );
        final controller = container.read(
          mailAccountControllerProvider.notifier,
        );
        await container.read(mailAccountControllerProvider.future);

        await expectLater(
          controller.signOut(),
          throwsA(
            isA<MailFailure>().having(
              (failure) => failure.kind,
              'kind',
              MailFailureKind.localDataWipeIncomplete,
            ),
          ),
        );
        expect(
          container.read(mailAccountControllerProvider).requireValue.isSignedIn,
          isTrue,
        );
        expect(await cache.readHeaders(), isEmpty);
        await expectLater(
          controller.requireCredentials(),
          throwsA(isA<MailFailure>()),
        );

        store.clearAvailable = true;
        await controller.signOut();
        expect(
          container.read(mailAccountControllerProvider).requireValue.isSignedIn,
          isFalse,
        );
      },
    );
  });

  group('inbox', () {
    test('serves the INBOX from the offline cache', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('7')]);
      final container = _container(
        gateway: FakeMailGateway(),
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);

      final result = await container.read(mailInboxControllerProvider.future);
      expect(result, hasLength(1));
      expect(result.first.id, '7');
    });

    test('deletes on the server before removing the offline copy', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('7'), _hdr('8')]);
      await cache.saveMessages(<MailMessageDetail>[_dtl('7'), _dtl('8')]);
      final gateway = FakeMailGateway();
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      await container.read(mailInboxControllerProvider.future);

      await container.read(mailInboxControllerProvider.notifier).deleteMessage((
        mailboxPath: kInboxPath,
        id: '7',
      ));

      expect(gateway.deletedMessages, <({String mailboxPath, String id})>[
        (mailboxPath: kInboxPath, id: '7'),
      ]);
      expect(
        (await cache.readHeaders()).map((MailMessageHeader h) => h.id),
        <String>['8'],
      );
      expect(await cache.readMessage('7'), isNull);
      expect(await cache.readMessage('8'), isNotNull);
    });

    test('loads older inbox headers in stable 100-message pages', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('300'), _hdr('200')]);
      final Completer<void> olderGate = Completer<void>();
      final Completer<void> olderStarted = Completer<void>();
      final gateway = FakeMailGateway(
        olderInbox: List<MailMessageHeader>.generate(
          100,
          (int index) => _hdr('${199 - index}'),
        ),
        fetchOlderHeadersGate: olderGate,
        fetchOlderHeadersStarted: olderStarted,
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      await container.read(mailInboxControllerProvider.future);

      final Future<void> firstPage = container
          .read(mailInboxControllerProvider.notifier)
          .loadOlder();
      await olderStarted.future;
      expect(container.read(mailPaginationProvider).isLoading, isTrue);
      olderGate.complete();
      await firstPage;

      expect(gateway.lastFetchHeadersBeforeId, '200');
      expect(gateway.lastFetchHeadersLimit, 100);
      expect(await cache.readHeaders(), hasLength(102));
      expect(container.read(mailPaginationProvider).hasMore, isTrue);

      gateway
        ..olderInbox = List<MailMessageHeader>.generate(
          50,
          (int index) => _hdr('${99 - index}'),
        )
        ..fetchOlderHeadersGate = null
        ..fetchOlderHeadersStarted = null;
      await container.read(mailInboxControllerProvider.notifier).loadOlder();

      expect(gateway.lastFetchHeadersBeforeId, '100');
      expect(await cache.readHeaders(), hasLength(152));
      expect(container.read(mailPaginationProvider).hasMore, isFalse);
    });

    test(
      'opening a cached message marks it seen locally and rebuilds the list',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final cache = MemoryMailCache();
        await cache.saveHeaders(<MailMessageHeader>[_hdr('7')]);
        await cache.saveMessage(_dtl('7'));
        final gateway = FakeMailGateway();
        final container = _container(
          gateway: gateway,
          store: store,
          cache: cache,
        );
        await container.read(mailAccountControllerProvider.future);

        final List<MailMessageHeader> before = await container.read(
          mailInboxControllerProvider.future,
        );
        expect(before.single.isSeen, isFalse);

        await container.read(
          mailMessageProvider((mailboxPath: kInboxPath, id: '7')).future,
        );

        final List<MailMessageHeader> after = await container.read(
          mailInboxControllerProvider.future,
        );
        expect(after.single.isSeen, isTrue);
        expect(gateway.markedSeen, <String>['7']);
      },
    );

    test(
      'opening a message fetched from the network marks it seen locally',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final cache = MemoryMailCache();
        await cache.saveHeaders(<MailMessageHeader>[_hdr('9')]);
        final gateway = FakeMailGateway(
          detailsById: <String, MailMessageDetail>{'9': _dtl('9')},
        );
        final container = _container(
          gateway: gateway,
          store: store,
          cache: cache,
        );
        await container.read(mailAccountControllerProvider.future);

        await container.read(
          mailMessageProvider((mailboxPath: kInboxPath, id: '9')).future,
        );

        final List<MailMessageHeader> after = await container.read(
          mailInboxControllerProvider.future,
        );
        expect(after.single.isSeen, isTrue);
      },
    );

    test(
      'a failed server \\Seen mark still leaves the message readable and seen locally',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final cache = MemoryMailCache();
        await cache.saveHeaders(<MailMessageHeader>[_hdr('3')]);
        await cache.saveMessage(_dtl('3'));
        final gateway = FakeMailGateway(
          markSeenError: const MailFailure(MailFailureKind.network),
        );
        final container = _container(
          gateway: gateway,
          store: store,
          cache: cache,
        );
        await container.read(mailAccountControllerProvider.future);

        final MailMessageDetail detail = await container.read(
          mailMessageProvider((mailboxPath: kInboxPath, id: '3')).future,
        );
        expect(detail.id, '3');

        // Let the best-effort, unawaited server call settle.
        await Future<void>.delayed(Duration.zero);

        final List<MailMessageHeader> after = await container.read(
          mailInboxControllerProvider.future,
        );
        expect(after.single.isSeen, isTrue);
        expect(gateway.markedSeen, isEmpty);
      },
    );

    test('a non-INBOX message open never touches the INBOX cache', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('1')]);
      final gateway = FakeMailGateway(
        detailsById: <String, MailMessageDetail>{'1': _dtl('1')},
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);

      await container.read(
        mailMessageProvider((mailboxPath: 'Archiv', id: '1')).future,
      );

      expect((await cache.readHeaders()).single.isSeen, isFalse);
    });

    test(
      'a non-inbox folder fetch maps a timeout to a typed failure',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final gateway = FakeMailGateway(
          fetchInboxError: const MailFailure(MailFailureKind.timeout),
        );
        final container = _container(gateway: gateway, store: store);
        await container.read(mailAccountControllerProvider.future);
        // A non-INBOX folder is fetched online, so it can fail with a timeout.
        container
            .read(selectedMailboxProvider.notifier)
            .select(const MailFolder(path: 'Archiv', name: 'Archiv'));

        final Completer<AsyncValue<List<MailMessageHeader>>> settled =
            Completer<AsyncValue<List<MailMessageHeader>>>();
        container.listen<AsyncValue<List<MailMessageHeader>>>(
          mailInboxControllerProvider,
          (_, AsyncValue<List<MailMessageHeader>> next) {
            if (!next.isLoading && !settled.isCompleted) settled.complete(next);
          },
          fireImmediately: true,
        );

        final AsyncValue<List<MailMessageHeader>> result = await settled.future;
        expect(result.hasError, isTrue);
        expect(
          result.error,
          isA<MailFailure>().having(
            (e) => e.kind,
            'kind',
            MailFailureKind.timeout,
          ),
        );
      },
    );
  });

  group('sync', () {
    test('an in-flight sync cannot repopulate cache after sign-out', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      final Completer<void> started = Completer<void>();
      final Completer<void> release = Completer<void>();
      final gateway = FakeMailGateway(
        inbox: <MailMessageHeader>[_hdr('1')],
        detailsById: <String, MailMessageDetail>{'1': _dtl('1')},
        fetchHeadersStarted: started,
        fetchHeadersGate: release,
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);

      final Future<void> sync = container
          .read(mailSyncControllerProvider.notifier)
          .syncNow();
      await started.future;
      await container.read(mailAccountControllerProvider.notifier).signOut();
      release.complete();
      await sync;

      expect(await cache.readHeaders(), isEmpty);
      expect(await cache.cachedMessageIds(), isEmpty);
    });

    test(
      'caches headers and prefetches new bodies, accumulating over time',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final cache = MemoryMailCache();
        final gateway = FakeMailGateway(
          inbox: <MailMessageHeader>[_hdr('1')],
          detailsById: <String, MailMessageDetail>{'1': _dtl('1')},
        );
        final container = _container(
          gateway: gateway,
          store: store,
          cache: cache,
        );
        await container.read(mailAccountControllerProvider.future);

        await container.read(mailSyncControllerProvider.notifier).syncNow();
        expect(
          (await cache.readHeaders()).map((MailMessageHeader h) => h.id),
          <String>['1'],
        );
        expect(await cache.cachedMessageIds(), <String>{'1'});

        // The server now shows a newer message and message 1 has scrolled off
        // the fetched window of a mailbox larger than that window.
        gateway
          ..inbox = <MailMessageHeader>[_hdr('2')]
          ..messagesExists = 120;
        gateway.detailsById = <String, MailMessageDetail>{'2': _dtl('2')};
        await container.read(mailSyncControllerProvider.notifier).syncNow();

        // Accumulated: the previously cached message stays, the new one is added.
        expect(
          (await cache.readHeaders())
              .map((MailMessageHeader h) => h.id)
              .toSet(),
          <String>{'1', '2'},
        );
        expect(await cache.cachedMessageIds(), <String>{'1', '2'});
      },
    );

    test('removes mails deleted elsewhere when the window is the whole mailbox '
        '(C-06)', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      final gateway = FakeMailGateway(
        inbox: <MailMessageHeader>[_hdr('3'), _hdr('2'), _hdr('1')],
        detailsById: <String, MailMessageDetail>{
          '3': _dtl('3'),
          '2': _dtl('2'),
          '1': _dtl('1'),
        },
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      await container.read(mailSyncControllerProvider.notifier).syncNow();
      expect(await cache.cachedMessageIds(), <String>{'1', '2', '3'});

      // Deleted in webmail: the mailbox now holds two of fewer than 50 mails.
      gateway
        ..inbox = <MailMessageHeader>[_hdr('3'), _hdr('1')]
        ..messagesExists = 2;
      await container.read(mailSyncControllerProvider.notifier).syncNow();

      expect(
        (await cache.readHeaders()).map((MailMessageHeader h) => h.id),
        <String>['3', '1'],
      );
      expect(await cache.cachedMessageIds(), <String>{'1', '3'});
    });

    test('an unchanged inbox with year-old mails is never reported as new '
        '(C-04)', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache(now: () => DateTime.utc(2026, 8, 1));
      final DateTime yearsAgo = DateTime.utc(2024, 1, 1);
      final gateway = FakeMailGateway(
        inbox: <MailMessageHeader>[
          _hdr('3'),
          _hdrAt('2', yearsAgo),
          _hdrAt('1', yearsAgo),
        ],
        detailsById: <String, MailMessageDetail>{'3': _dtl('3')},
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      final List<MailNewMessageEvent> events = <MailNewMessageEvent>[];
      container.listen<MailNewMessageEvent?>(mailNewMessageEventProvider, (
        _,
        MailNewMessageEvent? next,
      ) {
        if (next != null) events.add(next);
      });

      await container.read(mailSyncControllerProvider.notifier).syncNow();
      await container.read(mailSyncControllerProvider.notifier).syncNow();
      await container.read(mailSyncControllerProvider.notifier).syncNow();

      expect(events, isEmpty);
      expect(
        (await cache.readHeaders()).map((MailMessageHeader h) => h.id),
        <String>['3', '2', '1'],
        reason: 'the current server window is shown whatever its age',
      );
    });

    test('an empty mailbox page never erases the cached inbox', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('2'), _hdr('1')]);
      final gateway = FakeMailGateway(messagesExists: 0);
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);

      await container.read(mailSyncControllerProvider.notifier).syncNow();

      expect(await cache.readHeaders(), hasLength(2));
    });

    test(
      'publishes only messages arriving after the initial baseline',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final cache = MemoryMailCache();
        final gateway = FakeMailGateway(
          inbox: <MailMessageHeader>[_hdr('1')],
          detailsById: <String, MailMessageDetail>{'1': _dtl('1')},
        );
        final container = _container(
          gateway: gateway,
          store: store,
          cache: cache,
        );
        await container.read(mailAccountControllerProvider.future);
        final List<MailNewMessageEvent> events = <MailNewMessageEvent>[];
        container.listen<MailNewMessageEvent?>(mailNewMessageEventProvider, (
          _,
          MailNewMessageEvent? next,
        ) {
          if (next != null) events.add(next);
        });

        await container.read(mailSyncControllerProvider.notifier).syncNow();
        expect(
          events,
          isEmpty,
          reason: 'existing mailbox establishes baseline',
        );

        gateway.inbox = <MailMessageHeader>[_hdr('2'), _hdr('1')];
        gateway.detailsById = <String, MailMessageDetail>{'2': _dtl('2')};
        await container.read(mailSyncControllerProvider.notifier).syncNow();

        expect(events, hasLength(1));
        expect(events.single.newestMessageId, '2');
        expect(events.single.count, 1);
      },
    );

    test('a live IMAP change immediately triggers an inbox sync', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('1')]);
      final gateway = FakeMailGateway(
        inbox: <MailMessageHeader>[_hdr('2'), _hdr('1')],
        detailsById: <String, MailMessageDetail>{'2': _dtl('2')},
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);

      await container.read(mailLiveSyncControllerProvider.notifier).start();
      gateway.liveSignals.add(MailLiveSignal.connected);
      gateway.liveSignals.add(MailLiveSignal.changed);
      for (int attempt = 0; attempt < 30; attempt++) {
        if ((await cache.readHeaders()).any((header) => header.id == '2')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(gateway.watchInboxCalls, 1);
      expect((await cache.readHeaders()).map((header) => header.id), <String>[
        '2',
        '1',
      ]);
      expect(
        container.read(mailLiveSyncControllerProvider).connection,
        MailLiveConnection.idle,
      );
    });

    test('downloads attachment bytes only when the setting is on', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      final gateway = FakeMailGateway(
        inbox: <MailMessageHeader>[_hdr('1')],
        detailsById: <String, MailMessageDetail>{'1': _dtl('1')},
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);

      await container.read(mailSyncControllerProvider.notifier).syncNow();
      expect(gateway.lastIncludeAttachmentBytes, isFalse);

      await container
          .read(settingsProvider.notifier)
          .setMailDownloadAttachments(true);
      // Force a fresh prefetch by using a message not yet cached.
      gateway.inbox = <MailMessageHeader>[_hdr('2')];
      gateway.detailsById = <String, MailMessageDetail>{'2': _dtl('2')};
      await container.read(mailSyncControllerProvider.notifier).syncNow();
      expect(gateway.lastIncludeAttachmentBytes, isTrue);
    });

    test('prefetches only the newest bounded set of message bodies', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final cache = MemoryMailCache();
      final List<MailMessageHeader> headers = <MailMessageHeader>[
        for (int id = 30; id >= 1; id--) _hdr('$id'),
      ];
      final FakeMailGateway gateway = FakeMailGateway(
        inbox: headers,
        detailsById: <String, MailMessageDetail>{
          for (int id = 1; id <= 30; id++) '$id': _dtl('$id'),
        },
      );
      final ProviderContainer container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);

      await container.read(mailSyncControllerProvider.notifier).syncNow();

      expect(gateway.lastFetchMessageIds, hasLength(kMailBodyPrefetchLimit));
      expect(gateway.lastFetchMessageIds.first, '30');
      expect(gateway.lastFetchMessageIds.last, '11');
      expect(await cache.cachedMessageIds(), hasLength(kMailBodyPrefetchLimit));
    });

    test(
      'never prefetches bodies the age retention would delete again (C-05)',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        // Bodies older than 180 days are pruned right after saving.
        final cache = MemoryMailCache(now: () => DateTime.utc(2026, 8, 1));
        final DateTime old = DateTime.utc(2025, 1, 1);
        final gateway = FakeMailGateway(
          inbox: <MailMessageHeader>[
            _hdr('3'),
            _hdrAt('2', old),
            _hdrAt('1', old),
          ],
          detailsById: <String, MailMessageDetail>{
            '3': _dtl('3'),
            '2': _dtl('2', date: old),
            '1': _dtl('1', date: old),
          },
        );
        final container = _container(
          gateway: gateway,
          store: store,
          cache: cache,
        );
        await container.read(mailAccountControllerProvider.future);

        await container.read(mailSyncControllerProvider.notifier).syncNow();
        expect(gateway.lastFetchMessageIds, <String>['3']);

        gateway.lastFetchMessageIds = <String>[];
        await container.read(mailSyncControllerProvider.notifier).syncNow();
        expect(
          gateway.lastFetchMessageIds,
          isEmpty,
          reason: 'no full download is repeated on every sync',
        );
      },
    );
  });

  group('local search', () {
    MailMessageDetail detail({
      required String id,
      String subject = 'Semesterinfo',
      String body = 'Kein besonderer Inhalt.',
      List<MailAddress> to = const <MailAddress>[
        MailAddress(email: 'stud@hs-anhalt.de'),
      ],
    }) => MailMessageDetail(
      id: id,
      subject: subject,
      from: const MailAddress(
        email: 'buchhaltung@hs-anhalt.de',
        name: 'Buchhaltung',
      ),
      to: to,
      date: DateTime.utc(2026, 7, 20, 9, int.parse(id)),
      body: body,
    );

    MailMessageHeader header(String id, {String subject = 'Semesterinfo'}) =>
        MailMessageHeader(
          id: id,
          subject: subject,
          from: const MailAddress(
            email: 'buchhaltung@hs-anhalt.de',
            name: 'Buchhaltung',
          ),
          date: DateTime.utc(2026, 7, 20, 9, int.parse(id)),
          isSeen: false,
          hasAttachments: false,
        );

    Future<ProviderContainer> seeded(
      FakeMailGateway gateway,
      MemoryMailCache cache,
    ) async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      return container;
    }

    test('finds a cached message without asking the server', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[header('1')]);
      await cache.saveMessage(
        detail(id: '1', body: 'Anbei die Rechnung für das Semester.'),
      );
      final gateway = FakeMailGateway();
      final container = await seeded(gateway, cache);

      await container
          .read(mailSearchControllerProvider.notifier)
          .run('Rechnung');

      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.local.map((MailMessageHeader h) => h.id), <String>['1']);
      expect(gateway.lastSearchQuery, isNull, reason: 'no IMAP round trip');
      expect(state.serverStatus, MailServerSearchStatus.idle);
    });

    test('matches German case and surrounding whitespace robustly', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[
        header('1', subject: 'Prüfungsanmeldung'),
      ]);
      await cache.saveMessage(detail(id: '1', subject: 'Prüfungsanmeldung'));
      final container = await seeded(FakeMailGateway(), cache);

      await container
          .read(mailSearchControllerProvider.notifier)
          .run('   PRÜFUNG  ');

      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.query, 'PRÜFUNG', reason: 'trimmed');
      expect(state.local.map((MailMessageHeader h) => h.id), <String>['1']);
    });

    test('searches recipients and the body, not just the header', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[header('1'), header('2')]);
      await cache.saveMessage(
        detail(
          id: '1',
          to: const <MailAddress>[
            MailAddress(email: 'pruefungsamt@hs-anhalt.de'),
          ],
        ),
      );
      await cache.saveMessage(
        detail(id: '2', body: 'Die Mensa bleibt geschlossen.'),
      );
      final container = await seeded(FakeMailGateway(), cache);
      final controller = container.read(mailSearchControllerProvider.notifier);

      await controller.run('pruefungsamt');
      expect(
        container
            .read(mailSearchControllerProvider)
            .local
            .map((MailMessageHeader h) => h.id),
        <String>['1'],
      );

      await controller.run('mensa');
      expect(
        container
            .read(mailSearchControllerProvider)
            .local
            .map((MailMessageHeader h) => h.id),
        <String>['2'],
      );
    });

    test('a term nothing matches is an empty, non-error state', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[header('1')]);
      await cache.saveMessage(detail(id: '1'));
      final gateway = FakeMailGateway();
      final container = await seeded(gateway, cache);

      await container
          .read(mailSearchControllerProvider.notifier)
          .run('gibt-es-nicht');

      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.hasSearched, isTrue);
      expect(state.local, isEmpty);
      expect(state.serverError, isNull);
      expect(gateway.lastSearchQuery, isNull);
    });

    test('a blank query clears without hitting cache or server', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[header('1')]);
      final gateway = FakeMailGateway();
      final container = await seeded(gateway, cache);
      final controller = container.read(mailSearchControllerProvider.notifier);

      await controller.run('Semesterinfo');
      expect(container.read(mailSearchControllerProvider).local, isNotEmpty);

      await controller.run('   ');

      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.hasSearched, isFalse);
      expect(state.local, isEmpty);
      expect(gateway.lastSearchQuery, isNull);
    });

    test('does not pretend to search an uncached folder locally', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[header('1')]);
      await cache.saveMessage(detail(id: '1'));
      final gateway = FakeMailGateway();
      final container = await seeded(gateway, cache);
      container
          .read(selectedMailboxProvider.notifier)
          .select(const MailFolder(path: 'Sent', name: 'Sent'));

      await container
          .read(mailSearchControllerProvider.notifier)
          .run('Semesterinfo');

      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.localAvailable, isFalse);
      expect(
        state.local,
        isEmpty,
        reason: 'the INBOX cache is not this folder',
      );
      expect(state.mailboxPath, 'Sent');
    });

    test('removing the account leaves no results behind', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[header('1')]);
      await cache.saveMessage(detail(id: '1'));
      final store = InMemoryMailCredentialStore()..write(_creds);
      final container = _container(
        gateway: FakeMailGateway(),
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      await container
          .read(mailSearchControllerProvider.notifier)
          .run('Semesterinfo');
      expect(container.read(mailSearchControllerProvider).local, isNotEmpty);

      await container.read(mailAccountControllerProvider.notifier).signOut();

      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.query, isEmpty);
      expect(state.local, isEmpty);
      expect(state.hasSearched, isFalse);
      expect(await cache.searchHeaders('Semesterinfo'), isEmpty);
    });
  });

  group('server search', () {
    test('runs an IMAP search over the selected mailbox on request', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        searchResults: <MailMessageHeader>[_hdr('9')],
      );
      final container = _container(gateway: gateway, store: store);
      await container.read(mailAccountControllerProvider.future);
      final controller = container.read(mailSearchControllerProvider.notifier);

      await controller.run('  Rechnung ');
      expect(gateway.lastSearchQuery, isNull, reason: 'local search first');

      await controller.searchServer();

      expect(gateway.lastSearchQuery, 'Rechnung', reason: 'trimmed');
      expect(gateway.lastSearchMailbox, 'INBOX');
      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.server.map((MailMessageHeader h) => h.id), <String>['9']);
      expect(state.serverStatus, MailServerSearchStatus.done);
    });

    test('shows the same hit from cache and IMAP only once', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('1')]);
      await cache.saveMessage(_dtl('1'));
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        // The server returns the cached message *and* one only it knows.
        searchResults: <MailMessageHeader>[_hdr('1'), _hdr('9')],
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      final controller = container.read(mailSearchControllerProvider.notifier);

      await controller.run('Subject 1');
      await controller.searchServer();

      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.local.map((MailMessageHeader h) => h.id), <String>['1']);
      expect(state.server.map((MailMessageHeader h) => h.id), <String>['9']);
      final Iterable<String> resultIds = state.results.map(
        (MailMessageHeader h) => h.id,
      );
      const String reason = 'local hits first, each message exactly once';
      expect(resultIds, <String>['1', '9'], reason: reason);
    });

    test('a server failure keeps the local hits and can be retried', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('1')]);
      await cache.saveMessage(_dtl('1'));
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        searchError: const MailFailure(MailFailureKind.network),
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      final controller = container.read(mailSearchControllerProvider.notifier);

      await controller.run('Subject 1');
      await controller.searchServer();

      MailSearchState state = container.read(mailSearchControllerProvider);
      expect(state.serverStatus, MailServerSearchStatus.failed);
      expect(
        state.serverError,
        isA<MailFailure>().having(
          (MailFailure e) => e.kind,
          'kind',
          MailFailureKind.network,
        ),
      );
      final Iterable<String> localIds = state.local.map(
        (MailMessageHeader h) => h.id,
      );
      const String reason = 'offline results survive an IMAP failure';
      expect(localIds, <String>['1'], reason: reason);

      gateway.searchError = null;
      gateway.searchResults = <MailMessageHeader>[_hdr('9')];
      await controller.searchServer();

      state = container.read(mailSearchControllerProvider);
      expect(state.serverStatus, MailServerSearchStatus.done);
      expect(state.serverError, isNull);
      expect(state.results.map((MailMessageHeader h) => h.id), <String>[
        '1',
        '9',
      ]);
    });

    test('a hung search stays pending and keeps the results visible', () async {
      final cache = MemoryMailCache();
      await cache.saveHeaders(<MailMessageHeader>[_hdr('1')]);
      await cache.saveMessage(_dtl('1'));
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        searchGate: Completer<void>(),
        searchStarted: Completer<void>(),
      );
      final container = _container(
        gateway: gateway,
        store: store,
        cache: cache,
      );
      await container.read(mailAccountControllerProvider.future);
      final controller = container.read(mailSearchControllerProvider.notifier);
      await controller.run('Subject 1');

      final Future<void> search = controller.searchServer();
      await gateway.searchStarted!.future;
      MailSearchState state = container.read(mailSearchControllerProvider);
      expect(state.serverStatus, MailServerSearchStatus.running);
      expect(state.local, isNotEmpty, reason: 'never blanked while waiting');

      gateway.searchGate!.complete();
      await search;
      expect(
        container.read(mailSearchControllerProvider).serverStatus,
        MailServerSearchStatus.done,
      );
    });

    test('a late answer for a replaced query is dropped', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        searchGate: Completer<void>(),
        searchStarted: Completer<void>(),
        searchResults: <MailMessageHeader>[_hdr('9')],
      );
      final container = _container(gateway: gateway, store: store);
      await container.read(mailAccountControllerProvider.future);
      final controller = container.read(mailSearchControllerProvider.notifier);
      await controller.run('Rechnung');

      final Future<void> search = controller.searchServer();
      await gateway.searchStarted!.future;
      await controller.run('Mensa');
      gateway.searchGate!.complete();
      await search;

      final MailSearchState state = container.read(
        mailSearchControllerProvider,
      );
      expect(state.query, 'Mensa');
      expect(state.server, isEmpty, reason: 'stale hits never appear');
      expect(state.serverStatus, MailServerSearchStatus.idle);
    });
  });

  group('mergeInboxHeaders', () {
    test('unions by id, newest first, keeping cached ones', () {
      final List<MailMessageHeader> merged = mergeInboxHeaders(
        <MailMessageHeader>[_hdr('1'), _hdr('2')],
        <MailMessageHeader>[_hdr('3'), _hdr('2')],
      );
      expect(merged.map((MailMessageHeader h) => h.id), <String>[
        '3',
        '2',
        '1',
      ]);
    });

    test('drops a missing UID inside an authoritative newest page', () {
      final List<MailMessageHeader> merged = mergeInboxHeaders(
        <MailMessageHeader>[_hdr('1'), _hdr('2'), _hdr('3')],
        <MailMessageHeader>[_hdr('3'), _hdr('1')],
        fetchedLimit: 2,
      );
      expect(merged.map((MailMessageHeader h) => h.id), <String>['3', '1']);
    });

    test('keeps cached UIDs older than the authoritative newest page', () {
      final List<MailMessageHeader> merged = mergeInboxHeaders(
        <MailMessageHeader>[_hdr('1'), _hdr('3')],
        <MailMessageHeader>[_hdr('4'), _hdr('3')],
        fetchedLimit: 2,
      );
      expect(merged.map((MailMessageHeader h) => h.id), <String>[
        '4',
        '3',
        '1',
      ]);
    });

    test('a window covering the whole mailbox is authoritative (C-06)', () {
      final List<MailMessageHeader> merged = mergeInboxHeaders(
        <MailMessageHeader>[_hdr('1'), _hdr('2'), _hdr('3'), _hdr('4')],
        <MailMessageHeader>[_hdr('4'), _hdr('2')],
        fetchedLimit: 50,
        mailboxSize: 2,
      );
      expect(merged.map((MailMessageHeader h) => h.id), <String>['4', '2']);
    });

    test('a smaller page of a larger mailbox removes nothing', () {
      final List<MailMessageHeader> merged = mergeInboxHeaders(
        <MailMessageHeader>[_hdr('1'), _hdr('3')],
        <MailMessageHeader>[_hdr('3')],
        fetchedLimit: 50,
        mailboxSize: 120,
      );
      expect(merged.map((MailMessageHeader h) => h.id), <String>['3', '1']);
    });

    test('an empty server page never erases the last good cache', () {
      final List<MailMessageHeader> merged = mergeInboxHeaders(
        <MailMessageHeader>[_hdr('1'), _hdr('2')],
        const <MailMessageHeader>[],
        fetchedLimit: 50,
      );
      expect(merged.map((MailMessageHeader h) => h.id), <String>['2', '1']);
    });
  });

  group('folders', () {
    test(
      'lists the mailboxes from the server for a signed-in account',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final gateway = FakeMailGateway(
          folders: const <MailFolder>[
            MailFolder.inbox(),
            MailFolder(path: 'Sent', name: 'Sent', role: MailFolderRole.sent),
            MailFolder(
              path: 'Archiv',
              name: 'Archiv',
              role: MailFolderRole.archive,
            ),
          ],
        );
        final container = _container(gateway: gateway, store: store);
        await container.read(mailAccountControllerProvider.future);

        final List<MailFolder> folders = await container.read(
          mailFoldersProvider.future,
        );
        expect(
          folders.map((MailFolder f) => f.path),
          containsAll(<String>['INBOX', 'Sent', 'Archiv']),
        );
      },
    );

    test('stays empty while signed out', () async {
      final container = _container(
        gateway: FakeMailGateway(
          folders: const <MailFolder>[MailFolder.inbox()],
        ),
        store: InMemoryMailCredentialStore(),
      );
      await container.read(mailAccountControllerProvider.future);
      expect(await container.read(mailFoldersProvider.future), isEmpty);
    });
  });

  group('send', () {
    const OutgoingMessage message = OutgoingMessage(
      to: <String>['x@y.de'],
      subject: 'Hi',
      text: 'Body',
    );

    Future<MailComposeController> composer(ProviderContainer container) async {
      await container.read(mailAccountControllerProvider.future);
      return container.read(mailComposeControllerProvider.notifier);
    }

    test('submits the message via SMTP and reports success', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      final container = _container(gateway: gateway, store: store);
      final c = await composer(container);

      final bool sent = await c.send(message);

      expect(sent, isTrue);
      expect(gateway.sendCalls, 1);
      expect(gateway.sent.single.to, <String>['x@y.de']);
    });

    test('does not double-send while a send is in flight', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      final container = _container(gateway: gateway, store: store);
      final c = await composer(container);

      final Future<bool> f1 = c.send(message);
      final Future<bool> f2 = c.send(message);
      final List<bool> results = await Future.wait(<Future<bool>>[f1, f2]);

      expect(results, containsAll(<bool>[true, false]));
      expect(gateway.sendCalls, 1, reason: 'the second trigger is ignored');
    });

    test('a failed SMTP send throws and never records a send', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(
        sendError: const MailFailure(MailFailureKind.network),
      );
      final container = _container(gateway: gateway, store: store);
      final c = await composer(container);

      await expectLater(c.send(message), throwsA(isA<MailFailure>()));
      expect(gateway.sent, isEmpty);
    });

    test('stores the Sent copy separately and reports the result', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(sentCopy: SentCopyResult.appended);
      final container = _container(gateway: gateway, store: store);
      final c = await composer(container);

      final SentCopyResult result = await c.appendSentCopy(message);

      expect(result, SentCopyResult.appended);
      expect(gateway.appendCalls, 1);
      expect(gateway.appended.single.to, <String>['x@y.de']);
    });

    test('a failed Sent copy is reported, not thrown', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(sentCopy: SentCopyResult.appendFailed);
      final container = _container(gateway: gateway, store: store);
      final c = await composer(container);

      expect(await c.appendSentCopy(message), SentCopyResult.appendFailed);
    });

    test('passes attachments through to the gateway untouched', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway();
      final container = _container(gateway: gateway, store: store);
      final c = await composer(container);

      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final OutgoingMessage withAttachment = OutgoingMessage(
        to: const <String>['x@y.de'],
        subject: 'Hi',
        text: 'Body',
        attachments: <OutgoingAttachment>[
          OutgoingAttachment(
            filename: 'a.png',
            mediaType: 'image/png',
            bytes: bytes,
          ),
        ],
      );

      await c.send(withAttachment);

      expect(gateway.sent.single.attachments, hasLength(1));
      expect(gateway.sent.single.attachments.single.filename, 'a.png');
      expect(gateway.sent.single.attachments.single.bytes, same(bytes));
    });

    test('rejects an oversized attachment before contacting SMTP', () async {
      final FakeMailGateway gateway = FakeMailGateway();
      final store = InMemoryMailCredentialStore()..write(_creds);
      final ProviderContainer container = _container(
        gateway: gateway,
        store: store,
      );
      final MailComposeController c = await composer(container);
      final OutgoingMessage oversized = OutgoingMessage(
        to: const <String>['target@example.test'],
        subject: 'Budget',
        text: 'Text',
        attachments: <OutgoingAttachment>[
          OutgoingAttachment(
            filename: 'large.bin',
            mediaType: 'application/octet-stream',
            bytes: Uint8List(MailAttachmentLimits.maxFileBytes + 1),
          ),
        ],
      );

      await expectLater(
        c.send(oversized),
        throwsA(
          isA<MailFailure>().having(
            (MailFailure failure) => failure.kind,
            'kind',
            MailFailureKind.attachmentLimitExceeded,
          ),
        ),
      );
      expect(gateway.sendCalls, 0);
    });

    test('the Sent copy carries the same attachments as the send', () async {
      final store = InMemoryMailCredentialStore()..write(_creds);
      final gateway = FakeMailGateway(sentCopy: SentCopyResult.appended);
      final container = _container(gateway: gateway, store: store);
      final c = await composer(container);

      final Uint8List bytes = Uint8List.fromList(<int>[4, 5, 6]);
      final OutgoingMessage withAttachment = OutgoingMessage(
        to: const <String>['x@y.de'],
        subject: 'Hi',
        text: 'Body',
        attachments: <OutgoingAttachment>[
          OutgoingAttachment(
            filename: 'doc.pdf',
            mediaType: 'application/pdf',
            bytes: bytes,
          ),
        ],
      );

      await c.send(withAttachment);
      final SentCopyResult result = await c.appendSentCopy(withAttachment);

      expect(result, SentCopyResult.appended);
      expect(gateway.appended.single.attachments.single.filename, 'doc.pdf');
      expect(gateway.appended.single.attachments.single.bytes, same(bytes));
    });

    test(
      'does not double-send while a send with attachments is in flight',
      () async {
        final store = InMemoryMailCredentialStore()..write(_creds);
        final gateway = FakeMailGateway();
        final container = _container(gateway: gateway, store: store);
        final c = await composer(container);

        final OutgoingMessage withAttachment = OutgoingMessage(
          to: const <String>['x@y.de'],
          subject: 'Hi',
          text: 'Body',
          attachments: <OutgoingAttachment>[
            OutgoingAttachment(
              filename: 'a.png',
              mediaType: 'image/png',
              bytes: Uint8List.fromList(<int>[1]),
            ),
          ],
        );

        final Future<bool> f1 = c.send(withAttachment);
        final Future<bool> f2 = c.send(withAttachment);
        final List<bool> results = await Future.wait(<Future<bool>>[f1, f2]);

        expect(results, containsAll(<bool>[true, false]));
        expect(gateway.sendCalls, 1, reason: 'the second trigger is ignored');
      },
    );
  });
}
