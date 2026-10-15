// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/background/background_sync_runner.dart';
import '../core/background/background_sync_settings.dart';
import '../core/locale/locale_providers.dart';
import '../core/prefs/preference_keys.dart';
import '../core/prefs/settings_controller.dart';
import '../features/calendar/application/public_calendar_providers.dart';
import '../features/canteen/application/canteen_providers.dart';
import '../features/events/application/saved_events_controller.dart';
import '../features/mail/application/mail_account_controller.dart';
import '../features/mail/application/mail_sync_controller.dart';
import '../features/moodle/application/moodle_account_controller.dart';
import '../features/moodle/application/moodle_controller.dart';
import '../features/news/application/news_auto_refresh.dart';
import '../features/notifications/application/new_mail_notification.dart';
import '../features/notifications/application/notification_channels.dart';
import '../features/notifications/application/daily_summary_providers.dart';
import '../features/notifications/application/notification_providers.dart';
import '../features/notifications/application/notification_settings_controller.dart';
import '../features/notifications/domain/immediate_notification.dart';
import '../features/notifications/domain/notification_category.dart';
import '../features/notifications/domain/notification_gateway.dart';
import '../features/notifications/domain/notification_permission.dart';
import '../features/notifications/domain/notification_preferences.dart';
import '../features/timetable/application/timetable_providers.dart';
import '../features/timetable/application/timetable_week.dart';

/// Public sources (news, calendars, timetable) are refreshed at most this
/// often by the background run, however often it wakes up.
const Duration kBackgroundPublicRefreshInterval = Duration(minutes: 55);

/// The parts of one background run, wired to a provider container.
///
/// The container is either the running app's own (the run was handed to it,
/// see `ForegroundBridge`) or a headless one built just for this run. The
/// difference is [ownsNotifications]: a headless run has no screen listening
/// for new mail and no host that prepared the notification plugin, so it does
/// both itself; in the running app the notification host already does.
class BackgroundSyncSteps {
  BackgroundSyncSteps(this.container, {required this.ownsNotifications});

  final ProviderContainer container;
  final bool ownsNotifications;

  bool _notificationsPrepared = false;

  List<BackgroundSyncStep> build() => <BackgroundSyncStep>[
    BackgroundSyncStep('mail', mail),
    BackgroundSyncStep('moodle', moodle),
    BackgroundSyncStep('public', publicData),
    BackgroundSyncStep('plan', plan),
  ];

  // --- Mail -----------------------------------------------------------------

  /// Fetches the inbox and announces what is new.
  ///
  /// Skipped while a refused password is on record: every refused login
  /// counts against the central university account.
  Future<void> mail() async {
    final BackgroundMailGuard guard = BackgroundMailGuard(
      container.read(keyValueStoreProvider),
    );
    if (guard.blocked) return;
    final MailAccountState account = await container.read(
      mailAccountControllerProvider.future,
    );
    if (!account.isSignedIn) return;

    final List<Future<void>> shown = <Future<void>>[];
    final ProviderSubscription<MailNewMessageEvent?> subscription = container
        .listen<MailNewMessageEvent?>(mailNewMessageEventProvider, (
          MailNewMessageEvent? _,
          MailNewMessageEvent? event,
        ) {
          if (event != null && ownsNotifications) {
            shown.add(_showNewMail(event));
          }
        });
    try {
      await container.read(mailSyncControllerProvider.notifier).syncNow();
      await Future.wait(shown);
    } finally {
      subscription.close();
    }
    if (container.read(mailCredentialsRejectionProvider) != null) {
      await guard.block();
    }
  }

  Future<void> _showNewMail(MailNewMessageEvent event) async {
    final NotificationPreferences preferences = container.read(
      notificationSettingsProvider,
    );
    if (!preferences.optedIn ||
        !preferences.isCategoryEnabled(NotificationCategory.newMail)) {
      return;
    }
    await _prepareNotifications();
    final NotificationPermissionStatus permission = await container.read(
      notificationPermissionProvider.future,
    );
    if (!permission.allowsDelivery) return;
    final ImmediateNotification? notification = buildNewMailNotification(
      l10n: container.read(appLocalizationsProvider),
      event: event,
    );
    if (notification == null) return;
    await container.read(notificationGatewayProvider).showNow(notification);
  }

  // --- Moodle ---------------------------------------------------------------

  /// Fetches courses and deadlines. Moodle's own throttle (one automatic
  /// request per hour) applies, so a run every quarter of an hour is cheap.
  Future<void> moodle() async {
    if (await container.read(moodleAccountControllerProvider.future) == null) {
      return;
    }
    await container.read(moodleControllerProvider.future);
    await container.read(moodleControllerProvider.notifier).maybeAutoSync();
  }

  // --- Public data ----------------------------------------------------------

  /// Refreshes news, event calendars and the timetable — rarely, and from the
  /// Campus API only.
  Future<void> publicData() async {
    final store = container.read(keyValueStoreProvider);
    final int? lastMillis = store.getInt(
      PreferenceKeys.backgroundPublicRefreshedAt,
    );
    final DateTime now = DateTime.now();
    if (lastMillis != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastMillis)) <
            kBackgroundPublicRefreshInterval) {
      return;
    }
    await store.setInt(
      PreferenceKeys.backgroundPublicRefreshedAt,
      now.millisecondsSinceEpoch,
    );
    await _attempt(
      () => container.read(newsAutoRefreshProvider.notifier).run(),
    );
    container
      ..invalidate(publicCalendarsCatalogProvider)
      ..invalidate(publicCalendarMonthEntriesProvider);
    await _attempt(() => container.read(timetableForegroundRefreshProvider)());
  }

  // --- Plan -----------------------------------------------------------------

  /// Plans the local notifications again from what the device now knows.
  ///
  /// Whatever the earlier steps could not refresh is planned from the cache:
  /// a failed fetch never empties the plan.
  Future<void> plan() async {
    final List<ProviderSubscription<Object?>> alive =
        <ProviderSubscription<Object?>>[
          container.listen<Object?>(notificationPlanProvider, (_, _) {}),
        ];
    try {
      await _prepareNotifications();
      await _attempt(
        () => container.read(notificationPermissionProvider.future),
      );
      await _attempt(() => container.read(notificationLocationProvider.future));
      await _loadPlanningSources();
      await container
          .read(notificationSchedulerProvider)
          .apply(container.read(notificationPlanProvider));
    } finally {
      for (final ProviderSubscription<Object?> s in alive) {
        s.close();
      }
    }
  }

  /// Everything the plan reads without waiting for it (`.value`): loaded
  /// first, or this run would plan from an empty state.
  Future<void> _loadPlanningSources() async {
    final DateTime today = container.read(notificationPlanningDayProvider);
    await _attempt(() => container.read(savedEventsControllerProvider.future));
    await _attempt(() => container.read(publicCalendarsCatalogProvider.future));
    for (int i = 0; i < 2; i++) {
      final DateTime month = DateTime(today.year, today.month + i);
      await _attempt(
        () => container.read(publicCalendarMonthEntriesProvider(month).future),
      );
    }
    final List<String> groups = container.read(
      selectedTimetableGroupIdsProvider,
    );
    final DateTime lastDay = DateTime(today.year, today.month, today.day + 14);
    for (final String groupId in groups) {
      for (
        DateTime week = TimetableWeek.startOf(today);
        !week.isAfter(lastDay);
        week = TimetableWeek.shift(week, TimetableWeek.lengthInDays)
      ) {
        await _attempt(
          () => container.read(
            timetableWeekProvider(
              TimetableWeekRequest(groupId: groupId, weekStart: week),
            ).future,
          ),
        );
      }
    }
    final String? canteen = container.read(selectedCanteenSlugProvider);
    if (canteen != null) {
      await _attempt(() => container.read(canteenMenuProvider(canteen).future));
    }
  }

  // --- Shared ---------------------------------------------------------------

  /// A headless run has to start the notification plugin and make sure the
  /// channels exist before it shows or plans anything.
  Future<void> _prepareNotifications() async {
    if (!ownsNotifications || _notificationsPrepared) return;
    final NotificationGateway gateway = container.read(
      notificationGatewayProvider,
    );
    // A tap on one of these notifications opens the app, which reads the
    // launch payload itself; nothing here can route a tap.
    await gateway.initialize(onNotificationTapped: (String? _) {});
    await gateway.ensureChannels(
      notificationChannelSpecs(container.read(appLocalizationsProvider)),
    );
    _notificationsPrepared = true;
  }

  /// One source failing (offline, a server error) must not cost the others.
  static Future<void> _attempt(Future<Object?> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }
}
