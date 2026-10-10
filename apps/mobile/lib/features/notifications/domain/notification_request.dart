// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'notification_category.dart';
import 'notification_payload.dart';

/// When a request wants to be delivered.
///
/// Two cases, because time is not one thing here (ADR-0001 § 7.4): the
/// event-reminder lead is an **absolute duration** and moves with the clock
/// across a daylight-saving change, while the chosen overview time
/// and the 11:00 canteen hint are **wall-clock times** that stay where they
/// are on the dial.
sealed class NotificationTrigger {
  const NotificationTrigger();
}

/// An absolute instant. Resolved into the device zone by the planner and then
/// subject to the delivery window (P7).
@immutable
final class AbsoluteTrigger extends NotificationTrigger {
  const AbsoluteTrigger(this.instant, {this.before});

  final DateTime instant;

  /// What the reminder is about — an event start, a deadline — where it has
  /// one. The delivery window may move [instant], but never onto or past this
  /// moment (`DeliveryWindow.shiftIntoWindowBefore`): a reminder that arrives
  /// after its deadline is worse than one that arrives a little early.
  final DateTime? before;

  @override
  bool operator ==(Object other) =>
      other is AbsoluteTrigger &&
      other.instant == instant &&
      other.before == before;

  @override
  int get hashCode => Object.hash(instant, before);
}

/// A local wall-clock time on a given calendar day.
///
/// [day] is read for its date parts only; its own time and UTC flag are
/// ignored, so a day key built anywhere in the app can be handed over as-is.
@immutable
final class LocalTimeTrigger extends NotificationTrigger {
  const LocalTimeTrigger({
    required this.day,
    required this.hour,
    this.minute = 0,
  });

  final DateTime day;
  final int hour;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is LocalTimeTrigger &&
      other.day.year == day.year &&
      other.day.month == day.month &&
      other.day.day == day.day &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(day.year, day.month, day.day, hour, minute);
}

/// How much of a notification may show before the device is unlocked.
///
/// The only cross-platform guarantee is the **text itself** (ADR-0001 § 7.7):
/// Android's per-notification visibility and iOS's hidden-preview placeholder
/// both bow to a user setting the app does not control. A protection that
/// depends on someone else's switch is not one — so [neutral] means the body
/// was already written without the sensitive part, and the platform hints are
/// a second layer, not the first.
enum NotificationVisibility {
  /// Public campus data — an event title, time and place, a dish name (P9).
  publicContent,

  /// Personal content, aggregated and named without specifics; Moodle is the
  /// reference case (P10).
  neutral,
}

/// One candidate a category contributes to a planning run.
///
/// A request is a **wish**, not a plan: the planner still applies the reader's
/// preferences, the delivery window, the past filter and the budget before
/// anything reaches the operating system.
@immutable
class NotificationRequest {
  const NotificationRequest({
    required this.category,
    required this.target,
    required this.trigger,
    required this.title,
    required this.body,
    this.detail,
    this.visibility = NotificationVisibility.publicContent,
  });

  final NotificationCategory category;

  /// The category's own stable identifier for the thing this is about — a
  /// `CalendarEntry.id`, a `YYYY-MM-DD` day, a `<slug>:<day>` pair.
  ///
  /// Taken over from whatever already identifies the subject rather than
  /// invented here: `CalendarEntry.id` is already stable and source-prefixed
  /// (ADR-0001 § 4.1), and a second identity scheme could only drift from it.
  final String target;

  /// An optional second half of the payload target — what inside [target] the
  /// tap should land on, where the category has such a thing.
  ///
  /// It is deliberately **not** part of [key]. The identity of a notification
  /// is what it is about — one canteen, one day — and that must not change
  /// because a different dish happens to match today. So the key stays
  /// `n3:<slug>:<day>` while the payload carries `<slug>:<day>:<dish>`, and a
  /// reader who taps it lands on the right card.
  ///
  /// Only public content belongs here; it ends up in the operating system's
  /// notification store (ADR-0001 § 7.8). A value containing the payload
  /// separator is dropped rather than escaped — the tap simply falls back to
  /// the day.
  final String? detail;

  final NotificationTrigger trigger;

  /// Already localised, already assembled. The planner never touches text —
  /// it cannot, being a pure function without a `BuildContext`.
  final String title;
  final String body;

  final NotificationVisibility visibility;

  /// The stable scheduling key of ADR-0001 § 7.6, e.g. `n1:savedEvent:4711`.
  ///
  /// Derived rather than stored: key, payload and operating-system id all come
  /// from [category] and [target], so they cannot disagree.
  String get key => '${category.keyPrefix}:$target';

  NotificationPayload get payload => NotificationPayload(
    category: category,
    target: (detail == null || detail!.isEmpty || detail!.contains('|'))
        ? target
        : '$target:$detail',
  );
}
