// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;

import '../domain/notification_category.dart';
import '../domain/notification_gateway.dart';
import '../domain/immediate_notification.dart';
import '../domain/notification_permission.dart';
import '../domain/notification_request.dart' show NotificationVisibility;
import '../domain/planned_notification.dart';

/// The only place in the app that knows `flutter_local_notifications` exists.
///
/// Everything above it speaks in the app's own vocabulary — a
/// [PlannedNotification], a [NotificationPermissionStatus] — so the planner,
/// the scheduler and the settings screen all run in plain `flutter test`.
///
/// Platform failures are logged by category, never with notification content.
/// Initialization is propagated to the host so it can retry on resume.
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({
    fln.FlutterLocalNotificationsPlugin? plugin,
    this.targetPlatform,
  }) : _plugin = plugin ?? fln.FlutterLocalNotificationsPlugin();

  final fln.FlutterLocalNotificationsPlugin _plugin;

  /// Overrides runtime platform detection in the platform-channel unit tests.
  @visibleForTesting
  final TargetPlatform? targetPlatform;

  /// Channel texts, so a scheduled notification can name its channel with the
  /// same words the system settings show. Empty until [ensureChannels] ran.
  final Map<NotificationCategory, NotificationChannelSpec> _channels =
      <NotificationCategory, NotificationChannelSpec>{};

  bool _initialized = false;
  bool _launchPayloadTaken = false;

  /// The monochrome status-bar glyph. A coloured or multi-tone drawable is
  /// rendered by Android as a grey square (ADR-0001 § 7.9).
  static const String androidSmallIcon = '@drawable/ic_notification';

  @override
  Future<void> initialize({
    required void Function(String? payload) onNotificationTapped,
  }) async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const fln.InitializationSettings(
          android: fln.AndroidInitializationSettings(androidSmallIcon),
          // All four false: the permission is never requested at start-up.
          // The reader is asked in context, after an explanation, and only
          // then does the system dialog appear (UX spec § 2.1).
          iOS: fln.DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            requestCriticalPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (fln.NotificationResponse response) =>
            onNotificationTapped(response.payload),
      );
      _initialized = true;
    } catch (error) {
      _report('initialize', error);
      rethrow;
    }
  }

  @override
  Future<void> ensureChannels(List<NotificationChannelSpec> channels) async {
    for (final NotificationChannelSpec spec in channels) {
      _channels[spec.category] = spec;
    }
    final fln.AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return;
    for (final NotificationChannelSpec spec in channels) {
      try {
        await android.createNotificationChannel(
          fln.AndroidNotificationChannel(
            spec.category.channelId,
            spec.name,
            description: spec.description,
            // Default, not high: none of the categories is urgent
            // enough to interrupt, and an app that shouts is an app that
            // gets silenced wholesale.
            importance: fln.Importance.defaultImportance,
          ),
        );
      } catch (error) {
        _report('createNotificationChannel', error);
      }
    }
  }

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    try {
      final fln.AndroidFlutterLocalNotificationsPlugin? android = _android;
      if (android != null) {
        final bool? enabled = await android.areNotificationsEnabled();
        if (enabled == null) return NotificationPermissionStatus.notApplicable;
        if (enabled) return NotificationPermissionStatus.granted;
        // Android cannot tell "never asked" from "refused" through this call.
        // Below API 33 the permission does not exist and `enabled` is false
        // only when the reader switched notifications off in the system
        // settings — which is exactly what `denied` means here. Above it, a
        // false answer before the first prompt is corrected by the opt-in
        // flow, which asks the platform for the prompt rather than reading
        // this state.
        return NotificationPermissionStatus.denied;
      }
      final fln.IOSFlutterLocalNotificationsPlugin? ios = _ios;
      if (ios != null) {
        final fln.NotificationsEnabledOptions? options = await ios
            .checkPermissions();
        if (options == null) return NotificationPermissionStatus.notDetermined;
        return options.isEnabled
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      return NotificationPermissionStatus.notApplicable;
    } catch (error) {
      _report('permissionStatus', error);
      // A platform-channel failure is not evidence that delivery is allowed.
      // Fail closed until the next lifecycle refresh can read the real state.
      return NotificationPermissionStatus.denied;
    }
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    try {
      final fln.AndroidFlutterLocalNotificationsPlugin? android = _android;
      if (android != null) {
        final bool? granted = await android.requestNotificationsPermission();
        if (granted == null) return NotificationPermissionStatus.notApplicable;
        return granted
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      final fln.IOSFlutterLocalNotificationsPlugin? ios = _ios;
      if (ios != null) {
        final bool? granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return (granted ?? false)
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      return NotificationPermissionStatus.notApplicable;
    } catch (error) {
      _report('requestPermission', error);
      // Never turn an exception into a successful opt-in. `denied` keeps the
      // plan empty and gives the reader the existing system-settings recovery.
      return NotificationPermissionStatus.denied;
    }
  }

  @override
  Future<bool> cancelAllPending() async {
    try {
      // Never the plugin's `cancelAll()`: in 22.3.0 that also removes every
      // notification already delivered (Android `NotificationManager
      // .cancelAll()`, iOS `removeAllDeliveredNotifications`). A re-plan runs
      // on every resume, so an unread hint would vanish from the shade the
      // moment the reader opened the app. This one only cancels the alarms
      // and pending requests that have not fired yet.
      await _plugin.cancelAllPendingNotifications();
      return true;
    } catch (error) {
      _report('cancelAllPendingNotifications', error);
      return false;
    }
  }

  @override
  Future<void> schedule(PlannedNotification notification) async {
    await _plugin.zonedSchedule(
      id: notification.systemId,
      title: notification.title,
      body: notification.body,
      scheduledDate: notification.scheduledAt,
      payload: notification.payload.toStorage(),
      // Inexact on purpose: an exact alarm would require
      // SCHEDULE_EXACT_ALARM on Android 12+, and the price of that permission
      // is out of all proportion to a few minutes of drift on a reminder
      // planned a day ahead (ADR-0001 § 7.9).
      androidScheduleMode: fln.AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: _detailsFor(notification),
    );
  }

  @override
  Future<void> showNow(ImmediateNotification notification) async {
    try {
      await _plugin.show(
        id: notification.systemId,
        title: notification.title,
        body: notification.body,
        payload: notification.payload.toStorage(),
        notificationDetails: _details(
          notification.category,
          notification.visibility,
        ),
      );
    } catch (error) {
      _report('show', error);
      rethrow;
    }
  }

  @override
  Future<int> pendingCount() async {
    try {
      final List<fln.PendingNotificationRequest> pending = await _plugin
          .pendingNotificationRequests();
      return pending.length;
    } catch (error) {
      _report('pendingNotificationRequests', error);
      return 0;
    }
  }

  @override
  Future<String?> takeLaunchPayload() async {
    if (_launchPayloadTaken) return null;
    _launchPayloadTaken = true;
    try {
      final fln.NotificationAppLaunchDetails? details = await _plugin
          .getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return details.notificationResponse?.payload;
    } catch (error) {
      _report('getNotificationAppLaunchDetails', error);
      return null;
    }
  }

  @override
  Future<Set<NotificationCategory>> mutedCategories() async {
    final fln.AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return const <NotificationCategory>{};
    try {
      final List<fln.AndroidNotificationChannel>? channels = await android
          .getNotificationChannels();
      if (channels == null) return const <NotificationCategory>{};
      final Map<String, fln.AndroidNotificationChannel> byId =
          <String, fln.AndroidNotificationChannel>{
            for (final fln.AndroidNotificationChannel channel in channels)
              channel.id: channel,
          };
      return <NotificationCategory>{
        for (final NotificationCategory category in NotificationCategory.values)
          if (byId[category.channelId]?.importance == fln.Importance.none)
            category,
      };
    } catch (error) {
      _report('getNotificationChannels', error);
      return const <NotificationCategory>{};
    }
  }

  @override
  Future<void> openSystemNotificationSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (error) {
      _report('openAppSettings', error);
    }
  }

  fln.NotificationDetails _detailsFor(PlannedNotification notification) {
    return _details(notification.category, notification.visibility);
  }

  fln.NotificationDetails _details(
    NotificationCategory category,
    NotificationVisibility visibility,
  ) {
    final NotificationChannelSpec? spec = _channels[category];
    return fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        category.channelId,
        // The channel exists by the time anything is scheduled; the fallback
        // is the channel id so a mis-ordered call still produces a working
        // notification rather than an exception.
        spec?.name ?? category.channelId,
        channelDescription: spec?.description,
        icon: androidSmallIcon,
        importance: fln.Importance.defaultImportance,
        priority: fln.Priority.defaultPriority,
        // No group key, ever. P8 asks for separate notifications, and a group
        // key is what would merge them. That Android stacks one app's
        // notifications visually is system behaviour and not this app's doing.
        visibility: switch (visibility) {
          NotificationVisibility.publicContent =>
            fln.NotificationVisibility.public,
          NotificationVisibility.neutral => fln.NotificationVisibility.private,
        },
      ),
      // iOS carries no lock-screen visibility flag this plugin version can
      // set, and its hidden-preview placeholder is governed by a reader
      // setting the app does not control. P10 is therefore kept where it
      // actually holds on both platforms: in the text itself, which is
      // already written without the sensitive part.
      iOS: const fln.DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  fln.AndroidFlutterLocalNotificationsPlugin? get _android {
    if (kIsWeb ||
        !(targetPlatform == TargetPlatform.android ||
            (targetPlatform == null && Platform.isAndroid))) {
      return null;
    }
    return _plugin
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
  }

  fln.IOSFlutterLocalNotificationsPlugin? get _ios {
    if (kIsWeb ||
        !(targetPlatform == TargetPlatform.iOS ||
            (targetPlatform == null && Platform.isIOS))) {
      return null;
    }
    return _plugin
        .resolvePlatformSpecificImplementation<
          fln.IOSFlutterLocalNotificationsPlugin
        >();
  }

  /// One line, in debug builds only, naming the failed operation and the error
  /// type. Never the payload, never a title, never a key — a notification body
  /// can carry a dish name or an event title, and a log is not the place for
  /// either (ADR-0001 § 10).
  void _report(String operation, Object error) {
    assert(() {
      debugPrint('notifications: $operation failed (${error.runtimeType})');
      return true;
    }());
  }
}
