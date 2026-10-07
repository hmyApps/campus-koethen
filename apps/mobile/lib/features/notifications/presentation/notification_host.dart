// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_router.dart';
import '../../../app/app_routes.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../l10n/l10n.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../calendar/domain/calendar_entry.dart';
import '../../calendar/presentation/calendar_entry_sheet.dart';
import '../../canteen/application/canteen_providers.dart';
import '../../canteen/domain/meal_highlight.dart';
import '../../mail/application/mail_folders.dart';
import '../../mail/application/mail_providers.dart';
import '../../mail/application/mail_sync_controller.dart';
import '../../mail/domain/mail_folder.dart';
import '../application/daily_summary_providers.dart';
import '../application/event_reminder_candidates.dart';
import '../application/notification_providers.dart';
import '../application/notification_settings_controller.dart';
import '../application/notification_tap_router.dart';
import '../domain/notification_category.dart';
import '../domain/immediate_notification.dart';
import '../domain/notification_gateway.dart';
import '../domain/notification_payload.dart';
import '../domain/notification_plan.dart';
import '../domain/notification_permission.dart';
import '../domain/notification_request.dart';

/// Keeps the operating system's pending notifications equal to the current
/// plan, and turns a tap on one of them into navigation.
///
/// It sits above the router as a plain wrapper because it needs three things
/// a controller cannot have: the app lifecycle, a locale for the Android
/// channel names, and a navigator to send a tap to.
///
/// The triggers of ADR-0001 § 7.1 are split between two places, deliberately:
///
/// * **App state** — a successful fetch, a bookmark, a favourite, a changed
///   group, a preference, the permission — is watched by
///   `notificationCandidatesProvider` and `notificationPlanProvider`. Riverpod
///   rebuilds the plan, and the listener below applies it. No trigger list
///   exists, so none can be forgotten.
/// * **Everything that is not app state** — returning to the foreground, a
///   time zone change, the day rolling over, a language change — has no
///   provider to watch and is handled here.
class NotificationHost extends ConsumerStatefulWidget {
  const NotificationHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends ConsumerState<NotificationHost>
    with WidgetsBindingObserver {
  Timer? _dayRollover;
  String? _channelSignature;
  String? _timeZoneName;
  Duration? _timeZoneOffset;
  DateTime? _plannedForDay;
  bool _launchPayloadHandled = false;
  bool _gatewayReady = false;
  int _lastMailEventSerial = 0;
  MailNewMessageEvent? _pendingMailEvent;
  Future<void> _channelSetup = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeGateway());
  }

  @override
  void dispose() {
    _dayRollover?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeGateway() async {
    try {
      final NotificationGateway gateway = ref.read(notificationGatewayProvider);
      final timeZoneResolver = ref.read(timeZoneResolverProvider);
      await gateway.initialize(onNotificationTapped: _handlePayload);
      // A cold start from a notification: the tap happened before this widget
      // existed, so the platform kept the payload for exactly this question.
      if (!_launchPayloadHandled) {
        _launchPayloadHandled = true;
        _handlePayload(await gateway.takeLaunchPayload());
      }
      _timeZoneName = await timeZoneResolver.deviceTimeZoneName();
      if (!mounted) return;
      _timeZoneOffset = DateTime.now().timeZoneOffset;
      _scheduleDayRollover();
      setState(() => _gatewayReady = true);
      final MailNewMessageEvent? pending = _pendingMailEvent;
      _pendingMailEvent = null;
      if (pending != null) unawaited(_showNewMailNotification(pending));
    } catch (error) {
      // Some devices reject plugin startup transiently. Keep the plan pending;
      // the next resume retries initialization instead of cancelling entries.
      assert(() {
        debugPrint(
          'notifications: initialization failed (${error.runtimeType})',
        );
        return true;
      }());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_onResumed());
  }

  /// Everything that can have changed while the app was away.
  Future<void> _onResumed() async {
    if (!_gatewayReady) {
      await _initializeGateway();
      if (!_gatewayReady) return;
    }
    // The permission first: it can be withdrawn in the system settings, and a
    // withdrawn permission empties the plan, which clears the pending entries.
    await ref.read(notificationPermissionProvider.notifier).refresh();
    ref.invalidate(mutedNotificationCategoriesProvider);

    final String? zone = await ref
        .read(timeZoneResolverProvider)
        .deviceTimeZoneName();
    final Duration offset = DateTime.now().timeZoneOffset;
    if (zone != _timeZoneName || offset != _timeZoneOffset) {
      // A flight, or the twice-yearly change of offset. Every wall-clock time
      // in the plan means something different now, so the zone is re-resolved
      // and everything is planned again from scratch.
      _timeZoneName = zone;
      _timeZoneOffset = offset;
      ref.invalidate(notificationLocationProvider);
    }
    _invalidatePlanIfDayChanged();
    _scheduleDayRollover();
    if (!mounted) return;
    // Mobile operating systems may drop pending entries while the app is
    // suspended. Re-register even when the in-memory plan did not change.
    await _applyPlan(ref.read(notificationPlanProvider));
  }

  Future<void> _applyPlan(NotificationPlan plan) async {
    if (!_gatewayReady) return;
    await _channelSetup;
    await ref.read(notificationSchedulerProvider).apply(plan);
  }

  Future<void> _showNewMailNotification(MailNewMessageEvent event) async {
    if (event.serial <= _lastMailEventSerial) return;
    if (event.sessionGeneration != ref.read(mailSessionGenerationProvider)) {
      return;
    }
    if (!_gatewayReady) {
      final MailNewMessageEvent? pending = _pendingMailEvent;
      if (pending == null || event.serial > pending.serial) {
        _pendingMailEvent = event;
      }
      return;
    }
    _lastMailEventSerial = event.serial;
    final preferences = ref.read(notificationSettingsProvider);
    if (!preferences.optedIn ||
        !preferences.isCategoryEnabled(NotificationCategory.newMail)) {
      return;
    }
    final NotificationPermissionStatus permission = await ref.read(
      notificationPermissionProvider.future,
    );
    if (!mounted ||
        event.sessionGeneration != ref.read(mailSessionGenerationProvider) ||
        !permission.allowsDelivery) {
      return;
    }
    if (!RegExp(r'^\d{1,20}$').hasMatch(event.newestMessageId)) return;
    await _channelSetup;
    // Channel creation crosses an asynchronous platform boundary. The mail
    // account may have been signed out or replaced while it was pending, so
    // fence the event once more before exposing even a generic notification.
    if (!mounted ||
        event.sessionGeneration != ref.read(mailSessionGenerationProvider)) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    await ref
        .read(notificationGatewayProvider)
        .showNow(
          ImmediateNotification(
            key:
                '${NotificationCategory.newMail.keyPrefix}:'
                '${event.newestMessageId}',
            category: NotificationCategory.newMail,
            title: l10n.mailNewNotificationTitle,
            body: l10n.mailNewNotificationBody(event.count),
            payload: NotificationPayload(
              category: NotificationCategory.newMail,
              target: event.newestMessageId,
            ),
            visibility: NotificationVisibility.neutral,
          ),
        );
  }

  /// Re-plans when the calendar day has moved on.
  ///
  /// Two things depend on the date and neither notices it changing on its own:
  /// the plan is a function of "now", read when the provider is built, and
  /// every contributor's planning horizon starts at today. Without this, an
  /// app left open overnight would keep yesterday's answer to "is this in the
  /// past" and would reach one day less far ahead with every night that
  /// passes.
  void _invalidatePlanIfDayChanged() {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    if (_plannedForDay != null && _plannedForDay == today) return;
    _plannedForDay = today;
    ref.read(notificationPlanningDayProvider.notifier).refresh();
    ref.invalidate(notificationPlanProvider);
  }

  /// Fires once at the next local midnight. Rebuilt from the date parts, not
  /// from a fixed 24 hours, so the day the clocks change is still one day.
  void _scheduleDayRollover() {
    _dayRollover?.cancel();
    final DateTime now = DateTime.now();
    final DateTime midnight = DateTime(now.year, now.month, now.day + 1);
    _dayRollover = Timer(
      midnight.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        final Duration offset = DateTime.now().timeZoneOffset;
        if (offset != _timeZoneOffset) {
          _timeZoneOffset = offset;
          ref.invalidate(notificationLocationProvider);
        }
        _invalidatePlanIfDayChanged();
        _scheduleDayRollover();
      },
    );
  }

  void _handlePayload(String? payload) {
    if (payload == null) return;
    // Deferred to the next frame: a cold start resolves the launch payload
    // before the router has built its first route, and pushing into a
    // navigator that does not exist yet is how a notification tap turns into
    // a crash report.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final NotificationTapTarget? target = NotificationTapRouter(
        preferredCanteenSlug: ref.read(settingsProvider).preferredCanteenSlug,
        findCalendarEntry: (String id) =>
            ref.read(calendarEntryForNotificationProvider(id)),
      ).resolve(payload);
      if (target == null) return;

      final DateTime? day = target.focusDay;
      if (day != null) {
        // The destination's own state, set before navigating, so the screen
        // builds on the right day instead of jumping after its first frame.
        if (target.location == AppRoutes.calendar) {
          ref.read(calendarFocusedDayProvider.notifier).select(day);
          ref.read(calendarViewModeProvider.notifier).set(CalendarViewMode.day);
        } else {
          ref.read(selectedMenuDayProvider.notifier).select(day);
          // The dish, where the payload named one. Marking is not resolving:
          // a dish that has since left the menu is simply not found, and the
          // day still opens.
          final String? slug = ref.read(selectedCanteenSlugProvider);
          final String? meal = target.focusMealName;
          final MealHighlightController highlight = ref.read(
            mealHighlightProvider.notifier,
          );
          if (slug != null && meal != null) {
            highlight.mark(
              MealHighlight(canteenSlug: slug, day: day, mealName: meal),
            );
          } else {
            // An older payload, or a hint without a dish. Whatever an earlier
            // tap left behind must not be shown under this one.
            highlight.clear();
          }
        }
      }
      if (target.location == AppRoutes.mail) {
        ref
            .read(selectedMailboxProvider.notifier)
            .select(const MailFolder.inbox());
      }
      ref.read(appRouterProvider).go(target.location);

      if (!target.resolved) {
        final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
          context,
        );
        messenger?.showSnackBar(
          SnackBar(content: Text(context.l10n.notificationsEntryUnavailable)),
        );
        return;
      }

      final CalendarEntry? entry = target.calendarEntry;
      if (entry == null) return;
      // One more frame: `go` has been called but the calendar has not built
      // yet, and a sheet pushed onto the navigator before it does would sit
      // above the previous screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(showCalendarEntrySheet(context, entry));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    // Channel names are reader-visible strings in the Android system settings,
    // so they follow the app language. Re-registering a channel under the same
    // id is how Android takes over a new name; the reader's own sound and
    // importance choices survive it.
    final List<NotificationChannelSpec> channels = <NotificationChannelSpec>[
      NotificationChannelSpec(
        category: NotificationCategory.dailySummary,
        name: l10n.notificationChannelDailySummaryName,
        description: l10n.notificationChannelDailySummaryDescription,
      ),
      NotificationChannelSpec(
        category: NotificationCategory.eventReminder,
        name: l10n.notificationChannelEventsName,
        description: l10n.notificationChannelEventsDescription,
      ),
      NotificationChannelSpec(
        category: NotificationCategory.canteenFavourite,
        name: l10n.notificationChannelCanteenName,
        description: l10n.notificationChannelCanteenDescription,
      ),
      NotificationChannelSpec(
        category: NotificationCategory.moodleDeadline,
        name: l10n.notificationChannelMoodleDeadlineName,
        description: l10n.notificationChannelMoodleDeadlineDescription,
      ),
      NotificationChannelSpec(
        category: NotificationCategory.gradeChange,
        name: l10n.notificationChannelGradeChangeName,
        description: l10n.notificationChannelGradeChangeDescription,
      ),
      NotificationChannelSpec(
        category: NotificationCategory.newMail,
        name: l10n.notificationChannelMailName,
        description: l10n.notificationChannelMailDescription,
      ),
    ];
    final String signature = channels
        .map((NotificationChannelSpec c) => '${c.category.channelId}:${c.name}')
        .join('|');
    if (_gatewayReady && signature != _channelSignature) {
      _channelSignature = signature;
      _channelSetup = ref
          .read(notificationGatewayProvider)
          .ensureChannels(channels);
    }

    ref.listen<NotificationPlan>(notificationPlanProvider, (
      NotificationPlan? previous,
      NotificationPlan next,
    ) {
      if (previous == next) return;
      unawaited(_applyPlan(next));
    });
    ref.listen<MailNewMessageEvent?>(mailNewMessageEventProvider, (
      MailNewMessageEvent? previous,
      MailNewMessageEvent? next,
    ) {
      if (next == null) {
        _pendingMailEvent = null;
        _lastMailEventSerial = 0;
      } else if (next.serial != previous?.serial) {
        unawaited(_showNewMailNotification(next));
      }
    });
    // The first plan too: `listen` only fires on a change, and the very first
    // value of an app start is not one.
    final NotificationPlan plan = ref.watch(notificationPlanProvider);
    if (_plannedForDay == null && _gatewayReady) {
      _plannedForDay = DateUtils.dateOnly(DateTime.now());
      unawaited(_applyPlan(plan));
    }

    return widget.child;
  }
}
