// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/immediate_notification.dart';
import 'package:campus_koethen/features/notifications/domain/notification_gateway.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/domain/planned_notification.dart';

/// An in-memory notification centre.
///
/// Records the call order, because the ordering of `cancelAll` against the
/// scheduling that follows it is the property the scheduler exists to
/// guarantee — and it is invisible in the final state alone.
class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({
    this.permission = NotificationPermissionStatus.granted,
    this.requestResult,
    this.launchPayload,
    this.muted = const <NotificationCategory>{},
    this.failScheduleForKeys = const <String>{},
    this.failCancellation = false,
    this.scheduleDelay,
  });

  NotificationPermissionStatus permission;
  NotificationPermissionStatus? requestResult;
  String? launchPayload;
  Set<NotificationCategory> muted;

  /// Keys the platform refuses, so a partial failure can be exercised.
  Set<String> failScheduleForKeys;

  /// Whether the platform refuses to clear its pending entries.
  bool failCancellation;

  /// Slows a single schedule call down, so two overlapping runs can be
  /// observed interleaving — or not.
  Duration? scheduleDelay;

  final List<String> calls = <String>[];
  final List<PlannedNotification> pending = <PlannedNotification>[];
  final List<ImmediateNotification> shown = <ImmediateNotification>[];
  final List<NotificationChannelSpec> channels = <NotificationChannelSpec>[];

  int requestCount = 0;
  int openSettingsCount = 0;
  void Function(String? payload)? tapCallback;

  @override
  Future<void> initialize({
    required void Function(String? payload) onNotificationTapped,
  }) async {
    calls.add('initialize');
    tapCallback = onNotificationTapped;
  }

  @override
  Future<void> ensureChannels(List<NotificationChannelSpec> channels) async {
    calls.add('ensureChannels');
    this.channels
      ..clear()
      ..addAll(channels);
  }

  @override
  Future<NotificationPermissionStatus> permissionStatus() async => permission;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    requestCount++;
    return requestResult ?? permission;
  }

  @override
  Future<bool> cancelAll() async {
    calls.add('cancelAll');
    if (failCancellation) return false;
    pending.clear();
    return true;
  }

  @override
  Future<void> schedule(PlannedNotification notification) async {
    if (scheduleDelay != null) await Future<void>.delayed(scheduleDelay!);
    calls.add('schedule:${notification.key}');
    if (failScheduleForKeys.contains(notification.key)) {
      throw StateError('platform refused ${notification.key}');
    }
    pending.add(notification);
  }

  @override
  Future<void> showNow(ImmediateNotification notification) async {
    calls.add('showNow:${notification.key}');
    shown.add(notification);
  }

  @override
  Future<int> pendingCount() async => pending.length;

  @override
  Future<String?> takeLaunchPayload() async {
    final String? payload = launchPayload;
    launchPayload = null;
    return payload;
  }

  @override
  Future<Set<NotificationCategory>> mutedCategories() async => muted;

  @override
  Future<void> openSystemNotificationSettings() async => openSettingsCount++;
}
