// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:campus_koethen/features/mail/data/mail_mime_builder.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart'
    show
        MailAttachmentLimitException,
        MailAttachmentLimits,
        OutgoingAttachment,
        OutgoingMessage;
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';

const MailCredentials _creds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'irrelevant',
);

void main() {
  group('buildOutgoingMime', () {
    test('builds a plain-text message with no attachments', () {
      const OutgoingMessage message = OutgoingMessage(
        to: <String>['x@y.de'],
        subject: 'Hi',
        text: 'Body',
      );

      final MimeMessage mime = buildOutgoingMime(_creds, message);

      expect(mime.decodeSubject(), 'Hi');
      expect(mime.decodeTextPlainPart()?.trim(), 'Body');
      expect(mime.findContentInfo(), isEmpty);
    });

    test(
      'attaches a single file with exact bytes, filename and media type',
      () {
        final Uint8List bytes = Uint8List.fromList(
          List<int>.generate(300, (int i) => i % 256),
        );
        final OutgoingMessage message = OutgoingMessage(
          to: const <String>['x@y.de'],
          subject: 'Hi',
          text: 'Body',
          attachments: <OutgoingAttachment>[
            OutgoingAttachment(
              filename: 'bild.png',
              mediaType: 'image/png',
              bytes: bytes,
            ),
          ],
        );

        final MimeMessage mime = buildOutgoingMime(_creds, message);

        final List<ContentInfo> infos = mime.findContentInfo();
        expect(infos, hasLength(1));
        expect(infos.single.fileName, 'bild.png');
        expect(infos.single.mediaType?.text, 'image/png');
        final Uint8List? decoded = mime
            .getPart(infos.single.fetchId)
            ?.decodeContentBinary();
        expect(decoded, bytes);
        // The body text must still be there alongside the attachment.
        expect(mime.decodeTextPlainPart()?.trim(), 'Body');
      },
    );

    test('attaches multiple files, each byte-for-byte intact', () {
      final Uint8List a = Uint8List.fromList(<int>[10, 20, 30]);
      final Uint8List b = Uint8List.fromList(
        List<int>.generate(1000, (int i) => (i * 7) % 256),
      );
      final OutgoingMessage message = OutgoingMessage(
        to: const <String>['x@y.de'],
        subject: 'Hi',
        text: 'Body',
        attachments: <OutgoingAttachment>[
          OutgoingAttachment(
            filename: 'a.txt',
            mediaType: 'text/plain',
            bytes: a,
          ),
          OutgoingAttachment(
            filename: 'b.bin',
            mediaType: 'application/octet-stream',
            bytes: b,
          ),
        ],
      );

      final MimeMessage mime = buildOutgoingMime(_creds, message);

      final List<ContentInfo> infos = mime.findContentInfo();
      expect(infos, hasLength(2));
      final Map<String, ContentInfo> byName = <String, ContentInfo>{
        for (final ContentInfo info in infos) info.fileName!: info,
      };
      expect(mime.getPart(byName['a.txt']!.fetchId)?.decodeContentBinary(), a);
      expect(mime.getPart(byName['b.bin']!.fetchId)?.decodeContentBinary(), b);
      expect(byName['a.txt']!.mediaType?.text, 'text/plain');
      expect(byName['b.bin']!.mediaType?.text, 'application/octet-stream');
    });

    test(
      'the sender is always the account address, never an attacker input',
      () {
        const MailCredentials named = MailCredentials(
          emailAddress: 'stud@hs-anhalt.de',
          password: 'irrelevant',
          displayName: 'Max Mustermensch',
        );
        const OutgoingMessage message = OutgoingMessage(
          to: <String>['x@y.de'],
          subject: 'Hi',
          text: 'Body',
        );

        final MimeMessage mime = buildOutgoingMime(named, message);

        final MailAddress? from = mime.from?.firstOrNull;
        expect(from?.email, 'stud@hs-anhalt.de');
        expect(from?.personalName, 'Max Mustermensch');
      },
    );

    test(
      'building twice from the same message yields identical attachment bytes',
      () {
        final Uint8List bytes = Uint8List.fromList(<int>[9, 8, 7, 6, 5]);
        final OutgoingMessage message = OutgoingMessage(
          to: const <String>['x@y.de'],
          subject: 'Hi',
          text: 'Body',
          attachments: <OutgoingAttachment>[
            OutgoingAttachment(
              filename: 'a.bin',
              mediaType: 'application/octet-stream',
              bytes: bytes,
            ),
          ],
        );

        // This is exactly what send() and appendToSent() each do: build fresh
        // from the same OutgoingMessage, so the SMTP send and the Sent copy
        // carry identical attachment content.
        final MimeMessage first = buildOutgoingMime(_creds, message);
        final MimeMessage second = buildOutgoingMime(_creds, message);

        final Uint8List? firstBytes = first
            .getPart(first.findContentInfo().single.fetchId)
            ?.decodeContentBinary();
        final Uint8List? secondBytes = second
            .getPart(second.findContentInfo().single.fetchId)
            ?.decodeContentBinary();
        expect(firstBytes, bytes);
        expect(secondBytes, bytes);
      },
    );
  });

  test('refuses a message outside the attachment budget', () {
    final OutgoingMessage message = OutgoingMessage(
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

    expect(
      () => buildOutgoingMime(_creds, message),
      throwsA(isA<MailAttachmentLimitException>()),
    );
  });
}
