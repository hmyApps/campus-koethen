// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/mail/application/exchange_calendar_providers.dart';
import 'package:campus_koethen/features/mail/application/mail_account_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/domain/exchange_calendar_event.dart';
import 'package:campus_koethen/features/mail/domain/exchange_calendar_gateway.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_mail.dart';

const MailCredentials _credentials = MailCredentials(
  emailAddress: 'demo@hs-anhalt.de',
  password: 'not-a-real-password',
);

class _RecordingGateway implements ExchangeCalendarGateway {
  final List<({DateTime from, DateTime to})> calls =
      <({DateTime from, DateTime to})>[];
  final Completer<List<ExchangeCalendarEvent>>? pending;

  _RecordingGateway({this.pending});

  @override
  Future<List<ExchangeCalendarEvent>> fetchEvents(
    MailCredentials credentials, {
    required DateTime from,
    required DateTime to,
  }) async {
    calls.add((from: from, to: to));
    return pending?.future ?? const <ExchangeCalendarEvent>[];
  }
}

Future<ProviderContainer> _container(_RecordingGateway gateway) async {
  final InMemoryMailCredentialStore store = InMemoryMailCredentialStore();
  await store.write(_credentials);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      mailCredentialStoreProvider.overrideWithValue(store),
      exchangeCalendarGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  await container.read(mailAccountControllerProvider.future);
  return container;
}

void main() {
  test(
    'reads the requested inclusive day range with an exclusive EWS end',
    () async {
      final _RecordingGateway gateway = _RecordingGateway();
      final ProviderContainer container = await _container(gateway);

      await container.read(
        exchangeCalendarEventsProvider(
          ExchangeCalendarQuery(
            from: DateTime(2026, 10, 1),
            to: DateTime(2026, 10, 31),
          ),
        ).future,
      );

      expect(gateway.calls, <({DateTime from, DateTime to})>[
        (from: DateTime(2026, 10, 1), to: DateTime(2026, 11, 1)),
      ]);
    },
  );

  test('loads long export windows in bounded parallel batches', () async {
    final Completer<List<ExchangeCalendarEvent>> pending =
        Completer<List<ExchangeCalendarEvent>>();
    final _RecordingGateway gateway = _RecordingGateway(pending: pending);
    final ProviderContainer container = await _container(gateway);

    final Future<List<ExchangeCalendarEvent>> read = container.read(
      exchangeCalendarEventsProvider(
        ExchangeCalendarQuery(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
      ).future,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      gateway.calls,
      hasLength(3),
      reason: 'three chunks run together, but the fourth waits for the batch',
    );
    pending.complete(const <ExchangeCalendarEvent>[]);
    await read;
    expect(gateway.calls, hasLength(4));
  });

  test('a late EWS result cannot survive mail sign-out', () async {
    final Completer<List<ExchangeCalendarEvent>> pending =
        Completer<List<ExchangeCalendarEvent>>();
    final _RecordingGateway gateway = _RecordingGateway(pending: pending);
    final ProviderContainer container = await _container(gateway);
    final Future<List<ExchangeCalendarEvent>> read = container.read(
      exchangeCalendarEventsProvider(
        ExchangeCalendarQuery(
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 31),
        ),
      ).future,
    );
    await Future<void>.delayed(Duration.zero);

    await container.read(mailAccountControllerProvider.notifier).signOut();
    pending.complete(const <ExchangeCalendarEvent>[]);

    await expectLater(read, throwsA(isA<ExchangeCalendarFailure>()));
  });
}
