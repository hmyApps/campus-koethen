// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'calendar_entry_details.dart';

/// Where a calendar entry originates.
///
/// The set is the single extension point of the cross-source calendar: adding a
/// new source means adding a value here, a mapper to [CalendarEntry], and wiring
/// one contribution in the aggregator. Nothing merges on any server — every
/// source stays in its own feature and is combined only here, on-device.
enum CalendarSource {
  timetable('timetable'),
  moodle('moodle'),
  publicCalendar('public-calendar'),

  /// An event post from `/v1/posts/events`, folded into the calendar as its
  /// own source so it can be deduplicated against a matching
  /// [publicCalendar] entry — see `features/events/domain/event_dedup.dart`.
  postEvent('post-event'),

  /// A locally saved entry from the offline saved-events list.
  savedEvents('saved-events');

  const CalendarSource(this.storageValue);

  /// Stable identifier for local storage, never the enum index.
  final String storageValue;

  static CalendarSource? fromStorage(String? value) {
    for (final CalendarSource source in CalendarSource.values) {
      if (source.storageValue == value) return source;
    }
    return null;
  }
}

/// The sources the classic cross-source calendar merge (timetable, Moodle,
/// public calendars) lets the reader switch on or off individually.
///
/// [CalendarSource.postEvent] and [CalendarSource.savedEvents] are
/// deliberately excluded: they are contributed only by the `events`
/// feature's own aggregation (event overview + saved list), which has its
/// own, separate source-filter preference — see
/// `features/events/application/event_source_filter.dart`.
const List<CalendarSource> kMergeableCalendarSources = <CalendarSource>[
  CalendarSource.timetable,
  CalendarSource.moodle,
  CalendarSource.publicCalendar,
];

/// One unified item on the calendar, independent of its source.
@immutable
class CalendarEntry {
  const CalendarEntry({
    required this.id,
    required this.source,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.subtitle,
    this.location,
    this.isCancelled = false,
    this.calendarSlug,
    this.sourceLabel,
    this.colorArgb,
    this.details,
  });

  final String id;
  final CalendarSource source;
  final String title;

  /// Absolute instant the entry starts.
  final DateTime start;

  /// Absolute instant the entry ends, if it has a duration.
  final DateTime? end;

  final bool allDay;
  final String? subtitle;
  final String? location;

  /// A cancelled timetable slot — conveyed with icon + text, never colour only.
  final bool isCancelled;

  /// For a public-calendar entry: the slug of the calendar it belongs to.
  final String? calendarSlug;

  /// A per-source display label (e.g. the public calendar's name). Combined
  /// with the colour so the source is never distinguished by colour alone.
  final String? sourceLabel;

  /// Optional decorative accent colour (ARGB), e.g. a public calendar's colour.
  /// Never the sole carrier of state — always paired with a label/icon.
  final int? colorArgb;

  /// What the source still knows beyond the flattened fields above.
  ///
  /// Null only for an entry built without them; the agenda never needs it, and
  /// the detail sheet degrades to the flattened fields rather than failing.
  final CalendarEntryDetails? details;

  CalendarEntry copyWithColor(int? colorArgb) => CalendarEntry(
    id: id,
    source: source,
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    subtitle: subtitle,
    location: location,
    isCancelled: isCancelled,
    calendarSlug: calendarSlug,
    sourceLabel: sourceLabel,
    colorArgb: colorArgb,
    details: details,
  );

  static final Expando<DateTime> _dayCache = Expando<DateTime>(
    'calendarEntryDay',
  );
  static final Expando<DateTime> _lastDayCache = Expando<DateTime>(
    'calendarEntryLastDay',
  );

  /// The first calendar day the entry falls on (midnight, local time).
  DateTime get day => _dayCache[this] ??= calendarDayOf(start, allDay: allDay);

  /// The last calendar day the entry falls on.
  ///
  /// Equal to [day] for anything that fits in a day, which is most of what the
  /// app shows. It differs for the entries a university calendar is full of —
  /// an examination period, a lecture-free week — and for a timed entry that
  /// runs past midnight.
  ///
  /// The end is treated as **exclusive**, because both sources say so: an ICS
  /// `DTEND` for an all-day event names the morning after, and a lecture that
  /// ends at midnight has not reached the next day. One microsecond back is
  /// what turns "up to" into "on".
  DateTime get lastDay => _lastDayCache[this] ??= _computeLastDay();

  DateTime _computeLastDay() {
    final DateTime? finish = end;
    if (finish == null || !finish.isAfter(start)) return day;
    return calendarDayOf(
      finish.subtract(const Duration(microseconds: 1)),
      allDay: allDay,
    );
  }

  /// Whether [dayKey] — a value from [calendarDayKey] — is one of the days
  /// this entry runs on.
  bool coversDay(DateTime dayKey) =>
      !dayKey.isBefore(day) && !dayKey.isAfter(lastDay);

  @override
  bool operator ==(Object other) =>
      other is CalendarEntry &&
      other.id == id &&
      other.source == source &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.subtitle == subtitle &&
      other.location == location &&
      other.isCancelled == isCancelled &&
      other.calendarSlug == calendarSlug &&
      other.sourceLabel == sourceLabel &&
      other.colorArgb == colorArgb &&
      other.details == details;

  @override
  int get hashCode => Object.hash(
    id,
    source,
    title,
    start,
    end,
    allDay,
    subtitle,
    location,
    isCancelled,
    calendarSlug,
    sourceLabel,
    colorArgb,
    details,
  );
}

/// Normalises any [DateTime] to a local midnight day key, so entries and the
/// month grid agree on what "the same day" means.
DateTime calendarDayKey(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// The calendar day a source value belongs to.
///
/// A **timed** entry is an absolute instant. The API sends it in UTC, so
/// reading `start.day` straight off it answers a question about London: an
/// entry at 00:30 in Köthen is the previous day in UTC. It has to be converted
/// first — `WeekLayout` and the week grid have always done this, and this is
/// the same rule in one place.
///
/// An **all-day** entry has no instant; it names a calendar date. The worker
/// encodes such a date as UTC midnight precisely so that no device zone can
/// shift it (`ics-parser.ts`: "so no device/UTC-midnight shift is possible"),
/// so it is read back as it was written. Converting it to local time would move
/// it a day in every zone behind UTC. A locally built all-day entry names its
/// date directly and is read the same way, because the getters below follow the
/// value's own `isUtc` flag.
DateTime calendarDayOf(DateTime value, {required bool allDay}) {
  final DateTime reference = allDay ? value : value.toLocal();
  return DateTime(reference.year, reference.month, reference.day);
}
