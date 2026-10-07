// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/data/enough_mail_gateway.dart';
import 'package:campus_koethen/features/mail/domain/hsa_mail_profile.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_folder.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/features/mail/domain/mail_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_imap_server.dart';

/// Points [EnoughMailGateway] at a loopback [FakeImapServer] instead of the
/// real `mail.hs-anhalt.de`. Plain TCP, not TLS: the fake server only speaks
/// plaintext IMAP, and TLS handshake mechanics are no part of what these
/// tests exercise.
class _LoopbackMailProfile extends HsaMailProfile {
  const _LoopbackMailProfile(this._port);

  final int _port;

  @override
  String get imapHost => '127.0.0.1';

  @override
  int get imapPort => _port;

  @override
  bool get imapImplicitTls => false;
}

const MailCredentials _credentials = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

void main() {
  late FakeImapServer server;

  Future<EnoughMailGateway> gatewayFor(
    List<String> Function(String tag, String command) onSearch,
    List<String> Function(String tag, String command) onFetch,
  ) async {
    server = await FakeImapServer.start(
      fakeImapHandler(onSearch: onSearch, onFetch: onFetch),
    );
    return EnoughMailGateway(_LoopbackMailProfile(server.port));
  }

  tearDown(() async {
    await server.close();
  });

  group('EnoughMailGateway.fetchHeaders', () {
    test('loads the newest page before a stable UID cursor', () async {
      final EnoughMailGateway gateway = await gatewayFor(
        fakeSearchHits(<int>[1, 2, 3]),
        fakeFetchHandler(<int, FakeImapMessage>{
          2: const FakeImapMessage(
            uid: 2,
            subject: 'Older',
            fromName: 'Alice',
            fromLocal: 'alice',
            fromDomain: 'hs-anhalt.de',
            date: 'Mon, 1 Jun 2026 08:00:00 +0200',
          ),
          3: const FakeImapMessage(
            uid: 3,
            subject: 'Newer',
            fromName: 'Bob',
            fromLocal: 'bob',
            fromDomain: 'hs-anhalt.de',
            date: 'Tue, 2 Jun 2026 08:00:00 +0200',
          ),
        }),
      );

      final List<MailMessageHeader> result = await gateway.fetchHeaders(
        _credentials,
        beforeId: '4',
        limit: 2,
      );

      expect(result.map((MailMessageHeader header) => header.id), <String>[
        '3',
        '2',
      ]);
      expect(
        server.receivedCommands.singleWhere(
          (String command) => command.contains('UID SEARCH'),
        ),
        contains('UID 1:3'),
      );
    });
  });

  group('EnoughMailGateway mailbox mutation and live sync', () {
    test('moves a message to the special-use Trash folder by UID', () async {
      server = await FakeImapServer.start(
        (String tag, String command) {
          if (command.startsWith('LOGIN ')) {
            return <String>['$tag OK LOGIN completed'];
          }
          if (command.startsWith('LIST')) {
            return <String>[
              '* LIST (\\HasNoChildren) "/" "INBOX"',
              '* LIST (\\HasNoChildren \\Trash) "/" "Deleted Items"',
              '$tag OK LIST completed',
            ];
          }
          if (command.startsWith('SELECT')) {
            return <String>[
              '* 1 EXISTS',
              '* OK [UIDVALIDITY 1] UIDs valid',
              '* FLAGS (\\Deleted \\Seen)',
              '$tag OK [READ-WRITE] SELECT completed',
            ];
          }
          if (command.startsWith('UID MOVE')) {
            return <String>['$tag OK MOVE completed'];
          }
          if (command.startsWith('LOGOUT')) {
            return <String>['* BYE logging out', '$tag OK LOGOUT completed'];
          }
          return <String>['$tag OK done'];
        },
        greeting: '* OK [CAPABILITY IMAP4rev1 UIDPLUS MOVE SPECIAL-USE] ready',
      );
      final EnoughMailGateway gateway = EnoughMailGateway(
        _LoopbackMailProfile(server.port),
      );

      await gateway.deleteMessage(_credentials, id: '7');

      expect(
        server.receivedCommands,
        contains(contains('UID MOVE 7 "Deleted Items"')),
      );
    });

    test('enters IMAP IDLE when the server advertises it', () async {
      String? idleTag;
      server = await FakeImapServer.start((String tag, String command) {
        if (command.startsWith('LOGIN ')) {
          return <String>['$tag OK LOGIN completed'];
        }
        if (command.startsWith('LIST')) {
          return <String>[
            '* LIST (\\HasNoChildren) "/" "INBOX"',
            '$tag OK LIST completed',
          ];
        }
        if (command.startsWith('SELECT')) {
          return <String>[
            '* 1 EXISTS',
            '* OK [UIDVALIDITY 1] UIDs valid',
            '* FLAGS (\\Deleted \\Seen)',
            '$tag OK [READ-WRITE] SELECT completed',
          ];
        }
        if (command == 'IDLE') {
          idleTag = tag;
          return const <String>['+ idling'];
        }
        if (tag == 'DONE' && idleTag != null) {
          return <String>['$idleTag OK IDLE terminated'];
        }
        if (command.startsWith('LOGOUT')) {
          return <String>['* BYE logging out', '$tag OK LOGOUT completed'];
        }
        return <String>['$tag OK done'];
      }, greeting: '* OK [CAPABILITY IMAP4rev1 IDLE] ready');
      final EnoughMailGateway gateway = EnoughMailGateway(
        _LoopbackMailProfile(server.port),
      );

      final MailLiveSignal first = await gateway
          .watchInbox(_credentials)
          .first
          .timeout(const Duration(seconds: 3));

      expect(first, MailLiveSignal.connected);
      expect(server.receivedCommands, contains(contains(' IDLE')));
    });
  });

  group('EnoughMailGateway.searchMessages', () {
    test('a stalled IMAP login surfaces a typed timeout', () async {
      server = await FakeImapServer.start((String tag, String command) {
        if (command.startsWith('LOGIN ')) return const <String>[];
        return <String>['$tag OK done'];
      });
      final EnoughMailGateway gateway = EnoughMailGateway(
        _LoopbackMailProfile(server.port),
        connectionTimeout: const Duration(seconds: 1),
        commandTimeout: const Duration(milliseconds: 20),
        cleanupTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        gateway.fetchMailboxes(_credentials),
        throwsA(
          isA<MailFailure>().having(
            (MailFailure failure) => failure.kind,
            'kind',
            MailFailureKind.timeout,
          ),
        ),
      );
    });

    test('returns matching headers newest first', () async {
      final EnoughMailGateway gateway = await gatewayFor(
        fakeSearchHits(<int>[5, 7]),
        fakeFetchHandler(<int, FakeImapMessage>{
          5: const FakeImapMessage(
            uid: 5,
            subject: 'Older',
            fromName: 'Alice',
            fromLocal: 'alice',
            fromDomain: 'hs-anhalt.de',
            date: 'Mon, 1 Jun 2026 08:00:00 +0200',
          ),
          7: const FakeImapMessage(
            uid: 7,
            subject: 'Newer',
            fromName: 'Bob',
            fromLocal: 'bob',
            fromDomain: 'hs-anhalt.de',
            date: 'Tue, 2 Jun 2026 08:00:00 +0200',
          ),
        }),
      );

      final List<MailMessageHeader> result = await gateway.searchMessages(
        _credentials,
        mailboxPath: kInboxPath,
        query: 'Bob',
      );

      expect(result.map((MailMessageHeader h) => h.id), <String>['7', '5']);
      expect(result.map((MailMessageHeader h) => h.subject), <String>[
        'Newer',
        'Older',
      ]);
    });

    test('sends a properly quoted CHARSET so the query is not rejected '
        'regardless of content — the fixed regression path', () async {
      final EnoughMailGateway gateway = await gatewayFor(
        fakeSearchHits(const <int>[]),
        fakeFetchHandler(const <int, FakeImapMessage>{}),
      );

      await gateway.searchMessages(
        _credentials,
        mailboxPath: kInboxPath,
        query: 'irrelevant',
      );

      final String searchCommand = server.receivedCommands.singleWhere(
        (String c) => c.contains('UID SEARCH'),
      );
      // The historic bug sent an unquoted `CHARSET UTF-8` clause that a
      // strict server rejects outright for every query; the fix quotes it
      // like every other astring the client sends.
      expect(searchCommand, contains('CHARSET "UTF-8"'));
      expect(searchCommand, isNot(contains('CHARSET UTF-8 ')));
    });

    test('escapes quotes and backslashes in the query', () async {
      final EnoughMailGateway gateway = await gatewayFor(
        fakeSearchHits(const <int>[]),
        fakeFetchHandler(const <int, FakeImapMessage>{}),
      );

      await gateway.searchMessages(
        _credentials,
        mailboxPath: kInboxPath,
        query: 'a "quote" and a \\backslash',
      );

      final String searchCommand = server.receivedCommands.singleWhere(
        (String c) => c.contains('UID SEARCH'),
      );
      expect(searchCommand, contains(r'TEXT "a \"quote\" and a \\backslash"'));
    });

    test('returns an empty list, not an error, when nothing matches', () async {
      final EnoughMailGateway gateway = await gatewayFor(
        fakeSearchHits(const <int>[]),
        fakeFetchHandler(const <int, FakeImapMessage>{}),
      );

      final List<MailMessageHeader> result = await gateway.searchMessages(
        _credentials,
        mailboxPath: kInboxPath,
        query: 'nothing matches this',
      );

      expect(result, isEmpty);
    });

    test('a blank query never reaches the server', () async {
      final EnoughMailGateway gateway = await gatewayFor(
        fakeSearchHits(const <int>[]),
        fakeFetchHandler(const <int, FakeImapMessage>{}),
      );

      final List<MailMessageHeader> result = await gateway.searchMessages(
        _credentials,
        mailboxPath: kInboxPath,
        query: '   ',
      );

      expect(result, isEmpty);
      expect(server.receivedCommands, isEmpty);
    });

    test(
      'falls back to a charset-less search instead of a blanket protocol '
      'error when the server rejects the charset declaration entirely',
      () async {
        final EnoughMailGateway gateway = await gatewayFor(
          fakeSearchRejectsCharset(fallbackUids: <int>[9]),
          fakeFetchHandler(<int, FakeImapMessage>{
            9: const FakeImapMessage(
              uid: 9,
              subject: 'Ascii only',
              fromName: 'Carla',
              fromLocal: 'carla',
              fromDomain: 'hs-anhalt.de',
            ),
          }),
        );

        final List<MailMessageHeader> result = await gateway.searchMessages(
          _credentials,
          mailboxPath: kInboxPath,
          query: 'carla',
        );

        expect(result.single.id, '9');
        final Iterable<String> searchCommands = server.receivedCommands.where(
          (String c) => c.contains('UID SEARCH'),
        );
        expect(searchCommands, hasLength(2));
        expect(searchCommands.last, isNot(contains('CHARSET')));
      },
    );

    test('a server that rejects every search attempt still surfaces a typed '
        'MailFailure, never raw server text', () async {
      server = await FakeImapServer.start(
        fakeImapHandler(
          onSearch: (String tag, String command) => <String>[
            '$tag NO search failed unexpectedly',
          ],
          onFetch: fakeFetchHandler(const <int, FakeImapMessage>{}),
        ),
      );
      final EnoughMailGateway gateway = EnoughMailGateway(
        _LoopbackMailProfile(server.port),
      );

      await expectLater(
        gateway.searchMessages(
          _credentials,
          mailboxPath: kInboxPath,
          query: 'anything',
        ),
        throwsA(
          isA<MailFailure>().having(
            (MailFailure f) => f.kind,
            'kind',
            MailFailureKind.protocol,
          ),
        ),
      );
    });
  });
}
