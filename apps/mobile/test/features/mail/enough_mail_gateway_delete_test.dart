// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/data/enough_mail_gateway.dart';
import 'package:campus_koethen/features/mail/domain/hsa_mail_profile.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_imap_server.dart';

class _Loopback extends HsaMailProfile {
  const _Loopback(this.imap);

  final int imap;

  @override
  String get imapHost => '127.0.0.1';

  @override
  int get imapPort => imap;

  @override
  bool get imapImplicitTls => false;
}

const MailCredentials _credentials = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

/// An Exchange-like IMAP server: no SPECIAL-USE flags, a localised trash
/// folder, and [moveAnswer] for `UID MOVE`.
List<String> Function(String, String) _exchange({
  required String trashName,
  String? moveAnswer,
  String? copyAnswer,
  String searchAnswer = '7',
}) {
  return (String tag, String command) {
    if (command.startsWith('LOGIN ')) return <String>['$tag OK LOGIN done'];
    if (command.startsWith('LIST')) {
      return <String>[
        '* LIST (\\HasNoChildren) "/" "INBOX"',
        '* LIST (\\HasNoChildren) "/" "$trashName"',
        '* LIST (\\HasNoChildren) "/" "Sent Items"',
        '* LIST (\\HasNoChildren) "/" "Archiv"',
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
    if (command.startsWith('UID SEARCH')) {
      return <String>['* SEARCH $searchAnswer', '$tag OK SEARCH completed'];
    }
    if (command.startsWith('UID COPY') && copyAnswer != null) {
      return <String>['$tag $copyAnswer'];
    }
    if (command.startsWith('UID MOVE') && moveAnswer != null) {
      return <String>['$tag $moveAnswer'];
    }
    if (command.startsWith('LOGOUT')) {
      return <String>['* BYE bye', '$tag OK LOGOUT completed'];
    }
    return <String>['$tag OK done'];
  };
}

EnoughMailGateway _gateway(FakeImapServer server) => EnoughMailGateway(
  _Loopback(server.port),
  connectionTimeout: const Duration(seconds: 2),
  commandTimeout: const Duration(seconds: 2),
  cleanupTimeout: const Duration(milliseconds: 50),
  minTransferBytesPerSecond: 1 << 30,
);

bool _sent(FakeImapServer server, String prefix) =>
    server.receivedCommands.any((String c) => c.contains(' $prefix'));

void main() {
  late FakeImapServer server;
  tearDown(() => server.close());

  const String capabilities = '* OK [CAPABILITY IMAP4rev1 UIDPLUS MOVE] ready';

  for (final String name in <String>[
    'Deleted Items',
    'Gelöschte Elemente',
    'Gelöschte Objekte',
    'Papierkorb',
    'Trash',
  ]) {
    test(
      'moves to the trash folder "$name" even without a \\Trash flag',
      () async {
        server = await FakeImapServer.start(
          _exchange(trashName: name),
          greeting: capabilities,
        );

        await _gateway(server).deleteMessage(_credentials, id: '7');

        expect(_sent(server, 'UID MOVE'), isTrue);
        expect(
          server.receivedCommands.any(
            (String c) => c.contains(name) || c.contains('&'),
          ),
          isTrue,
          reason: 'the move names the trash folder',
        );
        expect(_sent(server, 'UID EXPUNGE'), isFalse);
      },
    );
  }

  test(
    'a refused MOVE falls back to copy, delete and a UID-scoped expunge',
    () async {
      server = await FakeImapServer.start(
        _exchange(
          trashName: 'Deleted Items',
          moveAnswer: 'NO MOVE not allowed',
        ),
        greeting: capabilities,
      );

      await _gateway(server).deleteMessage(_credentials, id: '7');

      expect(_sent(server, 'UID MOVE'), isTrue);
      expect(_sent(server, 'UID COPY'), isTrue);
      expect(_sent(server, 'UID STORE'), isTrue);
      expect(_sent(server, 'UID EXPUNGE'), isTrue);
    },
  );

  test('without any trash folder the message is deleted in place', () async {
    server = await FakeImapServer.start((String tag, String command) {
      if (command.startsWith('LIST')) {
        return <String>[
          '* LIST (\\HasNoChildren) "/" "INBOX"',
          '$tag OK LIST completed',
        ];
      }
      return _exchange(trashName: 'x')(tag, command);
    }, greeting: capabilities);

    await _gateway(server).deleteMessage(_credentials, id: '7');

    expect(_sent(server, 'UID MOVE'), isFalse);
    expect(_sent(server, 'UID STORE'), isTrue);
    expect(_sent(server, 'UID EXPUNGE'), isTrue);
  });

  const String plainCapabilities = '* OK [CAPABILITY IMAP4rev1] ready';

  bool plainExpungeSent() => server.receivedCommands.any(
    (String c) => RegExp(r'^\w+ EXPUNGE$').hasMatch(c.trim()),
  );

  test('without UIDPLUS a lone flagged message is expunged plainly', () async {
    server = await FakeImapServer.start(
      _exchange(trashName: 'Deleted Items'),
      greeting: plainCapabilities,
    );

    await _gateway(server).deleteMessage(_credentials, id: '7');

    expect(_sent(server, 'UID COPY'), isTrue);
    expect(_sent(server, 'UID SEARCH'), isTrue);
    expect(plainExpungeSent(), isTrue);
    expect(_sent(server, 'UID EXPUNGE'), isFalse);
  });

  test('without UIDPLUS another flagged message blocks the expunge', () async {
    server = await FakeImapServer.start(
      _exchange(trashName: 'Deleted Items', searchAnswer: '7 9'),
      greeting: plainCapabilities,
    );

    await expectLater(
      _gateway(server).deleteMessage(_credentials, id: '7'),
      throwsA(
        isA<MailFailure>().having(
          (MailFailure f) => f.step,
          'step',
          'expunge-unsafe',
        ),
      ),
    );
    expect(plainExpungeSent(), isFalse);
  });

  test('a refused COPY names the step and the server reason', () async {
    server = await FakeImapServer.start(
      _exchange(
        trashName: 'Deleted Items',
        copyAnswer: 'NO [CANNOT] copy refused',
      ),
      greeting: '* OK [CAPABILITY IMAP4rev1 UIDPLUS] ready',
    );

    await expectLater(
      _gateway(server).deleteMessage(_credentials, id: '7'),
      throwsA(
        isA<MailFailure>()
            .having((MailFailure f) => f.kind, 'kind', MailFailureKind.protocol)
            .having((MailFailure f) => f.step, 'step', 'copy')
            .having(
              (MailFailure f) => f.detail,
              'detail',
              contains('copy refused'),
            ),
      ),
    );
  });

  test('moves a message into a chosen folder', () async {
    server = await FakeImapServer.start(
      _exchange(trashName: 'Deleted Items'),
      greeting: capabilities,
    );

    await _gateway(
      server,
    ).moveMessage(_credentials, id: '7', targetPath: 'Archiv');

    expect(
      server.receivedCommands.any(
        (String c) => c.contains(' UID MOVE') && c.contains('Archiv'),
      ),
      isTrue,
    );
  });

  test('a refused MOVE into a folder falls back to copy and expunge', () async {
    server = await FakeImapServer.start(
      _exchange(trashName: 'Deleted Items', moveAnswer: 'NO not allowed'),
      greeting: capabilities,
    );

    await _gateway(
      server,
    ).moveMessage(_credentials, id: '7', targetPath: 'Archiv');

    expect(_sent(server, 'UID COPY'), isTrue);
    expect(_sent(server, 'UID EXPUNGE'), isTrue);
  });

  test('moving into the folder it is already in is refused', () async {
    server = await FakeImapServer.start(
      _exchange(trashName: 'Deleted Items'),
      greeting: capabilities,
    );

    await expectLater(
      _gateway(server).moveMessage(_credentials, id: '7', targetPath: 'INBOX'),
      throwsA(isA<MailFailure>()),
    );
    expect(_sent(server, 'UID MOVE'), isFalse);
  });

  // enough_mail encodes a COPY/MOVE target path a second time when it is
  // handed the already-encoded form, which turns "&APY-" into "&-APY-" and
  // makes the server answer [TRYCREATE]. Real German servers name the trash
  // "Gelöschte Elemente", sent as modified UTF-7.
  const String encodedTrash = 'Gel&APY-schte Elemente';

  for (final String? moveAnswer in <String?>[null, 'NO not allowed']) {
    test('a UTF-7 trash name is sent once-encoded '
        '(${moveAnswer == null ? 'MOVE' : 'COPY'})', () async {
      server = await FakeImapServer.start(
        _exchange(trashName: encodedTrash, moveAnswer: moveAnswer),
        greeting: capabilities,
      );

      await _gateway(server).deleteMessage(_credentials, id: '7');

      final String command = server.receivedCommands.firstWhere(
        (String c) => c.contains(' UID MOVE') || c.contains(' UID COPY'),
        orElse: () => '',
      );
      final String relocate = moveAnswer == null
          ? command
          : server.receivedCommands.firstWhere(
              (String c) => c.contains(' UID COPY'),
            );
      expect(relocate, contains('"$encodedTrash"'));
      expect(relocate, isNot(contains('&-')));
    });
  }
}
