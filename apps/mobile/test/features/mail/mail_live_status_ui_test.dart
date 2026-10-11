// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/application/mail_sync_controller.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/data/mail_local_data_coordinator.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/features/mail/presentation/mail_screen.dart';
import 'package:campus_koethen/features/settings/domain/direct_service.dart';
import 'package:campus_koethen/features/university_account/application/university_service_connector.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/l10n/l10n.dart';
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

void main() {
  testWidgets('a rejected live login is explained instead of "restoring"', (
    WidgetTester tester,
  ) async {
    final InMemoryMailCredentialStore store = InMemoryMailCredentialStore()
      ..write(_creds);
    final MemoryMailCache cache = MemoryMailCache();
    await cache.saveHeaders(<MailMessageHeader>[
      MailMessageHeader(
        id: '1',
        subject: 'Demo-Betreff',
        from: const MailAddress(email: 'alice@hs-anhalt.de', name: 'Alice'),
        date: DateTime.utc(2026, 7, 20, 9),
        isSeen: false,
        hasAttachments: false,
      ),
    ]);
    final FakeMailGateway gateway = FakeMailGateway();
    final ProviderContainer container = await pumpScreen(
      tester,
      const MailScreen(),
      overrides: <Override>[
        mailGatewayProvider.overrideWithValue(gateway),
        mailCredentialStoreProvider.overrideWithValue(store),
        mailCacheStoreProvider.overrideWithValue(cache),
        mailLocalDataCoordinatorProvider.overrideWithValue(
          MailLocalDataCoordinator(
            credentials: store,
            cache: cache,
            wipeIntent: MemoryMailWipeIntentStore(),
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    await container.read(mailLiveSyncControllerProvider.notifier).start();
    gateway.liveSignals.addError(
      const MailFailure(MailFailureKind.invalidCredentials),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Live-Synchronisierung angehalten: Anmeldung fehlgeschlagen. '
        'Bitte prüfe E-Mail-Adresse und Passwort.',
      ),
      findsOneWidget,
    );
    expect(find.text('Live-Verbindung wird wiederhergestellt …'), findsNothing);
    await container.read(mailLiveSyncControllerProvider.notifier).stop();
  });

  testWidgets('a blocked account removal names the real reason', (
    WidgetTester tester,
  ) async {
    final InMemoryMailCredentialStore store = InMemoryMailCredentialStore()
      ..write(_creds);
    final MemoryMailCache cache = MemoryMailCache();
    final ProviderContainer container = await pumpScreen(
      tester,
      const MailScreen(),
      overrides: <Override>[
        mailGatewayProvider.overrideWithValue(FakeMailGateway()),
        mailCredentialStoreProvider.overrideWithValue(store),
        mailCacheStoreProvider.overrideWithValue(cache),
        mailLocalDataCoordinatorProvider.overrideWithValue(
          MailLocalDataCoordinator(
            credentials: store,
            cache: cache,
            wipeIntent: MemoryMailWipeIntentStore(),
          ),
        ),
        universityServiceAdapterProvider(
          DirectService.mail,
        ).overrideWithValue(_BlockedAdapter()),
      ],
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('de'));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.mailAccountRemove));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.mailAccountRemoveConfirm));
    await tester.pumpAndSettle();

    expect(find.text(l10n.universityAccountDeletionInProgress), findsOneWidget);
    await container.read(mailLiveSyncControllerProvider.notifier).stop();
  });
}

class _BlockedAdapter implements UniversityServiceAdapter {
  @override
  Future<void> connect(UniversityIdentity identity, {String? displayName}) =>
      throw UnimplementedError();

  @override
  Future<void> disconnect() async => throw const UniversityAccountFailure(
    UniversityAccountFailureKind.operationBlocked,
  );
}
