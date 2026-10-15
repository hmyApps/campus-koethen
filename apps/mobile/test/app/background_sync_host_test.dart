// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/background_sync_host.dart';
import 'package:campus_koethen/app/background_sync_providers.dart';
import 'package:campus_koethen/core/background/background_sync_scheduler.dart';
import 'package:campus_koethen/core/background/foreground_bridge.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/mail/data/mail_cache.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/moodle/application/moodle_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_mail.dart';
import '../support/fake_moodle.dart';
import '../support/pump_app.dart';

class _Platform implements BackgroundJobPlatform {
  final List<String> calls = <String>[];

  @override
  Future<void> registerPeriodic() async => calls.add('register');

  @override
  Future<void> cancel() async => calls.add('cancel');
}

void main() {
  late _Platform platform;

  setUp(() => platform = _Platform());

  List<Override> overrides({bool signedIn = false}) => <Override>[
    backgroundSyncSchedulerProvider.overrideWithValue(
      BackgroundSyncScheduler(platform),
    ),
    mailGatewayProvider.overrideWithValue(FakeMailGateway()),
    mailCredentialStoreProvider.overrideWithValue(
      signedIn
          ? (InMemoryMailCredentialStore()..write(
              const MailCredentials(
                emailAddress: 'stud@hs-anhalt.de',
                password: 'demo-password',
              ),
            ))
          : InMemoryMailCredentialStore(),
    ),
    mailCacheStoreProvider.overrideWithValue(MemoryMailCache()),
    moodleTokenStoreProvider.overrideWithValue(InMemoryMoodleTokenStore()),
    moodleCacheStoreProvider.overrideWithValue(InMemoryMoodleCacheStore()),
  ];

  testWidgets('with nothing connected and no notifications the job is '
      'cancelled, not registered', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      const BackgroundSyncHost(child: SizedBox.shrink()),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();

    expect(platform.calls, <String>['cancel']);
  });

  testWidgets('a connected mail account registers the job once', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const BackgroundSyncHost(child: SizedBox.shrink()),
      overrides: overrides(signedIn: true),
    );
    await tester.pumpAndSettle();

    expect(platform.calls, <String>['register']);
  });

  testWidgets('opting into notifications registers it, switching the '
      'background sync off cancels it', (WidgetTester tester) async {
    final ProviderContainer container = await pumpScreen(
      tester,
      const BackgroundSyncHost(child: SizedBox.shrink()),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(platform.calls, <String>['cancel']);

    await container
        .read(notificationSettingsProvider.notifier)
        .setOptedIn(true);
    await tester.pumpAndSettle();
    expect(platform.calls.last, 'register');

    await container.read(backgroundSyncEnabledProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(platform.calls.last, 'cancel');
  });

  testWidgets('the app serves background runs while it is on screen and '
      'lets go afterwards', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      BackgroundSyncHost(
        onRun: (ProviderContainer _) async {},
        child: const SizedBox.shrink(),
      ),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(ForegroundBridge.isRegistered, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(ForegroundBridge.isRegistered, isFalse);
  });
}
