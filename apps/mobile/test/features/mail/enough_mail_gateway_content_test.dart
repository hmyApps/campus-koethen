// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:campus_koethen/features/mail/data/enough_mail_gateway.dart';
import 'package:campus_koethen/features/mail/domain/hsa_mail_profile.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_imap_server.dart';

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

/// A canned message: its raw RFC 5322 text, its BODYSTRUCTURE and — for
/// partial fetches — the raw content of individual parts by fetch id.
class _Message {
  const _Message({
    required this.raw,
    required this.structure,
    this.parts = const <String, String>{},
  });

  final String raw;
  final String structure;
  final Map<String, String> parts;

  String get header => raw.substring(0, raw.indexOf('\r\n\r\n') + 4);
}

String _literal(String text) => '{${utf8.encode(text).length}}\r\n$text';

/// Serves [messages] (UID → message) over the loopback IMAP fake, answering
/// sequence FETCH for headers and UID FETCH for sizes, structures, whole
/// bodies and individual parts. Every FETCH command is kept in [log].
List<String> Function(String, String) _mailbox(
  Map<int, _Message> messages,
  List<String> log,
) {
  final List<int> uids = messages.keys.toList()..sort();
  return (String tag, String command) {
    if (command.startsWith('LOGIN ')) return <String>['$tag OK LOGIN done'];
    if (command.startsWith('LIST')) {
      return <String>[
        '* LIST (\\HasNoChildren) "/" "INBOX"',
        '$tag OK LIST completed',
      ];
    }
    if (command.startsWith('SELECT')) {
      return <String>[
        '* ${uids.length} EXISTS',
        '* OK [UIDVALIDITY 1] UIDs valid',
        '* FLAGS (\\Deleted \\Seen)',
        '$tag OK [READ-WRITE] SELECT completed',
      ];
    }
    if (command.startsWith('LOGOUT')) {
      return <String>['* BYE logging out', '$tag OK LOGOUT completed'];
    }
    if (command.startsWith('FETCH ')) {
      log.add(command);
      return <String>[
        for (int i = 0; i < uids.length; i++)
          '* ${i + 1} FETCH (UID ${uids[i]} FLAGS () '
              'ENVELOPE ("Mon, 1 Jun 2026 08:00:00 +0200" "Demo" '
              '(("Demo" NIL "demo" "hs-anhalt.de")) '
              '(("Demo" NIL "demo" "hs-anhalt.de")) '
              '(("Demo" NIL "demo" "hs-anhalt.de")) '
              'NIL NIL NIL NIL "<${uids[i]}@fake>") '
              'BODYSTRUCTURE ${messages[uids[i]]!.structure})',
        '$tag OK FETCH completed',
      ];
    }
    if (command.startsWith('UID FETCH ')) {
      log.add(command);
      final RegExpMatch match = RegExp(
        r'^UID FETCH ([\d,:]+) \((.*)\)$',
      ).firstMatch(command)!;
      final String criteria = match.group(2)!;
      final List<String> lines = <String>[];
      for (final String idText in match.group(1)!.split(',')) {
        final int uid = int.parse(idText);
        final _Message? message = messages[uid];
        if (message == null) continue;
        final StringBuffer items = StringBuffer('UID $uid FLAGS ()');
        if (criteria.contains('RFC822.SIZE')) {
          items.write(' RFC822.SIZE ${utf8.encode(message.raw).length}');
        }
        if (criteria.contains('BODYSTRUCTURE')) {
          items.write(' BODYSTRUCTURE ${message.structure}');
        }
        if (criteria.contains('BODY.PEEK[]')) {
          items.write(' BODY[] ${_literal(message.raw)}');
        }
        if (criteria.contains('BODY.PEEK[HEADER]')) {
          items.write(' BODY[HEADER] ${_literal(message.header)}');
        }
        for (final RegExpMatch part in RegExp(
          r'BODY\.PEEK\[([\d.]+)\]',
        ).allMatches(criteria)) {
          final String id = part.group(1)!;
          items.write(' BODY[$id] ${_literal(message.parts[id]!)}');
        }
        lines.add('* 1 FETCH ($items)');
      }
      lines.add('$tag OK FETCH completed');
      return lines;
    }
    return <String>['$tag OK done'];
  };
}

String _crlf(List<String> lines) => '${lines.join('\r\n')}\r\n';

/// Demo message: a text body, an inline PDF and a PDF without any
/// Content-Disposition — the two kinds of attachment that used to vanish.
final _Message _inlinePdfs = _Message(
  raw: _crlf(<String>[
    'From: Demo Absender <demo@hs-anhalt.de>',
    'Reply-To: Demo Sekretariat <sekretariat-demo@hs-anhalt.de>',
    'To: stud@hs-anhalt.de',
    'Cc: Demo Kollegin <kollegin-demo@hs-anhalt.de>',
    'Subject: Demo mit Anhang',
    'Date: Mon, 1 Jun 2026 08:00:00 +0200',
    'MIME-Version: 1.0',
    'Content-Type: multipart/mixed; boundary="b1"',
    '',
    '--b1',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: 7bit',
    '',
    'Hallo, siehe Anhang.',
    '--b1',
    'Content-Type: application/pdf; name="plan.pdf"',
    'Content-Disposition: inline; filename="plan.pdf"',
    'Content-Transfer-Encoding: base64',
    '',
    'JVBERi0xLjQK',
    '--b1',
    'Content-Type: application/pdf; name="liste.pdf"',
    'Content-Transfer-Encoding: base64',
    '',
    'JVBERi0xLjUK',
    '--b1--',
  ]),
  structure:
      '(("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 22 1 NIL NIL NIL '
      'NIL)("APPLICATION" "PDF" ("NAME" "plan.pdf") NIL NIL "BASE64" 14 NIL '
      '("INLINE" ("FILENAME" "plan.pdf")) NIL NIL)("APPLICATION" "PDF" '
      '("NAME" "liste.pdf") NIL NIL "BASE64" 14 NIL NIL NIL NIL) "MIXED" '
      '("BOUNDARY" "b1") NIL NIL NIL)',
  parts: <String, String>{
    '1': 'Hallo, siehe Anhang.\r\n',
    '2': 'JVBERi0xLjQK\r\n',
    '3': 'JVBERi0xLjUK\r\n',
  },
);

void main() {
  late FakeImapServer server;
  late List<String> log;

  Future<EnoughMailGateway> gatewayFor(Map<int, _Message> messages) async {
    log = <String>[];
    server = await FakeImapServer.start(_mailbox(messages, log));
    return EnoughMailGateway(_LoopbackMailProfile(server.port));
  }

  tearDown(() => server.close());

  test('maps the Reply-To header (C-12)', () async {
    final EnoughMailGateway gateway = await gatewayFor(<int, _Message>{
      7: _inlinePdfs,
    });

    final MailMessageDetail detail = await gateway.fetchMessage(
      _credentials,
      id: '7',
    );

    expect(detail.replyTo.map((MailAddress a) => a.email), <String>[
      'sekretariat-demo@hs-anhalt.de',
    ]);
    expect(detail.replyTo.single.name, 'Demo Sekretariat');
  });

  group('attachments without "Content-Disposition: attachment" (C-08)', () {
    test('mark the header as having attachments', () async {
      final EnoughMailGateway gateway = await gatewayFor(<int, _Message>{
        7: _inlinePdfs,
      });

      final List<MailMessageHeader> headers = await gateway.fetchHeaders(
        _credentials,
      );

      expect(headers.single.hasAttachments, isTrue);
    });

    test('are listed with their file names and bytes', () async {
      final EnoughMailGateway gateway = await gatewayFor(<int, _Message>{
        7: _inlinePdfs,
      });

      final MailMessageDetail detail = await gateway.fetchMessage(
        _credentials,
        id: '7',
        includeAttachmentBytes: true,
      );

      expect(detail.body, 'Hallo, siehe Anhang.');
      expect(detail.attachments.map((MailAttachment a) => a.filename), <String>[
        'plan.pdf',
        'liste.pdf',
      ]);
      expect(
        detail.attachments.map((MailAttachment a) => a.mediaType),
        everyElement('application/pdf'),
      );
      expect(utf8.decode(detail.attachments.first.bytes!), '%PDF-1.4\n');
      expect(utf8.decode(detail.attachments.last.bytes!), '%PDF-1.5\n');
    });
  });
}
