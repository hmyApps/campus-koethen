// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/notifications/application/grade_change_notification.dart';
import 'package:campus_koethen/features/notifications/domain/immediate_notification.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_gateway.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/domain/notification_preferences.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows one neutral alert for one or more new grades', () async {
    final _Gateway gateway = _Gateway();
    final GradeChangeNotification service = GradeChangeNotification(
      gateway: gateway,
      preferences: const NotificationPreferences(optedIn: true),
      permission: NotificationPermissionStatus.granted,
      title: 'Neue Note eingetragen',
      body: 'Notenspiegel öffnen',
    );

    await service.notify(newGradeCount: 2);

    expect(gateway.shown, hasLength(1));
    expect(gateway.shown.single.category, NotificationCategory.gradeChange);
    expect(gateway.shown.single.visibility, NotificationVisibility.neutral);
    expect(gateway.shown.single.payload.target, 'grades');
  });

  test('respects global permission and the category switch', () async {
    for (final GradeChangeNotification service in <GradeChangeNotification>[
      GradeChangeNotification(
        gateway: _Gateway(),
        preferences: const NotificationPreferences(),
        permission: NotificationPermissionStatus.granted,
        title: 'title',
        body: 'body',
      ),
      GradeChangeNotification(
        gateway: _Gateway(),
        preferences: const NotificationPreferences(
          optedIn: true,
          disabledCategories: <NotificationCategory>{
            NotificationCategory.gradeChange,
          },
        ),
        permission: NotificationPermissionStatus.granted,
        title: 'title',
        body: 'body',
      ),
      GradeChangeNotification(
        gateway: _Gateway(),
        preferences: const NotificationPreferences(optedIn: true),
        permission: NotificationPermissionStatus.denied,
        title: 'title',
        body: 'body',
      ),
    ]) {
      await service.notify(newGradeCount: 1);
      expect((service.gateway as _Gateway).shown, isEmpty);
    }
  });
}

class _Gateway extends NoopNotificationGateway {
  final List<ImmediateNotification> shown = <ImmediateNotification>[];

  @override
  Future<void> showNow(ImmediateNotification notification) async {
    shown.add(notification);
  }
}
