// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/application/mail_suggestions.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/domain/mail_cache_store.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_directory_gateway.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/features/mail/presentation/recipient_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_mail.dart';
import '../../support/pump_app.dart';

const MailCredentials _creds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

/// Scriptable Exchange address book; never talks to a server.
class _FakeDirectory implements MailDirectoryGateway {
  _FakeDirectory({this.error, this.results = const <MailAddressEntry>[]});

  MailFailure? error;
  List<MailAddressEntry> results;
  final List<String> queries = <String>[];

  @override
  Future<List<MailAddressEntry>> search(
    MailCredentials credentials,
    String query, {
    int limit = 20,
  }) async {
    queries.add(query);
    if (error != null) throw error!;
    return results;
  }
}

Future<MemoryMailCache> _cacheWithAlice() async {
  final MemoryMailCache cache = MemoryMailCache();
  await cache.saveMessage(
    const MailMessageDetail(
      id: '1',
      subject: 'Demo',
      from: MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
      to: <MailAddress>[MailAddress(email: 'stud@hs-anhalt.de')],
      date: null,
      body: 'Demo-Inhalt',
    ),
  );
  return cache;
}

List<Override> _overrides(_FakeDirectory directory, MemoryMailCache cache) =>
    <Override>[
      mailGatewayProvider.overrideWithValue(FakeMailGateway()),
      mailCredentialStoreProvider.overrideWithValue(
        InMemoryMailCredentialStore()..write(_creds),
      ),
      mailCacheStoreProvider.overrideWithValue(cache),
      mailDirectoryGatewayProvider.overrideWithValue(directory),
    ];

Future<List<MailAddressEntry>> _suggest(
  ProviderContainer container,
  String query,
) async {
  // Hold a listener like the field does while it waits for the result.
  final ProviderSubscription<Future<List<MailAddressEntry>>> sub = container
      .listen(mailRecipientSuggestionsProvider(query).future, (_, _) {});
  try {
    return await sub.read();
  } finally {
    sub.close();
  }
}

void main() {
  group('Exchange directory lock', () {
    test('stops asking Exchange after the first rejected login of a session '
        'and keeps the local suggestions', () async {
      final _FakeDirectory directory = _FakeDirectory(
        error: const MailFailure(MailFailureKind.invalidCredentials),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _overrides(directory, await _cacheWithAlice()),
      );
      addTearDown(container.dispose);

      final List<MailAddressEntry> first = await _suggest(container, 'alic');
      final List<MailAddressEntry> second = await _suggest(container, 'alice');

      expect(directory.queries, <String>['alic']);
      expect(first.map((MailAddressEntry e) => e.email), <String>[
        'alice@hs-anhalt.de',
      ]);
      expect(second.map((MailAddressEntry e) => e.email), <String>[
        'alice@hs-anhalt.de',
      ]);

      // A new mail session (new sign-in) may try Exchange again.
      container.read(mailSessionGenerationProvider.notifier).advance();
      await _suggest(container, 'alice@');
      expect(directory.queries, <String>['alic', 'alice@']);
    });

    test('other Exchange failures do not lock the directory', () async {
      final _FakeDirectory directory = _FakeDirectory(
        error: const MailFailure(MailFailureKind.timeout),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _overrides(directory, await _cacheWithAlice()),
      );
      addTearDown(container.dispose);

      await _suggest(container, 'al');
      await _suggest(container, 'ali');

      expect(directory.queries, <String>['al', 'ali']);
    });
  });

  group('RecipientAutocompleteField', () {
    testWidgets('shows local and Exchange suggestions after the debounce', (
      WidgetTester tester,
    ) async {
      final _FakeDirectory directory = _FakeDirectory(
        results: const <MailAddressEntry>[
          MailAddressEntry(email: 'alina@hs-anhalt.de', name: 'Alina'),
        ],
      );
      final MemoryMailCache cache =
          await tester.runAsync(_cacheWithAlice) ?? MemoryMailCache();
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpScreen(
        tester,
        Scaffold(
          body: Form(
            child: RecipientAutocompleteField(
              controller: controller,
              label: 'An',
            ),
          ),
        ),
        overrides: _overrides(directory, cache),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'ali');
      await tester.pump(const Duration(milliseconds: 100));
      expect(directory.queries, isEmpty, reason: 'still debouncing');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(directory.queries, <String>['ali']);
      expect(find.text('alice@hs-anhalt.de'), findsOneWidget);
      expect(find.text('alina@hs-anhalt.de'), findsOneWidget);
    });

    testWidgets('typing quickly asks Exchange once, for the last token', (
      WidgetTester tester,
    ) async {
      final _FakeDirectory directory = _FakeDirectory();
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpScreen(
        tester,
        Scaffold(
          body: Form(
            child: RecipientAutocompleteField(
              controller: controller,
              label: 'An',
            ),
          ),
        ),
        overrides: _overrides(directory, MemoryMailCache()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'al');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextFormField), 'ali');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextFormField), 'alin');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(directory.queries, <String>['alin']);
    });
  });
}
