// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/application/mail_account_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_compose_controller.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/features/mail/presentation/mail_error_messages.dart';
import 'package:campus_koethen/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_mail.dart';

const MailCredentials _creds = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

void main() {
  test('an unclear send outcome frees the compose screen and stores no '
      'Sent copy', () async {
    final FakeMailGateway gateway = FakeMailGateway(
      sendError: const MailFailure(MailFailureKind.sendOutcomeUnknown),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        mailGatewayProvider.overrideWithValue(gateway),
        mailCredentialStoreProvider.overrideWithValue(
          InMemoryMailCredentialStore()..write(_creds),
        ),
        mailCacheStoreProvider.overrideWithValue(MemoryMailCache()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(mailAccountControllerProvider.future);

    await expectLater(
      container
          .read(mailComposeControllerProvider.notifier)
          .send(
            const OutgoingMessage(
              to: <String>['empfang@hs-anhalt.de'],
              subject: 'Demo',
              text: 'Demo-Inhalt',
            ),
          ),
      throwsA(
        isA<MailFailure>().having(
          (MailFailure f) => f.kind,
          'kind',
          MailFailureKind.sendOutcomeUnknown,
        ),
      ),
    );

    expect(container.read(mailComposeControllerProvider), isFalse);
    expect(gateway.sendCalls, 1);
    expect(gateway.appendCalls, 0);
  });

  test('the unclear outcome tells the user to check the Sent folder', () {
    const MailFailure failure = MailFailure(MailFailureKind.sendOutcomeUnknown);
    expect(
      mailFailureMessage(lookupAppLocalizations(const Locale('de')), failure),
      contains('„Gesendet“'),
    );
    expect(
      mailFailureMessage(lookupAppLocalizations(const Locale('en')), failure),
      contains('Sent folder'),
    );
  });
}
