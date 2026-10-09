// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/theme/hex_color.dart';
import '../../canteen/data/canteen_models.dart';
import '../../events/domain/event_dedup.dart';
import '../../events/domain/event_source_label.dart';
import '../../events/domain/saved_event_snapshot.dart';
import '../../events/domain/unified_event.dart';
import '../../mail/domain/exchange_calendar_event.dart';
import '../../moodle/domain/moodle_deadline.dart';
import '../../timetable/data/timetable_models.dart';
import '../domain/calendar_entry.dart';
import '../domain/calendar_entry_details.dart';
import '../domain/public_calendar.dart';

/// Pure mapping + aggregation for the cross-source calendar.
///
/// Every source is turned into [CalendarEntry] values by its own mapper, and the
/// lists are merged, deduplicated and sorted here — entirely on-device. No
/// server ever sees the combined set, and one source's data is never derived
/// from another's.

/// Maps a Campus-API timetable to calendar entries.
List<CalendarEntry> timetableToCalendarEntries(
  Timetable timetable, {
  bool Function(TimetableEntry)? include,
}) => <CalendarEntry>[
  for (final TimetableDay day in timetable.days)
    for (final TimetableEntry entry in day.entries)
      if (include == null || include(entry))
        timetableEntryToCalendarEntry(entry),
];

/// Maps one timetable slot.
///
/// Public because the timetable screen shows the very same detail view the
/// calendar does — a second mapper there would be a second answer to what a
/// slot *is*, and the two would drift.
CalendarEntry timetableEntryToCalendarEntry(TimetableEntry entry) {
  final String location = entry.rooms
      .map((TimetableRoom r) => r.label)
      .join(', ');
  final String teachers = entry.teachers
      .map((TimetableTeacher t) => t.label)
      .join(', ');

  return CalendarEntry(
    id: 'timetable:${entry.id}',
    source: CalendarSource.timetable,
    title: entry.displayTitle ?? '',
    start: entry.start,
    end: entry.end,
    subtitle: teachers.isEmpty ? null : teachers,
    location: location.isEmpty ? null : location,
    isCancelled: entry.status == TimetableEntryStatus.cancelled,
    // The flattened fields above are what the agenda draws; this is what the
    // detail sheet needs back — one room per room, not one string.
    details: TimetableCalendarDetails(
      type: entry.type,
      status: entry.status,
      teachers: entry.teachers
          .map((TimetableTeacher t) => t.label)
          .toList(growable: false),
      rooms: entry.rooms
          .map((TimetableRoom r) => r.label)
          .toList(growable: false),
      groups: entry.groups
          .map((TimetableGroup g) => g.shortName)
          .toList(growable: false),
      note: entry.note,
      lessonInfo: entry.lessonInfo,
    ),
  );
}

/// Maps the favourited dishes on one canteen's menu to calendar entries — one
/// per day the dish is served, so a reader who starred "Bulgur-Pfanne" sees it
/// land on their calendar the day it is actually on the board, not every day.
///
/// The exact-name match is the same stability trade-off the canteen feature's
/// own favourites already make (`CanteenFilter.isFavourite`): a dish has no
/// stable id across republishes, only its name.
List<CalendarEntry> canteenFavouriteMealsToCalendarEntries(
  CanteenMenu menu,
  Set<String> favouriteNames,
) => <CalendarEntry>[
  if (favouriteNames.isNotEmpty)
    for (final MenuDay day in menu.days)
      for (final Meal meal in day.meals)
        if (favouriteNames.contains(meal.name))
          CalendarEntry(
            id:
                'canteenFavourite:${menu.canteenSlug}:'
                '${day.date.toIso8601String()}:${meal.name}',
            source: CalendarSource.canteenFavourite,
            title: meal.name,
            start: day.date,
            allDay: true,
            subtitle: menu.displayName,
            sourceLabel: menu.displayName,
            details: CanteenFavouriteMealCalendarDetails(
              canteenName: menu.displayName,
            ),
          ),
];

/// Maps direct-from-Moodle deadlines to calendar entries.
List<CalendarEntry> moodleDeadlinesToCalendarEntries(
  List<MoodleDeadline> deadlines,
) {
  return deadlines
      .map(
        (MoodleDeadline d) => CalendarEntry(
          id: 'moodle:${d.id}',
          source: CalendarSource.moodle,
          title: d.title,
          start: d.dueAt,
          subtitle: d.courseName,
          details: MoodleCalendarDetails(
            courseName: d.courseName,
            moduleName: d.moduleName,
            eventType: d.eventType,
          ),
        ),
      )
      .toList();
}

/// Maps personal Exchange appointments into the local merged calendar. The
/// opaque EWS item id is namespaced and kept on-device; account identifiers,
/// attendees and bodies are never requested or copied into [CalendarEntry].
List<CalendarEntry> exchangeEventsToCalendarEntries(
  List<ExchangeCalendarEvent> events, {
  required String untitledTitle,
}) => events
    .map(
      (ExchangeCalendarEvent event) => CalendarEntry(
        id: 'exchange:${event.id}',
        source: CalendarSource.exchangeCalendar,
        title: event.subject.isEmpty ? untitledTitle : event.subject,
        start: event.isAllDay ? _exchangeAllDayDate(event.start) : event.start,
        end: event.isAllDay ? _exchangeAllDayDate(event.end) : event.end,
        allDay: event.isAllDay,
        location: event.location,
        isCancelled: event.isCancelled,
        details: ExchangeCalendarDetails(location: event.location),
      ),
    )
    .toList(growable: false);

/// The UTC-midnight date marker (see [calendarDayOf]) for one bound of an
/// all-day Exchange appointment.
///
/// Exchange stores an all-day appointment as the midnight that starts its
/// date in the calendar's own zone, and the gateway pins the response zone to
/// UTC — so a mailbox in Köthen answers with 22:00Z (summer) or 23:00Z
/// (winter) the evening before. Read as a date marker that was a day early
/// (F-06). The nearest UTC midnight is that zone's date for every zone from
/// UTC−11 to UTC+12, whatever zone the device is in, and leaves a server that
/// already sends 00:00Z unchanged.
DateTime _exchangeAllDayDate(DateTime value) {
  final DateTime utc = value.toUtc();
  final DateTime midnight = DateTime.utc(utc.year, utc.month, utc.day);
  return utc.difference(midnight) >= const Duration(hours: 12)
      ? DateTime.utc(utc.year, utc.month, utc.day + 1)
      : midnight;
}

/// Maps aggregated public-calendar events to calendar entries, resolving each
/// event's colour and display name from the catalogue (by slug). The colour is
/// only a decorative accent — the calendar name is always carried too.
List<CalendarEntry> publicCalendarEventsToCalendarEntries(
  List<PublicCalendarEvent> events,
  Map<String, PublicCalendar> bySlug,
) {
  return events.map((PublicCalendarEvent e) {
    final PublicCalendar? calendar = bySlug[e.calendarSlug];
    return CalendarEntry(
      id: 'publicCalendar:${e.calendarSlug}:${e.id}',
      source: CalendarSource.publicCalendar,
      title: e.title.isEmpty ? (calendar?.name ?? e.calendarSlug) : e.title,
      start: e.start,
      end: e.end,
      allDay: e.allDay,
      isCancelled: e.status == 'cancelled',
      // The room comes from the ICS LOCATION, the description from DESCRIPTION —
      // both only present when the calendar enables their corresponding import options.
      subtitle: e.description,
      location: e.location,
      calendarSlug: e.calendarSlug,
      sourceLabel: calendar?.name ?? e.calendarSlug,
      colorArgb: parseHexColorArgb(calendar?.colorHex),
      details: PublicCalendarDetails(
        calendarName: calendar?.name ?? e.calendarSlug,
        location: e.location,
        description: e.description,
      ),
    );
  }).toList();
}

/// Maps a saved snapshot ("Meine gemerkten Events") to its calendar entry, so
/// a bookmarked event shows up in the cross-source calendar with its own
/// source and a bookmark to mark it apart from a live entry.
CalendarEntry savedEventSnapshotToCalendarEntry(SavedEventSnapshot snapshot) =>
    CalendarEntry(
      id: 'savedEvent:${snapshot.eventRef}',
      source: CalendarSource.savedEvents,
      title: snapshot.title,
      start: snapshot.start,
      end: snapshot.end,
      allDay: snapshot.allDay,
      calendarSlug: snapshot.calendarSlug,
      colorArgb: snapshot.colorArgb,
      sourceLabel: snapshot.sourceLabel == null
          ? null
          : eventSourceDisplayLabel(
              snapshot.sourceLabel!,
              isChannelSource: snapshot.kind == UnifiedEventKind.postEvent,
            ),
    );

/// The live public-calendar entry's own `eventRef`, in the same
/// `calendar:<id>` form [UnifiedEvent]/[SavedEventSnapshot] use, or `null`
/// when [entry] is not a public-calendar entry. Derived from
/// [CalendarEntry.id] (`publicCalendar:<calendarSlug>:<eventId>`) rather than
/// a second identity field, so the two can never drift apart.
String? _livePublicCalendarEventRef(CalendarEntry entry) {
  if (entry.source != CalendarSource.publicCalendar) return null;
  final String? slug = entry.calendarSlug;
  if (slug == null) return null;
  final String prefix = 'publicCalendar:$slug:';
  if (!entry.id.startsWith(prefix)) return null;
  return 'calendar:${entry.id.substring(prefix.length)}';
}

/// Which saved snapshots still need their own calendar entry, once the ones a
/// live source already shows are dropped — "identische Live-/Merkeinträge
/// erscheinen nur einmal".
///
/// Reuses the events feature's own dedup rule
/// (`event_dedup.isDuplicateCalendarEvent`) rather than a second, UI-side
/// implementation of the same check. A saved snapshot is dropped when:
/// * its `eventRef` names exactly the live public-calendar entry already
///   shown (the common case: a bookmarked calendar occurrence still present
///   live), or
/// * it is a saved event post whose minute-exact start, all-day flag and
///   mapped channel match a live public-calendar entry — the same
///   post-suppresses-calendar-duplicate rule the event overview applies.
///
/// [channelSlugByCalendarSlug] resolves a live public-calendar entry's
/// channel attribution (from the calendar catalogue), the same lookup the
/// event overview performs — the mapping cannot be read off [CalendarEntry]
/// alone.
List<CalendarEntry> savedEventEntriesForCalendar({
  required List<SavedEventSnapshot> saved,
  required List<CalendarEntry> liveEntries,
  required Map<String, String?> channelSlugByCalendarSlug,
}) {
  final Set<String> liveRefs = liveEntries
      .map(_livePublicCalendarEventRef)
      .whereType<String>()
      .toSet();
  final List<UnifiedEvent> livePublicAsUnified = liveEntries
      .where((CalendarEntry e) => e.source == CalendarSource.publicCalendar)
      .map(
        (CalendarEntry e) => UnifiedEvent(
          eventRef: _livePublicCalendarEventRef(e) ?? e.id,
          kind: UnifiedEventKind.calendarEvent,
          title: e.title,
          start: e.start,
          end: e.end,
          allDay: e.allDay,
          channelSlug: e.calendarSlug == null
              ? null
              : channelSlugByCalendarSlug[e.calendarSlug],
          calendarSlug: e.calendarSlug,
        ),
      )
      .toList();

  // The same rule, asked as a lookup rather than once per (snapshot, live
  // entry) pair — see [EventDedupIndex].
  final EventDedupIndex liveByDedupKey = EventDedupIndex(livePublicAsUnified);

  final List<CalendarEntry> out = <CalendarEntry>[];
  for (final SavedEventSnapshot snapshot in saved) {
    if (liveRefs.contains(snapshot.eventRef)) continue;
    if (snapshot.kind == UnifiedEventKind.postEvent &&
        liveByDedupKey.hasCounterpartOf(snapshot.toUnifiedEvent())) {
      continue;
    }
    out.add(savedEventSnapshotToCalendarEntry(snapshot));
  }
  return out;
}

/// Merges entries from any number of sources: deduplicates by [CalendarEntry.id]
/// and returns them sorted ascending by start.
List<CalendarEntry> mergeCalendarEntries(Iterable<CalendarEntry> entries) {
  final Map<String, CalendarEntry> byId = <String, CalendarEntry>{};
  for (final CalendarEntry e in entries) {
    byId[e.id] = e;
  }
  final List<CalendarEntry> merged = byId.values.toList()
    ..sort((CalendarEntry a, CalendarEntry b) => a.start.compareTo(b.start));
  return merged;
}

/// The entries running on [day] (local time), sorted by start.
///
/// "Running on", not "starting on": an examination period or a lecture-free
/// week is one entry that covers a run of days, and someone looking at the
/// third of them expects to see it.
List<CalendarEntry> entriesForDay(List<CalendarEntry> entries, DateTime day) {
  final DateTime key = calendarDayKey(day);
  final List<CalendarEntry> out =
      entries.where((CalendarEntry e) => e.coversDay(key)).toList()..sort(
        (CalendarEntry a, CalendarEntry b) => a.start.compareTo(b.start),
      );
  return out;
}

/// A merged entry list, indexed once by the day each entry starts on.
///
/// [entriesForDay] answers the same question by walking the WHOLE list and
/// asking every entry for its `day` and `lastDay` — two fresh [DateTime]s per
/// entry, per call. The calendar asks it on every rebuild, for the focused day
/// and for the day dashboard, so the walk repeats for a set of entries that
/// has not changed.
///
/// The index keeps the two cases apart, because they are not equally common:
///
/// * an entry that begins and ends on one day is filed under that day, and a
///   lookup is a map read;
/// * an entry that runs across days — an examination period, a lecture-free
///   week, a lecture past midnight — additionally stays in a small separate
///   list that every lookup scans.
///
/// Deliberately no day-by-day expansion of the spanning entries: that would
/// need the same guard against a broken `DTEND` that [calendarEventDays]
/// carries, and would answer a day beyond the guard differently from
/// [entriesForDay]. Scanning the few spanning entries keeps the answer
/// identical for every day, however far out.
class CalendarDayIndex {
  CalendarDayIndex._(this._byStartDay, this._spanning);

  /// Indexes [entries], which are expected in merged (start-ascending) order.
  factory CalendarDayIndex.of(List<CalendarEntry> entries) {
    final Map<DateTime, List<CalendarEntry>> byStartDay =
        <DateTime, List<CalendarEntry>>{};
    final List<CalendarEntry> spanning = <CalendarEntry>[];
    for (final CalendarEntry entry in entries) {
      final DateTime day = entry.day;
      (byStartDay[day] ??= <CalendarEntry>[]).add(entry);
      if (entry.lastDay.isAfter(day)) spanning.add(entry);
    }
    return CalendarDayIndex._(byStartDay, spanning);
  }

  final Map<DateTime, List<CalendarEntry>> _byStartDay;
  final List<CalendarEntry> _spanning;
  final Map<DateTime, List<CalendarEntry>> _forDayCache =
      <DateTime, List<CalendarEntry>>{};

  /// How many entries **start** on each day, keyed exactly as [forDay] keys
  /// its lookup — the week strip's dot and its screen-reader count therefore
  /// name the same day the day list does.
  ///
  /// A spanning entry is counted on its first day only, which is what the dot
  /// has always meant: "something begins here". [forDay] additionally lists an
  /// entry that merely runs through a day; widening the dot to that is a
  /// product decision, not a consequence of the day key.
  late final Map<DateTime, int> countsByStartDay =
      Map<DateTime, int>.unmodifiable(<DateTime, int>{
        for (final MapEntry<DateTime, List<CalendarEntry>> group
            in _byStartDay.entries)
          group.key: group.value.length,
      });

  /// The entries running on [day] (local time), sorted by start — the same
  /// answer [entriesForDay] gives for the indexed list.
  List<CalendarEntry> forDay(DateTime day) {
    final DateTime key = calendarDayKey(day);
    final List<CalendarEntry>? cached = _forDayCache[key];
    if (cached != null) return cached;
    final List<CalendarEntry> starting =
        _byStartDay[key] ?? const <CalendarEntry>[];
    if (_spanning.isEmpty) {
      // Already in start order: the merged list is sorted and grouping keeps
      // that order inside each day.
      final List<CalendarEntry> result = List<CalendarEntry>.unmodifiable(
        starting,
      );
      _forDayCache[key] = result;
      return result;
    }
    final List<CalendarEntry> out = <CalendarEntry>[
      ...starting,
      for (final CalendarEntry entry in _spanning)
        // Anything starting today is already in `starting`.
        if (entry.day != key && entry.coversDay(key)) entry,
    ]..sort((CalendarEntry a, CalendarEntry b) => a.start.compareTo(b.start));
    final List<CalendarEntry> result = List<CalendarEntry>.unmodifiable(out);
    _forDayCache[key] = result;
    return result;
  }
}

/// How many days one entry may contribute to [calendarEventDays].
///
/// A guard, not a product rule: a feed with a broken `DTEND` could otherwise
/// name every day for centuries. Two years is far beyond anything the calendar
/// window shows and far below anything that costs memory.
const int kMaxCalendarEntrySpanDays = 732;

/// The distinct local day keys that have at least one entry.
///
/// A multi-day entry contributes every day it runs on, so the week strip and
/// the month grid mark the whole span rather than only its first day.
Set<DateTime> calendarEventDays(List<CalendarEntry> entries) {
  final Set<DateTime> days = <DateTime>{};
  for (final CalendarEntry entry in entries) {
    final DateTime last = entry.lastDay;
    DateTime cursor = entry.day;
    for (int i = 0; i <= kMaxCalendarEntrySpanDays; i++) {
      days.add(cursor);
      if (!cursor.isBefore(last)) break;
      // Rebuilt from the date parts rather than advanced by a Duration: adding
      // 24 hours across a daylight saving change lands on the same day again.
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
  }
  return days;
}
