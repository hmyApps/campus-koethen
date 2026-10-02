// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_koethen/features/mail/data/mail_cache_codec.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detail round-trips through JSON including attachment bytes', () {
    final MailMessageDetail original = MailMessageDetail(
      id: '42',
      subject: 'Betreff',
      from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
      to: const <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
      cc: const <MailAddress>[MailAddress(email: 'carol@hs-anhalt.de')],
      date: DateTime.utc(2026, 7, 20, 9, 30),
      body: 'Hallo\nWelt',
      attachments: <MailAttachment>[
        MailAttachment(
          filename: 'datei.pdf',
          mediaType: 'application/pdf',
          sizeBytes: 3,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
        const MailAttachment(filename: 'x.txt', mediaType: 'text/plain'),
      ],
    );

    // Encode to a string (as Hive would) and back.
    final String raw = jsonEncode(MailCacheCodec.detail(original));
    final MailMessageDetail decoded = MailCacheCodec.detailFrom(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );

    expect(decoded.id, '42');
    expect(decoded.subject, 'Betreff');
    expect(decoded.from.name, 'Alice');
    expect(decoded.to.single.email, 'stud@hs-anhalt.de');
    expect(decoded.cc.single.email, 'carol@hs-anhalt.de');
    expect(decoded.date, DateTime.utc(2026, 7, 20, 9, 30));
    expect(decoded.body, 'Hallo\nWelt');
    expect(decoded.attachments, hasLength(2));
    expect(decoded.attachments.first.bytes, <int>[1, 2, 3]);
    expect(decoded.attachments.first.sizeBytes, 3);
    // The metadata-only attachment stays byte-less.
    expect(decoded.attachments.last.bytes, isNull);
  });

  test('header round-trips through JSON', () {
    final MailMessageHeader original = MailMessageHeader(
      id: '7',
      subject: 'Hi',
      from: const MailAddress(email: 'a@b.de'),
      date: DateTime.utc(2026, 1, 2, 3, 4),
      isSeen: true,
      hasAttachments: true,
    );
    final MailMessageHeader decoded = MailCacheCodec.headerFrom(
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(MailCacheCodec.header(original))) as Map,
      ),
    );
    expect(decoded.id, '7');
    expect(decoded.isSeen, isTrue);
    expect(decoded.hasAttachments, isTrue);
    expect(decoded.date, DateTime.utc(2026, 1, 2, 3, 4));
  });

  test('search document is normalized and never contains attachment bytes', () {
    final MailMessageDetail message = MailMessageDetail(
      id: '8',
      subject: 'PRÜFUNGSANMELDUNG',
      from: const MailAddress(email: 'amt@example.test'),
      to: const <MailAddress>[MailAddress(email: 'stud@example.test')],
      date: DateTime.utc(2026, 10, 1),
      body: 'Bitte Frist beachten.',
      attachments: <MailAttachment>[
        MailAttachment(
          filename: 'secret.bin',
          mediaType: 'application/octet-stream',
          bytes: Uint8List.fromList(utf8.encode('attachment-secret')),
        ),
      ],
    );

    final String encoded = jsonEncode(MailCacheCodec.searchDocument(message));

    expect(encoded, contains('prüfungsanmeldung'));
    expect(encoded, contains('frist'));
    expect(encoded, isNot(contains('attachment-secret')));
    expect(
      encoded,
      isNot(contains(base64Encode(message.attachments.single.bytes!))),
    );
  });
}
