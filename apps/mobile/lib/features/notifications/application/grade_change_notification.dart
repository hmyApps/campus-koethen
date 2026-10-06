// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../domain/immediate_notification.dart';
import '../domain/notification_category.dart';
import '../domain/notification_gateway.dart';
import '../domain/notification_payload.dart';
import '../domain/notification_permission.dart';
import '../domain/notification_preferences.dart';
import '../domain/notification_request.dart';

class GradeChangeNotification {
  const GradeChangeNotification({
    required this.gateway,
    required this.preferences,
    required this.permission,
    required this.title,
    required this.body,
  });

  final NotificationGateway gateway;
  final NotificationPreferences preferences;
  final NotificationPermissionStatus permission;
  final String title;
  final String body;

  Future<void> notify({required int newGradeCount}) async {
    if (newGradeCount <= 0 ||
        !preferences.optedIn ||
        !permission.allowsDelivery ||
        !preferences.isCategoryEnabled(NotificationCategory.gradeChange)) {
      return;
    }
    await gateway.showNow(
      ImmediateNotification(
        // One current-state alert rather than a lock-screen history of
        // personal academic changes. A later result replaces the earlier one.
        key: '${NotificationCategory.gradeChange.keyPrefix}:latest',
        category: NotificationCategory.gradeChange,
        title: title,
        body: body,
        payload: const NotificationPayload(
          category: NotificationCategory.gradeChange,
          target: 'grades',
        ),
        visibility: NotificationVisibility.neutral,
      ),
    );
  }
}
