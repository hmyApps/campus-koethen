// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/data/mail_cache_codec.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/features/mail/presentation/compose_draft.dart';
import 'package:flutter_test/flutter_test.dart';

MailMessageDetail _detail({
  MailAddress from = const MailAddress(
    email: 'alice@hs-anhalt.de',
    name: 'Alice',
  ),
  List<MailAddress> to = const <MailAddress>[
    MailAddress(email: 'me@hs-anhalt.de'),
    MailAddress(email: 'carol@hs-anhalt.de'),
  ],
  List<MailAddress> cc = const <MailAddress>[
    MailAddress(email: 'dan@hs-anhalt.de'),
  ],
  String subject = 'Projekt',
  String body = 'Zeile eins\nZeile zwei',
}) => MailMessageDetail(
  id: '1',
  subject: subject,
  from: from,
  to: to,
  cc: cc,
  date: DateTime.utc(2026, 7, 20, 9, 30),
  body: body,
);

void main() {
  group('replySubject', () {
    test('prefixes Re: for a fresh subject', () {
      expect(replySubject('Projekt'), 'Re: Projekt');
    });
    test('does not double-prefix an existing reply', () {
      expect(replySubject('Re: Projekt'), 'Re: Projekt');
      expect(replySubject('RE: Projekt'), 'RE: Projekt');
    });
    test('handles an empty subject', () {
      expect(replySubject('   '), 'Re:');
    });
  });

  group('quotedBody', () {
    test('adds the attribution and quotes each line', () {
      final String result = quotedBody('a\nb', 'Am X schrieb Y:');
      expect(result, '\n\nAm X schrieb Y:\n> a\n> b');
    });
  });

  group('ComposeDraft.reply', () {
    test('addresses only the original sender and quotes the body', () {
      final ComposeDraft draft = ComposeDraft.reply(
        _detail(),
        attribution: 'Am 20. schrieb Alice:',
      );
      expect(draft.to, <String>['alice@hs-anhalt.de']);
      expect(draft.cc, isEmpty);
      expect(draft.subject, 'Re: Projekt');
      expect(draft.body, contains('> Zeile eins'));
      expect(draft.body, contains('> Zeile zwei'));
    });
  });

  group('ComposeDraft.replyAll', () {
    test('keeps the sender in To and everyone else in Cc, minus self', () {
      final ComposeDraft draft = ComposeDraft.replyAll(
        _detail(),
        selfEmail: 'me@hs-anhalt.de',
        attribution: 'Am 20. schrieb Alice:',
      );
      expect(draft.to, <String>['alice@hs-anhalt.de']);
      // 'me' (self) is excluded; the sender is not duplicated into Cc.
      expect(
        draft.cc,
        containsAll(<String>['carol@hs-anhalt.de', 'dan@hs-anhalt.de']),
      );
      expect(draft.cc, isNot(contains('me@hs-anhalt.de')));
      expect(draft.cc, isNot(contains('alice@hs-anhalt.de')));
    });

    test('deduplicates repeated recipients case-insensitively', () {
      final MailMessageDetail detail = _detail(
        to: const <MailAddress>[
          MailAddress(email: 'carol@hs-anhalt.de'),
          MailAddress(email: 'Carol@hs-anhalt.de'),
        ],
        cc: const <MailAddress>[MailAddress(email: 'carol@hs-anhalt.de')],
      );
      final ComposeDraft draft = ComposeDraft.replyAll(
        detail,
        selfEmail: 'me@hs-anhalt.de',
        attribution: 'x',
      );
      expect(draft.cc, hasLength(1));
    });
  });

  group('Reply-To', () {
    MailMessageDetail withReplyTo() => MailMessageDetail(
      id: '1',
      subject: 'Projekt',
      from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
      replyTo: const <MailAddress>[
        MailAddress(email: 'team-demo@hs-anhalt.de', name: 'Demo-Team'),
      ],
      to: const <MailAddress>[
        MailAddress(email: 'me@hs-anhalt.de'),
        MailAddress(email: 'carol@hs-anhalt.de'),
      ],
      cc: const <MailAddress>[MailAddress(email: 'team-demo@hs-anhalt.de')],
      date: DateTime.utc(2026, 7, 20, 9, 30),
      body: 'Zeile eins',
    );

    test('a reply goes to the Reply-To address instead of From', () {
      final ComposeDraft draft = ComposeDraft.reply(
        withReplyTo(),
        attribution: 'x',
      );
      expect(draft.to, <String>['team-demo@hs-anhalt.de']);
    });

    test('reply-all addresses Reply-To and keeps it out of Cc', () {
      final ComposeDraft draft = ComposeDraft.replyAll(
        withReplyTo(),
        selfEmail: 'me@hs-anhalt.de',
        attribution: 'x',
      );
      expect(draft.to, <String>['team-demo@hs-anhalt.de']);
      expect(draft.cc, <String>['carol@hs-anhalt.de']);
    });

    test('survives the offline cache', () {
      final MailMessageDetail cached = MailCacheCodec.detailFrom(
        MailCacheCodec.detail(withReplyTo()),
      );
      expect(ComposeDraft.reply(cached, attribution: 'x').to, <String>[
        'team-demo@hs-anhalt.de',
      ]);
    });

    test('a cached message from before Reply-To was stored still replies '
        'to From', () {
      final Map<String, dynamic> legacy = MailCacheCodec.detail(_detail())
        ..remove('replyTo');
      expect(
        ComposeDraft.reply(
          MailCacheCodec.detailFrom(legacy),
          attribution: 'x',
        ).to,
        <String>['alice@hs-anhalt.de'],
      );
    });
  });
}
