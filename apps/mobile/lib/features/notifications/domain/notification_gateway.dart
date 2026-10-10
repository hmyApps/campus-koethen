// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'notification_category.dart';
import 'immediate_notification.dart';
import 'notification_permission.dart';
import 'planned_notification.dart';

/// The reader-visible name and description of one Android notification
/// channel.
///
/// Both strings appear in the Android system settings, so they come from the
/// ARB files like every other visible text. They are handed to the gateway
/// from the widget tree, where a locale exists — the gateway itself has no
/// `BuildContext` and must not invent English defaults.
@immutable
class NotificationChannelSpec {
  const NotificationChannelSpec({
    required this.category,
    required this.name,
    required this.description,
  });

  final NotificationCategory category;
  final String name;
  final String description;

  @override
  bool operator ==(Object other) =>
      other is NotificationChannelSpec &&
      other.category == category &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(category, name, description);
}

/// The whole surface the app uses to talk to the operating system's
/// notification centre.
///
/// A port, so everything above it — planner, scheduler, settings, permission
/// handling — is testable without a device. The real implementation
/// (`data/local_notification_gateway.dart`) is the only file in the app that
/// imports `flutter_local_notifications`; no plugin type ever reaches a
/// controller or a widget.
abstract interface class NotificationGateway {
  /// Prepares the platform side: initialises the plugin, registers the
  /// Android channels and wires the tap callback.
  ///
  /// Asks for **no** permission — the opt-in is a product decision that
  /// happens far away from app start (UX spec § 2.1).
  Future<void> initialize({
    required void Function(String? payload) onNotificationTapped,
  });

  /// Creates or updates the Android channels, one per category.
  ///
  /// Called again whenever the app language changes: re-registering a channel
  /// under the same id is how Android takes over a new name and description.
  /// Sound, importance and the reader's own per-channel choices are kept —
  /// those belong to the reader, not to the app.
  ///
  /// A no-op on iOS, which has no channels.
  Future<void> ensureChannels(List<NotificationChannelSpec> channels);

  /// What the operating system currently says. Re-read on every resume: the
  /// permission can be withdrawn in the system settings while the app sleeps.
  Future<NotificationPermissionStatus> permissionStatus();

  /// Shows the operating system's own permission dialog, once.
  ///
  /// Only meaningful while the status is
  /// [NotificationPermissionStatus.notDetermined]; iOS shows the dialog
  /// exactly once per installation.
  Future<NotificationPermissionStatus> requestPermission();

  /// Removes every **pending** entry. The first half of a full re-plan, and
  /// the whole of switching notifications off.
  ///
  /// Notifications that have already been delivered stay where they are: a
  /// re-plan runs on every resume, and an unread hint must not disappear from
  /// the notification shade just because the reader opened the app (F-01).
  ///
  /// Returns `false` when the platform refused the cancellation. A scheduler
  /// must not register the replacement plan in that case, otherwise stale and
  /// new entries coexist and the reader receives duplicate notifications.
  Future<bool> cancelAllPending();

  /// Registers one entry with the operating system.
  Future<void> schedule(PlannedNotification notification);

  /// Shows one already-gated, confirmed notification immediately.
  Future<void> showNow(ImmediateNotification notification);

  /// How many entries the operating system currently holds for this app.
  /// Diagnostic only — a count, never the entries.
  Future<int> pendingCount();

  /// The payload of the notification that launched the app, if one did.
  /// Returns `null` on every later call and on a normal start.
  Future<String?> takeLaunchPayload();

  /// The categories whose Android channel the reader has silenced.
  ///
  /// Always empty on iOS, which has no per-channel concept. Used only to
  /// explain a silence the app would otherwise be blamed for (UX spec § 3.2).
  Future<Set<NotificationCategory>> mutedCategories();

  /// Opens the operating system's notification settings for this app — the
  /// only remaining route once the permission has been refused.
  Future<void> openSystemNotificationSettings();
}

/// A gateway that does nothing, for tests and for platforms the app runs on
/// without a notification centre.
class NoopNotificationGateway implements NotificationGateway {
  const NoopNotificationGateway();

  @override
  Future<void> initialize({
    required void Function(String? payload) onNotificationTapped,
  }) async {}

  @override
  Future<void> ensureChannels(List<NotificationChannelSpec> channels) async {}

  @override
  Future<NotificationPermissionStatus> permissionStatus() async =>
      NotificationPermissionStatus.notApplicable;

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.notApplicable;

  @override
  Future<bool> cancelAllPending() async => true;

  @override
  Future<void> schedule(PlannedNotification notification) async {}

  @override
  Future<void> showNow(ImmediateNotification notification) async {}

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<String?> takeLaunchPayload() async => null;

  @override
  Future<Set<NotificationCategory>> mutedCategories() async =>
      const <NotificationCategory>{};

  @override
  Future<void> openSystemNotificationSettings() async {}
}
