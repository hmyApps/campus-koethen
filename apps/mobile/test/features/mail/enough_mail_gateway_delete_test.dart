// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/data/enough_mail_gateway.dart';
import 'package:campus_koethen/features/mail/domain/hsa_mail_profile.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
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
}) {
  return (String tag, String command) {
    if (command.startsWith('LOGIN ')) return <String>['$tag OK LOGIN done'];
    if (command.startsWith('LIST')) {
      return <String>[
        '* LIST (\\HasNoChildren) "/" "INBOX"',
        '* LIST (\\HasNoChildren) "/" "$trashName"',
        '* LIST (\\HasNoChildren) "/" "Sent Items"',
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
}
