// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:campus_koethen/features/mail/data/enough_mail_gateway.dart';
import 'package:campus_koethen/features/mail/domain/hsa_mail_profile.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_gateway.dart';
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
///
/// A content fetch (anything beyond size and structure) of a UID in [stall]
/// is never answered; one of a UID in [refuse] is answered with `NO`.
List<String> Function(String, String) _mailbox(
  Map<int, _Message> messages,
  List<String> log, {
  Set<int> stall = const <int>{},
  Set<int> refuse = const <int>{},
}) {
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
      final bool content = criteria.contains('BODY.PEEK[');
      final List<int> requested = <int>[
        for (final String range in match.group(1)!.split(','))
          if (range.contains(':'))
            for (
              int uid = int.parse(range.split(':').first);
              uid <= int.parse(range.split(':').last);
              uid++
            )
              uid
          else
            int.parse(range),
      ];
      if (content && requested.any(stall.contains)) return const <String>[];
      if (content && requested.any(refuse.contains)) {
        return <String>['$tag NO message cannot be fetched'];
      }
      final List<String> lines = <String>[];
      for (final int uid in requested) {
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
        lines.add('* ${uids.indexOf(uid) + 1} FETCH ($items)');
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

/// Demo message: a text body, an inline image and a PDF attachment.
final _Message _imageAndPdf = _Message(
  raw: _crlf(<String>[
    'From: Demo Absender <demo@hs-anhalt.de>',
    'To: stud@hs-anhalt.de',
    'Subject: Demo mit Bild',
    'Date: Tue, 2 Jun 2026 08:00:00 +0200',
    'MIME-Version: 1.0',
    'Content-Type: multipart/mixed; boundary="b2"',
    '',
    '--b2',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: 7bit',
    '',
    'Bild und Plan anbei.',
    '--b2',
    'Content-Type: image/png; name="foto.png"',
    'Content-Disposition: inline; filename="foto.png"',
    'Content-Transfer-Encoding: base64',
    '',
    'iVBORw0KGgo=',
    '--b2',
    'Content-Type: application/pdf; name="plan.pdf"',
    'Content-Disposition: attachment; filename="plan.pdf"',
    'Content-Transfer-Encoding: base64',
    '',
    'JVBERi0xLjQK',
    '--b2--',
  ]),
  structure:
      '(("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 22 1 NIL NIL NIL '
      'NIL)("IMAGE" "PNG" ("NAME" "foto.png") NIL NIL "BASE64" 14 NIL '
      '("INLINE" ("FILENAME" "foto.png")) NIL NIL)("APPLICATION" "PDF" '
      '("NAME" "plan.pdf") NIL NIL "BASE64" 14 NIL ("ATTACHMENT" '
      '("FILENAME" "plan.pdf")) NIL NIL) "MIXED" ("BOUNDARY" "b2") NIL NIL '
      'NIL)',
  parts: <String, String>{
    '1': 'Bild und Plan anbei.\r\n',
    '2': 'iVBORw0KGgo=\r\n',
    '3': 'JVBERi0xLjQK\r\n',
  },
);

/// Demo message: plain text only, but noticeably larger than the others.
final _Message _longText = _Message(
  raw: _crlf(<String>[
    'From: Demo Absender <demo@hs-anhalt.de>',
    'To: stud@hs-anhalt.de',
    'Subject: Demo lang',
    'Date: Wed, 3 Jun 2026 08:00:00 +0200',
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    '',
    for (int i = 0; i < 60; i++) 'Demo-Zeile $i mit etwas Fülltext.',
  ]),
  structure:
      '("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "8BIT" 2100 60 NIL NIL '
      'NIL NIL)',
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

      final MailHeaderPage page = await gateway.fetchHeaders(_credentials);

      expect(page.headers.single.hasAttachments, isTrue);
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

  group('message bodies (C-02)', () {
    test('without attachment download only text and image parts are '
        'fetched', () async {
      final EnoughMailGateway gateway = await gatewayFor(<int, _Message>{
        8: _imageAndPdf,
      });

      final MailMessageDetail detail = await gateway.fetchMessage(
        _credentials,
        id: '8',
      );

      expect(log, isNot(contains(contains('BODY.PEEK[]'))));
      final String contentFetch = log.singleWhere(
        (String c) => c.contains('BODY.PEEK[1]'),
      );
      expect(contentFetch, contains('BODY.PEEK[2]'));
      expect(contentFetch, isNot(contains('BODY.PEEK[3]')));
      expect(detail.subject, 'Demo mit Bild');
      expect(detail.from.email, 'demo@hs-anhalt.de');
      expect(detail.body, 'Bild und Plan anbei.');
      expect(detail.attachments.map((MailAttachment a) => a.filename), <String>[
        'foto.png',
        'plan.pdf',
      ]);
      expect(detail.attachments.first.bytes, isNotNull, reason: 'preview');
      expect(detail.attachments.last.bytes, isNull);
    });

    test('with attachment download the whole message is fetched', () async {
      final EnoughMailGateway gateway = await gatewayFor(<int, _Message>{
        8: _imageAndPdf,
      });

      final MailMessageDetail detail = await gateway.fetchMessage(
        _credentials,
        id: '8',
        includeAttachmentBytes: true,
      );

      expect(log, contains(contains('BODY.PEEK[]')));
      expect(utf8.decode(detail.attachments.last.bytes!), '%PDF-1.4\n');
    });

    test('a large message gets time in proportion to its size', () async {
      log = <String>[];
      server = await FakeImapServer.start(
        _mailbox(<int, _Message>{9: _longText}, log),
        replyDelay: (String command) => command.contains('BODY.PEEK[]')
            ? const Duration(milliseconds: 700)
            : Duration.zero,
      );
      final EnoughMailGateway gateway = EnoughMailGateway(
        _LoopbackMailProfile(server.port),
        commandTimeout: const Duration(milliseconds: 300),
        cleanupTimeout: const Duration(milliseconds: 50),
        // About 2 KiB at 1 KiB/s: two more seconds than the command timeout.
        minTransferBytesPerSecond: 1024,
      );

      final MailMessageDetail detail = await gateway.fetchMessage(
        _credentials,
        id: '9',
      );

      expect(detail.body, startsWith('Demo-Zeile 0'));
    });

    test('one message the server refuses does not fail the prefetch '
        'batch', () async {
      log = <String>[];
      server = await FakeImapServer.start(
        _mailbox(
          <int, _Message>{7: _inlinePdfs, 8: _imageAndPdf},
          log,
          refuse: <int>{8},
        ),
      );
      final EnoughMailGateway gateway = EnoughMailGateway(
        _LoopbackMailProfile(server.port),
      );

      final List<MailMessageDetail> details = await gateway.fetchMessages(
        _credentials,
        ids: <String>['8', '7'],
      );

      expect(details.map((MailMessageDetail d) => d.id), <String>['7']);
    });

    test(
      'a stalled large message no longer starves the smaller ones',
      () async {
        log = <String>[];
        server = await FakeImapServer.start(
          _mailbox(
            <int, _Message>{7: _inlinePdfs, 9: _longText},
            log,
            stall: <int>{9},
          ),
        );
        final EnoughMailGateway gateway = EnoughMailGateway(
          _LoopbackMailProfile(server.port),
          commandTimeout: const Duration(milliseconds: 300),
          cleanupTimeout: const Duration(milliseconds: 50),
          minTransferBytesPerSecond: 1 << 30,
        );

        final List<MailMessageDetail> details = await gateway
            .fetchMessages(_credentials, ids: <String>['9', '7'])
            .timeout(const Duration(seconds: 5));

        expect(details.map((MailMessageDetail d) => d.id), <String>['7']);
        expect(
          server.receivedCommands,
          contains(contains('UID FETCH 9 (UID FLAGS ENVELOPE BODY.PEEK[])')),
          reason: 'the large message was tried last',
        );
        expect(
          server.receivedCommands,
          isNot(contains(contains('LOGOUT'))),
          reason: 'no protocol command after a timed-out fetch',
        );
      },
    );
  });
}
