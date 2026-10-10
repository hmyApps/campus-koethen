// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:timezone/timezone.dart' as tz;

/// The approved delivery window, 07:00–20:00 local time (P7).
///
/// Both bounds are **inclusive**. 07:00:00 and 20:00:00 are inside the window;
/// that convention makes the rule single-valued and is an architecture
/// decision for unambiguity, not a product rule of its own
/// (ADR-0001 § 7.4).
abstract final class DeliveryWindow {
  static const int startHour = 7;
  static const int endHour = 20;

  /// Whether [moment] lies inside the window.
  static bool allows(tz.TZDateTime moment) {
    if (moment.hour < startHour) return false;
    if (moment.hour > endHour) return false;
    if (moment.hour == endHour) {
      // 20:00:00 exactly is allowed; 20:00:01 is not.
      return moment.minute == 0 &&
          moment.second == 0 &&
          moment.millisecond == 0 &&
          moment.microsecond == 0;
    }
    return true;
  }

  /// The moment [desired] is actually delivered at, per P7.
  ///
  /// ```text
  /// inside the window        → unchanged
  /// before 07:00             → 07:00 of the same day
  /// after 20:00              → 07:00 of the next day
  /// ```
  ///
  /// The rule is total and single-valued: every input has exactly one result.
  /// It only ever moves a moment **forward** and knows nothing about what the
  /// reminder is about, so on its own it can push a short lead past its
  /// target: a deadline at 23:59 with a one-hour lead wants 22:59, and the
  /// next 07:00 is after the deadline. A reminder with a target therefore
  /// uses [shiftIntoWindowBefore].
  ///
  /// The result is rebuilt through the [tz.TZDateTime] constructor rather than
  /// by adding a `Duration`, so a shift across a daylight-saving change lands
  /// on 07:00 on the dial instead of 06:00 or 08:00.
  static tz.TZDateTime shiftIntoWindow(tz.TZDateTime desired) {
    if (allows(desired)) return desired;
    final tz.Location location = desired.location;
    if (desired.hour < startHour) {
      return tz.TZDateTime(
        location,
        desired.year,
        desired.month,
        desired.day,
        startHour,
      );
    }
    return tz.TZDateTime(
      location,
      desired.year,
      desired.month,
      desired.day + 1,
      startHour,
    );
  }

  /// [shiftIntoWindow], but never onto or past [target] — the event start or
  /// the deadline the reminder is about.
  ///
  /// ```text
  /// shifted moment before target → the shifted moment
  /// otherwise                    → the latest 20:00 strictly before target
  /// ```
  ///
  /// For a target after 20:00 the fallback is 20:00 the same evening; for a
  /// target at or before 20:00 it is 20:00 the evening before. It only ever
  /// moves a reminder **earlier** than the reader asked for, never later, and
  /// it is always inside the window. It may lie in the past; dropping it then
  /// is the caller's job, exactly as for every other moment.
  ///
  /// Like [shiftIntoWindow], the result is built from the date parts, so the
  /// fallback is 20:00 on the dial on a daylight-saving day too.
  static tz.TZDateTime shiftIntoWindowBefore(
    tz.TZDateTime desired,
    DateTime target,
  ) {
    final tz.TZDateTime shifted = shiftIntoWindow(desired);
    final tz.Location location = desired.location;
    final tz.TZDateTime bound = tz.TZDateTime.from(target, location);
    if (shifted.isBefore(bound)) return shifted;
    final tz.TZDateTime sameEvening = tz.TZDateTime(
      location,
      bound.year,
      bound.month,
      bound.day,
      endHour,
    );
    if (sameEvening.isBefore(bound)) return sameEvening;
    return tz.TZDateTime(
      location,
      bound.year,
      bound.month,
      bound.day - 1,
      endHour,
    );
  }
}
