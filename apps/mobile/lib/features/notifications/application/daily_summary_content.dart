// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/locale/formatters.dart';
import '../../../l10n/l10n.dart';
import '../domain/notification_category.dart';
import '../domain/notification_request.dart';
import 'daily_summary.dart';
import 'notification_tap_router.dart';

/// Turns one day's [DailySummaryDay] into the notification the reader sees, or
/// into `null` when the day has nothing worth waking up for.
///
/// Separate from both the aggregation and the planner, and for the same
/// reason each of those is separate: this is the only place that knows a
/// language exists. The planner is a pure function without a `BuildContext`
/// and never touches text, and [buildDailySummaryDays] never sees one either.
///
/// Two rules are enforced here rather than trusted:
///
/// * **Moodle stays aggregated.** [DailySummaryDay] carries a count and no
///   title, so the body cannot name a course or an assignment even by
///   accident (P10). The visible text is the neutral one in both languages;
///   the full detail lives behind the tap, inside the app.
/// * **Two lines, at most four parts.** Lectures, events, Moodle, canteen —
///   each contributes one short fragment or none, and a crowded day says
///   "5 Termine" rather than listing five titles (UX spec § 5.1.3).
NotificationRequest? dailySummaryRequest({
  required DailySummaryDay day,
  required AppLocalizations l10n,
  required String localeCode,
  int deliveryMinutes = 8 * 60,
}) {
  if (!day.hasRelevantEntry) return null;

  final List<String> parts = <String>[
    if (day.lectureCount > 0) _lectures(day, l10n, localeCode),
    if (day.eventCount > 0) _events(day, l10n, localeCode),
    if (day.moodleDeadlineCount > 0)
      l10n.notificationDailySummaryMoodle(day.moodleDeadlineCount),
    ?_canteen(day, l10n),
  ];
  // `hasRelevantEntry` guarantees at least one part, so the join below always
  // has something to work with.
  return NotificationRequest(
    category: NotificationCategory.dailySummary,
    target: notificationDayKey(day.day),
    trigger: LocalTimeTrigger(
      day: day.day,
      hour: deliveryMinutes ~/ 60,
      minute: deliveryMinutes % 60,
    ),
    title: l10n.notificationDailySummaryTitle,
    body: l10n.notificationDailySummaryBody(_join(parts, l10n)),
    // A second layer only: the body above is already free of anything a
    // course or an assignment could be recognised by.
    visibility: day.isSensitive
        ? NotificationVisibility.neutral
        : NotificationVisibility.publicContent,
  );
}

String _lectures(
  DailySummaryDay day,
  AppLocalizations l10n,
  String localeCode,
) {
  final String count = l10n.notificationDailySummaryLectures(day.lectureCount);
  final DateTime? first = day.firstLectureStart;
  if (first == null) return count;
  return l10n.notificationDailySummaryLecturesFirstAt(
    count,
    AppDateFormats.time(first, localeCode),
  );
}

String _events(DailySummaryDay day, AppLocalizations l10n, String localeCode) {
  final String? title = day.singleEventTitle;
  if (title == null) {
    return l10n.notificationDailySummaryEvents(day.eventCount);
  }
  final DateTime? start = day.singleEventStart;
  if (start == null) return l10n.notificationDailySummaryEventAllDay(title);
  return l10n.notificationDailySummaryEventAt(
    title,
    AppDateFormats.time(start, localeCode),
  );
}

String? _canteen(DailySummaryDay day, AppLocalizations l10n) {
  final String? favourite = day.favouriteMealName;
  if (favourite != null) {
    return l10n.notificationDailySummaryCanteenFavourite(favourite);
  }
  // A plain menu is one of the four N2 sources, so it earns the day an
  // overview even on its own — see [DailySummaryDay.hasRelevantEntry].
  if (day.hasCanteenMenu) return l10n.notificationDailySummaryCanteenMenu;
  return null;
}

/// `A`, `A und B`, `A, B und C` — the conjunction comes from the ARB file, so
/// each language keeps its own punctuation without a rule in Dart.
String _join(List<String> parts, AppLocalizations l10n) {
  if (parts.length == 1) return parts.first;
  return l10n.notificationDailySummaryJoin(
    parts.sublist(0, parts.length - 1).join(', '),
    parts.last,
  );
}
