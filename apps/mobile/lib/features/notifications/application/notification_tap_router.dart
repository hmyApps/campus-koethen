// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../../../app/app_routes.dart';
import '../../calendar/domain/calendar_entry.dart';
import '../domain/notification_category.dart';
import '../domain/notification_payload.dart';

/// Where a tapped notification takes the reader.
///
/// [resolved] is the honest part: `false` means the app understood the
/// payload but could no longer find what it pointed at, and the destination
/// is the category's fallback. The UI turns that into one quiet line — "the
/// entry is no longer available" — instead of an empty screen the reader has
/// to interpret (UX spec § 6.2).
@immutable
class NotificationTapTarget {
  const NotificationTapTarget({
    required this.location,
    this.focusDay,
    this.focusMealName,
    this.calendarEntry,
    this.resolved = true,
  });

  /// The in-app route. Always one of the existing app routes: no custom URL
  /// scheme, no App Link, no Associated Domain — the notification never
  /// leaves the app to come back in (ADR-0001 § 7.8).
  final String location;

  /// The day the destination should focus, where it has one.
  final DateTime? focusDay;

  /// The dish the canteen screen should mark, by name.
  ///
  /// Optional on purpose, and never a reason to fail: a payload written before
  /// this app version carries no dish, and a dish that is no longer on the
  /// menu simply is not found. Both open the day and mark nothing, which is
  /// the safe fallback the UX spec asks for (§ 6.2).
  final String? focusMealName;

  /// The event whose detail sheet should open after navigating to its day.
  ///
  /// Set only for a successfully resolved `event.reminder`. Carrying the
  /// resolved value avoids a second lookup racing a local data update between
  /// routing and opening the sheet.
  final CalendarEntry? calendarEntry;

  final bool resolved;

  @override
  bool operator ==(Object other) =>
      other is NotificationTapTarget &&
      other.location == location &&
      other.focusDay == focusDay &&
      other.focusMealName == focusMealName &&
      other.calendarEntry == calendarEntry &&
      other.resolved == resolved;

  @override
  int get hashCode =>
      Object.hash(location, focusDay, focusMealName, calendarEntry, resolved);
}

/// Turns the string the operating system handed back into a destination.
///
/// The payload is **never** trusted. It was written by whichever version of
/// the app scheduled the notification, possibly several releases ago, and it
/// has been sitting in the system's notification store ever since. So:
/// parse, validate, map to a known route — and on anything unexpected, fall
/// back rather than guess. An unparsable payload navigates nowhere at all;
/// sending the reader to an arbitrary screen because a string was malformed
/// would be worse than opening where the app normally opens.
class NotificationTapRouter {
  const NotificationTapRouter({
    this.preferredCanteenSlug,
    this.findCalendarEntry,
  });

  /// The canteen the reader currently prefers, used to tell "the hint is for
  /// the canteen you follow" from "you switched canteens since".
  final String? preferredCanteenSlug;

  /// Resolves a `CalendarEntry.id` against the merged event stock
  /// (ADR-0001 § 7.8), or answers `null` when it no longer names anything.
  ///
  /// Injected rather than looked up here, for the same reason the planner
  /// takes its "now" as an argument: it keeps this class a pure mapping from
  /// a string to a destination, testable without a container.
  final CalendarEntry? Function(String id)? findCalendarEntry;

  /// The destination for [raw], or `null` when nothing can be said about it.
  NotificationTapTarget? resolve(String? raw) {
    final NotificationPayload? payload = NotificationPayload.tryParse(raw);
    if (payload == null) return null;
    switch (payload.category) {
      case NotificationCategory.eventReminder:
        // The payload names a `CalendarEntry.id` and nothing else — no day,
        // no route. The day comes from the entry, which means an event moved
        // to another day since the reminder was scheduled still opens on the
        // day it is actually on.
        final CalendarEntry? entry = findCalendarEntry?.call(payload.target);
        if (entry == null) {
          // Understood, but gone: the event left its calendar, the bookmark
          // was deleted, or the reminder outlived the app version that wrote
          // it. The calendar is a correct destination either way; the caller
          // adds the quiet line that says why there is no sheet.
          return const NotificationTapTarget(
            location: AppRoutes.calendar,
            resolved: false,
          );
        }
        return NotificationTapTarget(
          location: AppRoutes.calendar,
          focusDay: entry.day,
          calendarEntry: entry,
        );
      case NotificationCategory.dailySummary:
        final DateTime? day = _parseDay(payload.target);
        if (day == null) {
          return const NotificationTapTarget(
            location: AppRoutes.calendar,
            resolved: false,
          );
        }
        return NotificationTapTarget(
          location: AppRoutes.calendar,
          focusDay: day,
        );
      case NotificationCategory.canteenFavourite:
        // Read left to right, never from the end: the optional dish name is
        // the only part that may itself contain a colon, so anchoring on the
        // last one would cut a dish called "Menü 1: Käsespätzle" in half.
        final RegExpMatch? parts = _canteenTarget.firstMatch(payload.target);
        final DateTime? day = parts == null ? null : _parseDay(parts.group(2)!);
        final String? slug = parts?.group(1);
        // A hint for a canteen the reader has since left is not an error, but
        // it is not resolvable either: the menu on screen would be a different
        // canteen's. Say so instead of showing the wrong dish list.
        if (day == null ||
            (preferredCanteenSlug != null && slug != preferredCanteenSlug)) {
          return const NotificationTapTarget(
            location: AppRoutes.canteen,
            resolved: false,
          );
        }
        return NotificationTapTarget(
          location: AppRoutes.canteen,
          focusDay: day,
          focusMealName: parts!.group(3),
        );
      case NotificationCategory.newMail:
        if (!_mailUid.hasMatch(payload.target)) {
          return const NotificationTapTarget(
            location: AppRoutes.mail,
            resolved: false,
          );
        }
        return const NotificationTapTarget(location: AppRoutes.mail);
    }
  }

  static final RegExp _mailUid = RegExp(r'^\d{1,20}$');

  /// `<slug>:<YYYY-MM-DD>` with an optional `:<dish name>` tail.
  static final RegExp _canteenTarget = RegExp(
    r'^([^:]+):(\d{4}-\d{2}-\d{2})(?::(.+))?$',
  );

  /// `YYYY-MM-DD` to a local midnight day key, or `null`.
  ///
  /// Strict on purpose: `DateTime.tryParse` accepts a great deal more than a
  /// plain date, including time zones and instants, and a payload is exactly
  /// the kind of input that should not be interpreted generously.
  static final RegExp _dayShape = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static DateTime? _parseDay(String value) {
    final RegExpMatch? match = _dayShape.firstMatch(value);
    if (match == null) return null;
    final int year = int.parse(match.group(1)!);
    final int month = int.parse(match.group(2)!);
    final int day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final DateTime parsed = DateTime(year, month, day);
    // Rejects 2026-02-30, which DateTime would happily roll into March.
    if (parsed.month != month || parsed.day != day) return null;
    return parsed;
  }
}

/// Formats a day the way a payload target spells it.
String notificationDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
