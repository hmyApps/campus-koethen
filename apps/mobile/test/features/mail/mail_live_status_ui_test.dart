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
}
