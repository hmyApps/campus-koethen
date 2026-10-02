// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../../calendar/application/calendar_merge.dart';
import '../../calendar/domain/calendar_entry.dart';

/// How far ahead the daily overview is planned.
///
/// Fourteen days is not a round number picked for tidiness: it is the length
/// of the canteen menu the API delivers (UX spec § 1.3), and planning past the
/// shortest source would produce overviews that name a day nothing is known
/// about yet. It also sits well inside the budget of
/// `kMaxScheduledNotifications` — at most fourteen of the sixty slots — so the
/// overview can never crowd out the event reminders it shares them with.
const int kDailySummaryHorizonDays = 14;

/// The canteen's contribution to one day, already reduced to what a
/// notification may say about it.
@immutable
class DailySummaryCanteen {
  const DailySummaryCanteen({required this.hasMenu, this.favouriteMealName});

  /// Whether the day has at least one meal on the board. An empty day is a
  /// closed canteen, not a missing menu — `CanteenMenu` states that
  /// explicitly, and a closed canteen contributes nothing.
  final bool hasMenu;

  /// The name of a dish the reader has favourited, when one is on offer.
  final String? favouriteMealName;
}

/// Everything one day's overview is allowed to say, and nothing more.
///
/// Deliberately counts and at most one name per kind. The overview has two
/// lines on a lock screen (UX spec § 5.1.3), and — more importantly — the
/// Moodle part is aggregated **by construction**: there is no field here that
/// could carry a course or an assignment title, so no later change to the text
/// builder can put one on a lock screen (P10, LEVIORA-164).
@immutable
class DailySummaryDay {
  const DailySummaryDay({
    required this.day,
    this.lectureCount = 0,
    this.firstLectureStart,
    this.eventCount = 0,
    this.singleEventTitle,
    this.singleEventStart,
    this.singleEventAllDay = false,
    this.moodleDeadlineCount = 0,
    this.hasCanteenMenu = false,
    this.favouriteMealName,
  });

  /// Local midnight of the day this describes — the same key
  /// [calendarDayKey] produces, and the same one the payload target spells.
  final DateTime day;

  /// Lectures of the selected timetable group that are **not** cancelled.
  ///
  /// A cancelled slot is a locally known change (P12): it is left out rather
  /// than counted, so a day whose only lecture was cancelled is an empty day
  /// and produces no overview at all.
  final int lectureCount;

  /// Start of the earliest lecture, in local time, or `null` when there is
  /// none.
  final DateTime? firstLectureStart;

  /// Relevant events: entries from the activated public calendars plus the
  /// reader's own saved events, deduplicated against each other.
  final int eventCount;

  /// Title of the day's only event. `null` as soon as there are two or more —
  /// the text then names a count instead, which keeps the body inside two
  /// lines whatever the day holds.
  final String? singleEventTitle;
  final DateTime? singleEventStart;
  final bool singleEventAllDay;

  /// How many Moodle deadlines fall on the day. A number and never a title:
  /// see the class comment.
  final int moodleDeadlineCount;

  final bool hasCanteenMenu;
  final String? favouriteMealName;

  /// Whether the day is worth a notification at all.
  ///
  /// A canteen menu is one of the four sources approved for N2. Only a day on
  /// which all four sources are empty may be omitted (ADR-0001 § 7.3 N2).
  bool get hasRelevantEntry =>
      lectureCount > 0 ||
      eventCount > 0 ||
      moodleDeadlineCount > 0 ||
      hasCanteenMenu ||
      favouriteMealName != null;

  /// Whether anything in the day is personal enough to keep off a lock
  /// screen in detail. Only Moodle is, and it is already aggregated — this
  /// drives the platform's own visibility hint as a second layer, never as
  /// the first (see `NotificationVisibility`).
  bool get isSensitive => moodleDeadlineCount > 0;
}

/// Reduces the merged local calendar to one [DailySummaryDay] per day of the
/// planning horizon.
///
/// A **pure function** over values the callers already hold: no provider, no
/// clock, no I/O. The entries are the very same [CalendarEntry] values the
/// calendar screen renders, produced by the same mappers — there is no second
/// copy of the timetable, of the deadlines or of the events anywhere in the
/// notification feature.
///
/// Days are returned in chronological order, including the empty ones; the
/// caller drops those by asking [DailySummaryDay.hasRelevantEntry]. Returning
/// them makes "this day is empty" a testable value rather than an absence.
List<DailySummaryDay> buildDailySummaryDays({
  required DateTime firstDay,
  required List<CalendarEntry> entries,
  Map<DateTime, DailySummaryCanteen> canteenByDay =
      const <DateTime, DailySummaryCanteen>{},
  int horizonDays = kDailySummaryHorizonDays,
}) {
  // Merged and indexed exactly the way the calendar does it, so an entry that
  // runs across days — an examination period, a lecture-free week — appears in
  // every day it covers and not only on the one it starts.
  final CalendarDayIndex index = CalendarDayIndex.of(
    mergeCalendarEntries(entries),
  );
  final DateTime start = calendarDayKey(firstDay);

  return <DailySummaryDay>[
    for (int offset = 0; offset < horizonDays; offset++)
      _summariseDay(
        // Rebuilt from the date parts rather than advanced by a Duration:
        // adding 24 hours across a daylight saving change lands on the same
        // day again, which would plan two overviews for it and none for the
        // next.
        day: DateTime(start.year, start.month, start.day + offset),
        index: index,
        canteenByDay: canteenByDay,
      ),
  ];
}

DailySummaryDay _summariseDay({
  required DateTime day,
  required CalendarDayIndex index,
  required Map<DateTime, DailySummaryCanteen> canteenByDay,
}) {
  int lectures = 0;
  DateTime? firstLecture;
  final List<CalendarEntry> events = <CalendarEntry>[];
  int deadlines = 0;

  for (final CalendarEntry entry in index.forDay(day)) {
    // A cancelled lecture or a cancelled event is not something happening
    // today, in either direction: it neither counts nor makes the day
    // non-empty.
    if (entry.isCancelled) continue;
    switch (entry.source) {
      case CalendarSource.timetable:
        lectures++;
        final DateTime local = entry.start.toLocal();
        if (firstLecture == null || local.isBefore(firstLecture)) {
          firstLecture = local;
        }
      case CalendarSource.moodle:
        deadlines++;
      case CalendarSource.publicCalendar:
      case CalendarSource.postEvent:
      case CalendarSource.savedEvents:
        events.add(entry);
      // Deliberately not summarised: `daily_summary_providers.dart` never
      // feeds this source into the day index in the first place — a
      // favourited dish being on the board is not "something happening
      // today" in the sense P5 (no reminder of its own) was written for.
      case CalendarSource.canteenFavourite:
    }
  }

  final CalendarEntry? onlyEvent = events.length == 1 ? events.first : null;
  final DailySummaryCanteen? canteen = canteenByDay[day];

  return DailySummaryDay(
    day: day,
    lectureCount: lectures,
    firstLectureStart: firstLecture,
    eventCount: events.length,
    singleEventTitle: onlyEvent?.title,
    singleEventStart: onlyEvent == null || onlyEvent.allDay
        ? null
        : onlyEvent.start.toLocal(),
    singleEventAllDay: onlyEvent?.allDay ?? false,
    moodleDeadlineCount: deadlines,
    hasCanteenMenu: canteen?.hasMenu ?? false,
    favouriteMealName: canteen?.favouriteMealName,
  );
}
