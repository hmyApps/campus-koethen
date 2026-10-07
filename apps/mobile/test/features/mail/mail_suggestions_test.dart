// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/application/mail_suggestions.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/domain/mail_cache_store.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('suggestRecipients', () {
    const List<MailAddressEntry> all = <MailAddressEntry>[
      MailAddressEntry(email: 'anna@hs-anhalt.de', name: 'Anna'),
      MailAddressEntry(email: 'ben@hs-anhalt.de'),
      MailAddressEntry(email: 'studanna@example.de'),
    ];

    test('is empty for an empty query', () {
      expect(suggestRecipients(all, '  '), isEmpty);
    });

    test('matches email and name, ranking prefix matches first', () {
      final List<MailAddressEntry> result = suggestRecipients(all, 'anna');
      expect(result.map((MailAddressEntry e) => e.email), <String>[
        'anna@hs-anhalt.de', // prefix match ranks above…
        'studanna@example.de', // …a substring match
      ]);
    });

    test('respects the limit', () {
      expect(suggestRecipients(all, 'hs-anhalt', limit: 1), hasLength(1));
    });

    test('merges Exchange and local results without duplicate addresses', () {
      final List<MailAddressEntry> result = mergeRecipientSuggestions(
        const <MailAddressEntry>[MailAddressEntry(email: 'alice@hs-anhalt.de')],
        const <MailAddressEntry>[
          MailAddressEntry(email: 'ALICE@hs-anhalt.de', name: 'Alice Example'),
          MailAddressEntry(email: 'alina@hs-anhalt.de', name: 'Alina'),
        ],
        'ali',
      );

      expect(result.map((MailAddressEntry entry) => entry.email), <String>[
        'ALICE@hs-anhalt.de',
        'alina@hs-anhalt.de',
      ]);
      expect(result.first.name, 'Alice Example');
    });
  });

  group('known-address index', () {
    test(
      'accumulates From/To/Cc across cached messages, preferring names',
      () async {
        final MemoryMailCache cache = MemoryMailCache();
        await cache.saveMessage(
          const MailMessageDetail(
            id: '1',
            subject: 's',
            from: MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
            to: <MailAddress>[MailAddress(email: 'me@hs-anhalt.de')],
            cc: <MailAddress>[MailAddress(email: 'carol@hs-anhalt.de')],
            date: null,
            body: 'b',
          ),
        );
        // A later message learns Carol's name; the index should adopt it.
        await cache.saveMessage(
          const MailMessageDetail(
            id: '2',
            subject: 's',
            from: MailAddress(email: 'carol@hs-anhalt.de', name: 'Carol'),
            to: <MailAddress>[MailAddress(email: 'me@hs-anhalt.de')],
            date: null,
            body: 'b',
          ),
        );

        final List<MailAddressEntry> known = await cache.knownAddresses();
        final Map<String, String?> byEmail = <String, String?>{
          for (final MailAddressEntry e in known) e.email: e.name,
        };
        expect(
          byEmail.keys,
          containsAll(<String>[
            'alice@hs-anhalt.de',
            'me@hs-anhalt.de',
            'carol@hs-anhalt.de',
          ]),
        );
        expect(byEmail['alice@hs-anhalt.de'], 'Alice');
        expect(byEmail['carol@hs-anhalt.de'], 'Carol');
      },
    );
  });
}
