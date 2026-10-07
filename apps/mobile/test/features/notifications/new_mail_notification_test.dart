// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/application/mail_sync_controller.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_settings_controller.dart';
import 'package:campus_koethen/features/notifications/data/device_time_zone.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_plan.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:campus_koethen/features/notifications/presentation/notification_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_notification_gateway.dart';
import '../../support/pump_app.dart';

const MailMessageHeader _newMessage = MailMessageHeader(
  id: '4711',
  subject: 'Must stay out of the notification',
  from: MailAddress(email: 'private@example.invalid', name: 'Private sender'),
  date: null,
  isSeen: false,
  hasAttachments: false,
);

Future<(ProviderContainer, FakeNotificationGateway)> _pumpHost(
  WidgetTester tester,
) async {
  final FakeNotificationGateway gateway = FakeNotificationGateway();
  final ProviderContainer container = await pumpScreen(
    tester,
    const NotificationHost(child: SizedBox.shrink()),
    overrides: <Override>[
      notificationGatewayProvider.overrideWithValue(gateway),
      timeZoneResolverProvider.overrideWithValue(
        FixedTimeZoneResolver('Europe/Berlin'),
      ),
      notificationPlanProvider.overrideWithValue(
        const NotificationPlan.empty(),
      ),
    ],
  );
  await tester.pumpAndSettle();
  return (container, gateway);
}

void main() {
  testWidgets('confirmed new mail is shown with neutral content after opt-in', (
    WidgetTester tester,
  ) async {
    final (ProviderContainer container, FakeNotificationGateway gateway) =
        await _pumpHost(tester);
    await container
        .read(notificationSettingsProvider.notifier)
        .setOptedIn(true);

    container.read(mailNewMessageEventProvider.notifier).publish(
      const <MailMessageHeader>[_newMessage],
    );
    await tester.pumpAndSettle();

    expect(gateway.shown, hasLength(1));
    final notification = gateway.shown.single;
    expect(notification.category, NotificationCategory.newMail);
    expect(notification.visibility, NotificationVisibility.neutral);
    expect(notification.payload.target, '4711');
    expect(notification.title, isNot(contains(_newMessage.subject)));
    expect(notification.body, isNot(contains(_newMessage.from.email)));
  });

  testWidgets('new mail stays silent without the global opt-in', (
    WidgetTester tester,
  ) async {
    final (ProviderContainer container, FakeNotificationGateway gateway) =
        await _pumpHost(tester);

    container.read(mailNewMessageEventProvider.notifier).publish(
      const <MailMessageHeader>[_newMessage],
    );
    await tester.pumpAndSettle();

    expect(gateway.shown, isEmpty);
  });
}
