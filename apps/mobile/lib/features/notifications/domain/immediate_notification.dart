// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'notification_category.dart';
import 'notification_payload.dart';
import 'notification_request.dart';
import 'planned_notification.dart';

@immutable
class ImmediateNotification {
  const ImmediateNotification({
    required this.key,
    required this.category,
    required this.title,
    required this.body,
    required this.payload,
    required this.visibility,
  });

  final String key;
  final NotificationCategory category;
  final String title;
  final String body;
  final NotificationPayload payload;
  final NotificationVisibility visibility;

  int get systemId => notificationSystemId(key);
}
