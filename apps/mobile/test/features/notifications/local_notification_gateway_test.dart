// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/notifications/data/local_notification_gateway.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/immediate_notification.dart';
import 'package:campus_koethen/features/notifications/domain/notification_payload.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'areNotificationsEnabled' ||
              call.method == 'requestNotificationsPermission') {
            throw PlatformException(code: 'unavailable');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a failed permission status read fails closed', () async {
    final LocalNotificationGateway gateway = LocalNotificationGateway(
      targetPlatform: TargetPlatform.android,
    );

    expect(
      await gateway.permissionStatus(),
      NotificationPermissionStatus.denied,
    );
  });

  test(
    'a failed permission request cannot become a successful opt-in',
    () async {
      final LocalNotificationGateway gateway = LocalNotificationGateway(
        targetPlatform: TargetPlatform.android,
      );

      expect(
        await gateway.requestPermission(),
        NotificationPermissionStatus.denied,
      );
    },
  );

  test('an immediate mail notification reaches the platform once', () async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          return null;
        });
    final LocalNotificationGateway gateway = LocalNotificationGateway(
      targetPlatform: TargetPlatform.android,
    );
    await gateway.initialize(onNotificationTapped: (_) {});
    await gateway.showNow(
      const ImmediateNotification(
        key: 'n4:4711',
        category: NotificationCategory.newMail,
        title: 'Neue E-Mail',
        body: 'Eine neue Nachricht ist eingegangen.',
        payload: NotificationPayload(
          category: NotificationCategory.newMail,
          target: '4711',
        ),
        visibility: NotificationVisibility.neutral,
      ),
    );

    final List<MethodCall> showCalls = calls
        .where((MethodCall call) => call.method == 'show')
        .toList();
    expect(showCalls, hasLength(1));
    expect(showCalls.single.arguments.toString(), contains('v1|mail.new|4711'));
  });

  // F-01: the plugin's `cancelAll` also removes notifications that have
  // already been delivered (Android `NotificationManager.cancelAll()`, iOS
  // `removeAllDeliveredNotifications`). A re-plan runs on every resume, so it
  // must only ever clear the *pending* entries.
  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    test('a re-plan clears only pending entries and keeps delivered ones '
        '(${platform.name})', () async {
      if (platform == TargetPlatform.iOS) {
        IOSFlutterLocalNotificationsPlugin.registerWith();
      }
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            return null;
          });
      final LocalNotificationGateway gateway = LocalNotificationGateway(
        targetPlatform: platform,
      );

      expect(await gateway.cancelAllPending(), isTrue);

      expect(calls.map((MethodCall call) => call.method), <String>[
        'cancelAllPendingNotifications',
      ]);
    });
  }
}
