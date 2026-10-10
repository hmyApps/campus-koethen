// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:timezone/timezone.dart' as tz;

import '../domain/delivery_window.dart';
import '../domain/notification_category.dart';
import '../domain/notification_plan.dart';
import '../domain/notification_preferences.dart';
import '../domain/notification_permission.dart';
import '../domain/notification_request.dart';
import '../domain/planned_notification.dart';

/// Turns the candidates of every category into the complete set of
/// notifications the operating system should hold — ADR-0001 § 7.
///
/// A **pure function**: no provider, no platform channel, no clock of its own,
/// no I/O. Everything it needs is an argument, so "what would be scheduled
/// right now, in Sydney, on the day the clocks change" is a unit test rather
/// than a device session.
///
/// It also never produces a delta. Each run answers with the whole target
/// state, and the scheduler cancels everything before re-registering it. That
/// is the entire implementation of P12: updating, replacing and cancelling are
/// not separate code paths, they are what happens when a cancelled entry
/// simply stops being produced.
///
/// The order of the steps matters and is asserted by the tests:
///
/// 1. permission and the global switch — one "no" empties the whole plan;
/// 2. the category switches;
/// 3. resolve each trigger into the device zone, and apply the delivery
///    window (P7) to the categories it applies to — never onto or past the
///    target a trigger names;
/// 4. drop everything already past — missed moments are never caught up;
/// 5. drop duplicate keys, first one wins;
/// 6. sort deterministically;
/// 7. cut to the budget, counting what did not fit.
///
/// Filtering before sorting is what keeps a cancelled or long-past entry from
/// occupying a budget slot ahead of a reminder that is still due.
NotificationPlan planNotifications({
  required Iterable<NotificationRequest> candidates,
  required NotificationPreferences preferences,
  required NotificationPermissionStatus permission,
  required tz.TZDateTime now,
  int budget = kMaxScheduledNotifications,
}) {
  final List<NotificationRequest> all = candidates.toList(growable: false);
  final Map<NotificationDropReason, int> dropped =
      <NotificationDropReason, int>{};
  void drop(NotificationDropReason reason, [int count = 1]) {
    if (count <= 0) return;
    dropped[reason] = (dropped[reason] ?? 0) + count;
  }

  if (!preferences.optedIn || !permission.allowsDelivery) {
    drop(NotificationDropReason.notPermitted, all.length);
    return NotificationPlan(
      notifications: const <PlannedNotification>[],
      diagnostics: NotificationPlanDiagnostics(
        candidateCount: all.length,
        scheduledCount: 0,
        scheduledByCategory: const <NotificationCategory, int>{},
        dropped: dropped,
        budget: budget,
      ),
    );
  }

  final tz.Location location = now.location;
  final List<PlannedNotification> eligible = <PlannedNotification>[];
  final Set<String> seenKeys = <String>{};

  for (final NotificationRequest request in all) {
    if (!preferences.isCategoryEnabled(request.category)) {
      drop(NotificationDropReason.categoryDisabled);
      continue;
    }

    final tz.TZDateTime desired = _resolveTrigger(request.trigger, location);
    final tz.TZDateTime scheduledAt;
    switch (request.category.windowPolicy) {
      case DeliveryWindowPolicy.anyLocalTime:
        scheduledAt = desired;
      case DeliveryWindowPolicy.shiftIntoWindow:
        // A reminder that names its target is never shifted onto or past it:
        // a deadline at 23:59 with a one-hour lead is reminded about at
        // 20:00 that evening, not at 07:00 after it has passed.
        scheduledAt = switch (request.trigger) {
          AbsoluteTrigger(before: final DateTime target?) =>
            DeliveryWindow.shiftIntoWindowBefore(desired, target),
          _ => DeliveryWindow.shiftIntoWindow(desired),
        };
      case DeliveryWindowPolicy.fixedLocalTime:
        if (!DeliveryWindow.allows(desired)) {
          // Not shifted: a fixed-time category that lands outside the window
          // is a contributor bug, and moving it would hide the bug behind a
          // notification at a time nobody specified.
          drop(NotificationDropReason.outsideDeliveryWindow);
          continue;
        }
        scheduledAt = desired;
    }

    if (!scheduledAt.isAfter(now)) {
      drop(NotificationDropReason.inThePast);
      continue;
    }
    if (!seenKeys.add(request.key)) {
      drop(NotificationDropReason.duplicateKey);
      continue;
    }

    eligible.add(
      PlannedNotification(
        key: request.key,
        category: request.category,
        scheduledAt: scheduledAt,
        title: request.title,
        body: request.body,
        payload: request.payload,
        visibility: request.visibility,
      ),
    );
  }

  eligible.sort(_byScheduleThenCategoryThenKey);

  final List<PlannedNotification> scheduled = eligible.length <= budget
      ? eligible
      : eligible.sublist(0, budget);
  drop(NotificationDropReason.budgetExhausted, eligible.length - budget);

  final Map<NotificationCategory, int> byCategory =
      <NotificationCategory, int>{};
  for (final PlannedNotification entry in scheduled) {
    byCategory[entry.category] = (byCategory[entry.category] ?? 0) + 1;
  }

  return NotificationPlan(
    notifications: List<PlannedNotification>.unmodifiable(scheduled),
    diagnostics: NotificationPlanDiagnostics(
      candidateCount: all.length,
      scheduledCount: scheduled.length,
      scheduledByCategory: Map<NotificationCategory, int>.unmodifiable(
        byCategory,
      ),
      dropped: Map<NotificationDropReason, int>.unmodifiable(dropped),
      budget: budget,
    ),
  );
}

/// Earliest first; at the same instant by the fixed category order; and for a
/// pair that is still tied, lexicographically by key.
///
/// Total and reproducible, which is the point: which entries survive a full
/// budget must not depend on the order the sources happened to be read in.
int _byScheduleThenCategoryThenKey(
  PlannedNotification a,
  PlannedNotification b,
) {
  final int byTime = a.scheduledAt.compareTo(b.scheduledAt);
  if (byTime != 0) return byTime;
  final int byCategory = a.category.order.compareTo(b.category.order);
  if (byCategory != 0) return byCategory;
  return a.key.compareTo(b.key);
}

tz.TZDateTime _resolveTrigger(
  NotificationTrigger trigger,
  tz.Location location,
) {
  switch (trigger) {
    case AbsoluteTrigger(:final DateTime instant):
      // An instant is an instant; reading it in the device zone is a display
      // question, and the configured lead has already been applied to it as
      // an absolute duration by the contributor.
      return tz.TZDateTime.from(instant, location);
    case LocalTimeTrigger(
      :final DateTime day,
      :final int hour,
      :final int minute,
    ):
      // Built from the date parts, never by adding a Duration to midnight:
      // on the day the clocks change, "08:00" has to stay 08:00 on the dial.
      return tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day,
        hour,
        minute,
      );
  }
}
