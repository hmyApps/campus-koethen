// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_settings_controller.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/domain/notification_preferences.dart';
import 'package:campus_koethen/features/notifications/presentation/notification_settings_screen.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_notification_gateway.dart';
import '../../support/pump_app.dart';

Future<(ProviderContainer, FakeNotificationGateway)> pumpSettings(
  WidgetTester tester, {
  NotificationPermissionStatus permission =
      NotificationPermissionStatus.granted,
  bool optedIn = true,
  Set<NotificationCategory> muted = const <NotificationCategory>{},
  KeyValueStore? store,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final FakeNotificationGateway gateway = FakeNotificationGateway(
    permission: permission,
    muted: muted,
  );
  final KeyValueStore keyValueStore = store ?? InMemoryKeyValueStore();
  if (permission == NotificationPermissionStatus.denied) {
    await keyValueStore.setInt(
      PreferenceKeys.notificationsSystemPromptRequested,
      1,
    );
  }
  final ProviderContainer container = await pumpScreen(
    tester,
    const NotificationSettingsScreen(),
    keyValueStore: keyValueStore,
    textScaler: textScaler,
    overrides: <Override>[
      notificationGatewayProvider.overrideWithValue(gateway),
    ],
  );
  if (optedIn) {
    await container
        .read(notificationSettingsProvider.notifier)
        .setOptedIn(true);
  }
  await tester.pumpAndSettle();
  return (container, gateway);
}

/// Finds the switch belonging to a tile, by its title.
Finder switchFor(String title) => find.descendant(
  of: find.ancestor(
    of: find.text(title),
    matching: find.byType(SwitchListTile),
  ),
  matching: find.byType(Switch),
);

void main() {
  late AppLocalizations de;

  setUpAll(() async {
    de = await AppLocalizations.delegate.load(AppLocales.german);
  });

  testWidgets('with the permission granted there is no banner', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text(de.notificationsPermissionBlockedTitle), findsNothing);
    expect(find.text(de.notificationsCategoryDailySummary), findsOneWidget);
  });

  testWidgets('a refused permission shows the way to the system settings', (
    WidgetTester tester,
  ) async {
    final (_, FakeNotificationGateway gateway) = await pumpSettings(
      tester,
      permission: NotificationPermissionStatus.denied,
    );

    expect(find.text(de.notificationsPermissionBlockedTitle), findsOneWidget);
    await tester.tap(find.text(de.notificationsOpenSystemSettings));
    await tester.pump();

    expect(gateway.openSettingsCount, 1);
    // And it never asks the operating system again — that dialog is spent.
    expect(gateway.requestCount, 0);
  });

  testWidgets('a refused permission disables the category switches', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester, permission: NotificationPermissionStatus.denied);

    final Switch summary = tester.widget<Switch>(
      switchFor(de.notificationsCategoryDailySummary),
    );
    expect(summary.onChanged, isNull);
  });

  testWidgets('without the opt-in the categories are not interactive', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester, optedIn: false);

    expect(
      tester
          .widget<Switch>(switchFor(de.notificationsCategoryEvents))
          .onChanged,
      isNull,
    );
  });

  testWidgets('switching a category off is persisted', (
    WidgetTester tester,
  ) async {
    final KeyValueStore store = InMemoryKeyValueStore();
    final (ProviderContainer container, _) = await pumpSettings(
      tester,
      store: store,
    );

    await tester.tap(switchFor(de.notificationsCategoryCanteen));
    await tester.pumpAndSettle();

    final NotificationPreferences preferences = container.read(
      notificationSettingsProvider,
    );
    expect(
      preferences.isCategoryEnabled(NotificationCategory.canteenFavourite),
      isFalse,
    );
    expect(
      preferences.isCategoryEnabled(NotificationCategory.dailySummary),
      isTrue,
    );
  });

  testWidgets('a silenced Android channel is explained, not hidden', (
    WidgetTester tester,
  ) async {
    await pumpSettings(
      tester,
      muted: <NotificationCategory>{NotificationCategory.dailySummary},
    );

    expect(find.textContaining(de.notificationsCategoryMuted), findsOneWidget);
  });

  testWidgets('the timeliness limit is stated on the screen, not buried', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);

    await tester.scrollUntilVisible(
      find.text(de.notificationsTimetableMoodleNoticeTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(de.notificationsTimetableMoodleNoticeTitle),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text(de.notificationsFreshnessTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(de.notificationsFreshnessTitle), findsOneWidget);
  });

  testWidgets('switching everything off stays possible while blocked', (
    WidgetTester tester,
  ) async {
    final (ProviderContainer container, _) = await pumpSettings(
      tester,
      permission: NotificationPermissionStatus.denied,
    );

    await tester.tap(switchFor(de.notificationsMasterSwitch));
    await tester.pumpAndSettle();

    expect(container.read(notificationSettingsProvider).optedIn, isFalse);
  });

  testWidgets('the Moodle lead control fits a narrow phone at 200% text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpSettings(tester, textScaler: const TextScaler.linear(2));
    await tester.scrollUntilVisible(
      find.text(de.notificationsMoodleLeadTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text(de.notificationsMoodleLeadTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
