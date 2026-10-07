// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_settings_controller.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/presentation/pre_permission_sheet.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_notification_gateway.dart';
import '../../support/pump_app.dart';

/// The order of the contextual opt-in is the point of the flow: the app
/// explains first, and only a reader who said yes ever sees the operating
/// system's dialog. The onboarding has its own explanation and tests its
/// direct hand-off to the system dialog separately.

/// A button that runs the flow, so it can be driven from a widget test the
/// way a bookmark or a star drives it in the app.
class _TriggerPoint extends ConsumerWidget {
  const _TriggerPoint({required this.contextual, this.category});

  final bool contextual;

  /// What this trigger point would actually deliver — a star on a dish means
  /// the 11:00 canteen hint.
  final NotificationCategory? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => contextual
            ? maybeOfferNotificationOptIn(context, ref, category: category)
            : requestNotificationOptIn(context, ref),
        child: const Text('go'),
      ),
    ),
  );
}

Future<(ProviderContainer, FakeNotificationGateway)> pumpTrigger(
  WidgetTester tester, {
  required NotificationPermissionStatus permission,
  bool contextual = true,
  KeyValueStore? store,
  NotificationCategory? category,
}) async {
  final FakeNotificationGateway gateway = FakeNotificationGateway(
    permission: permission,
  );
  final ProviderContainer container = await pumpScreen(
    tester,
    _TriggerPoint(contextual: contextual, category: category),
    keyValueStore: store ?? InMemoryKeyValueStore(),
    overrides: <Override>[
      notificationGatewayProvider.overrideWithValue(gateway),
    ],
  );
  await tester.pumpAndSettle();
  return (container, gateway);
}

void main() {
  late AppLocalizations de;

  setUpAll(() async {
    de = await AppLocalizations.delegate.load(AppLocales.german);
  });

  testWidgets('the explanation comes before the system dialog', (
    WidgetTester tester,
  ) async {
    final (_, FakeNotificationGateway gateway) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.notDetermined,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text(de.notificationsPrePromptTitle), findsOneWidget);
    expect(
      gateway.requestCount,
      0,
      reason: 'the operating system must not be asked before the reader is',
    );
  });

  testWidgets('"not now" asks the operating system nothing at all', (
    WidgetTester tester,
  ) async {
    final (
      ProviderContainer container,
      FakeNotificationGateway gateway,
    ) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.notDetermined,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(de.notificationsPrePromptNotNow));
    await tester.pumpAndSettle();

    expect(gateway.requestCount, 0);
    expect(container.read(notificationSettingsProvider).optedIn, isFalse);
    expect(
      container.read(notificationSettingsProvider).prePromptDeclined,
      isTrue,
    );
  });

  testWidgets('a contextual trigger asks once, not at every bookmark', (
    WidgetTester tester,
  ) async {
    final (_, FakeNotificationGateway gateway) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.notDetermined,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(de.notificationsPrePromptNotNow));
    await tester.pumpAndSettle();

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text(de.notificationsPrePromptTitle), findsNothing);
    expect(gateway.requestCount, 0);
  });

  testWidgets('"allow" asks the operating system and turns everything on', (
    WidgetTester tester,
  ) async {
    final (
      ProviderContainer container,
      FakeNotificationGateway gateway,
    ) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.notDetermined,
    );
    // The fake answers the request with whatever it is set to at that moment.
    gateway.permission = NotificationPermissionStatus.notDetermined;

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    gateway.permission = NotificationPermissionStatus.granted;
    await tester.tap(find.text(de.notificationsPrePromptAllow));
    await tester.pumpAndSettle();

    expect(gateway.requestCount, 1);
    expect(container.read(notificationSettingsProvider).optedIn, isTrue);
    expect(
      container.read(notificationSettingsProvider).enabledCategories,
      hasLength(4),
    );
  });

  testWidgets('a refusal leaves the feature off and does not opt in', (
    WidgetTester tester,
  ) async {
    final (
      ProviderContainer container,
      FakeNotificationGateway gateway,
    ) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.notDetermined,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    gateway.permission = NotificationPermissionStatus.denied;
    await tester.tap(find.text(de.notificationsPrePromptAllow));
    await tester.pumpAndSettle();

    expect(container.read(notificationSettingsProvider).optedIn, isFalse);
  });

  testWidgets('an already refused permission is never asked again', (
    WidgetTester tester,
  ) async {
    final KeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.notificationsSystemPromptRequested: 1,
    });
    final (_, FakeNotificationGateway gateway) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.denied,
      contextual: false,
      store: store,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text(de.notificationsPrePromptTitle), findsNothing);
    expect(gateway.requestCount, 0);
  });

  testWidgets(
    'a fresh disabled platform state remains promptable until first request',
    (WidgetTester tester) async {
      final KeyValueStore store = InMemoryKeyValueStore();
      final (
        ProviderContainer container,
        FakeNotificationGateway gateway,
      ) = await pumpTrigger(
        tester,
        permission: NotificationPermissionStatus.denied,
        contextual: false,
        store: store,
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(de.notificationsPrePromptTitle), findsOneWidget);
      expect(gateway.requestCount, 0);

      await tester.tap(find.text(de.notificationsPrePromptAllow));
      await tester.pumpAndSettle();

      expect(gateway.requestCount, 1);
      expect(
        store.getInt(PreferenceKeys.notificationsSystemPromptRequested),
        1,
      );
      expect(container.read(notificationSettingsProvider).optedIn, isFalse);
    },
  );

  testWidgets('an already granted permission needs no sheet and no dialog', (
    WidgetTester tester,
  ) async {
    final (
      ProviderContainer container,
      FakeNotificationGateway gateway,
    ) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.granted,
      contextual: false,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text(de.notificationsPrePromptTitle), findsNothing);
    expect(gateway.requestCount, 0);
    expect(container.read(notificationSettingsProvider).optedIn, isTrue);
  });

  testWidgets('nothing is offered when notifications are already on', (
    WidgetTester tester,
  ) async {
    final KeyValueStore store = InMemoryKeyValueStore();
    final (
      ProviderContainer container,
      FakeNotificationGateway gateway,
    ) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.notDetermined,
      store: store,
    );
    await container
        .read(notificationSettingsProvider.notifier)
        .setOptedIn(true);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text(de.notificationsPrePromptTitle), findsNothing);
    expect(gateway.requestCount, 0);
  });

  testWidgets(
    'a trigger point for a category the reader switched off stays silent',
    (WidgetTester tester) async {
      final (
        ProviderContainer container,
        FakeNotificationGateway gateway,
      ) = await pumpTrigger(
        tester,
        permission: NotificationPermissionStatus.notDetermined,
        category: NotificationCategory.canteenFavourite,
      );
      await container
          .read(notificationSettingsProvider.notifier)
          .setCategoryEnabled(NotificationCategory.canteenFavourite, false);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // The reader has answered this exact question already. Asking again at
      // the very trigger point they silenced would be the app arguing with
      // its own settings.
      expect(find.text(de.notificationsPrePromptTitle), findsNothing);
      expect(gateway.requestCount, 0);
    },
  );

  testWidgets('starring a dish still offers the opt-in when nothing is off', (
    WidgetTester tester,
  ) async {
    final (_, FakeNotificationGateway gateway) = await pumpTrigger(
      tester,
      permission: NotificationPermissionStatus.notDetermined,
      category: NotificationCategory.canteenFavourite,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text(de.notificationsPrePromptTitle), findsOneWidget);
    expect(gateway.requestCount, 0);
  });
}
