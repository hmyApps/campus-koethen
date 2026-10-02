// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';

import 'calendar_entry.dart';

/// One entry placed on the time grid.
///
/// [lane] and [laneCount] describe how a group of overlapping entries shares
/// the width of its day column: lane 1 of 3 sits in the middle third.
@immutable
class PlacedEntry {
  const PlacedEntry({
    required this.entry,
    required this.startMinute,
    required this.endMinute,
    required this.lane,
    required this.laneCount,
  });

  final CalendarEntry entry;

  /// Minutes since midnight.
  final int startMinute;
  final int endMinute;

  final int lane;
  final int laneCount;

  int get durationMinutes => endMinute - startMinute;
}

/// The vertical extent the grid has to draw.
@immutable
class GridRange {
  const GridRange({required this.startHour, required this.endHour});

  final int startHour;
  final int endHour;

  int get hourCount => endHour - startHour;
}

/// The independently actionable area around one visual grid entry.
///
/// A short appointment must keep its truthful duration on the time axis, but
/// that visual rectangle is often smaller than a finger. This model separates
/// the two rectangles: [visualTop] and [visualBottom] locate the card, while
/// [top] and [bottom] locate the (possibly larger) semantic and pointer target.
@immutable
class GridHitBounds {
  const GridHitBounds({
    required this.top,
    required this.height,
    required this.visualTop,
    required this.visualHeight,
  });

  final double top;
  final double height;
  final double visualTop;
  final double visualHeight;

  double get bottom => top + height;
  double get visualBottom => visualTop + visualHeight;
  double get visualOffset => visualTop - top;
}

/// Turns a day's entries into positioned boxes.
///
/// Everything here is arithmetic on minutes, deliberately kept out of the
/// widget: overlap handling is the only genuinely tricky part of a week grid,
/// and it is far easier to get right — and to keep right — as a pure function
/// with tests than as a layout side effect.
///
/// **Every reading of a clock here goes through [_local] first.** The API sends
/// absolute instants, so `entry.start.hour` is the hour in UTC — two hours off
/// in a German summer, one in winter, arbitrary abroad. Every other view
/// formats via `toLocal()`, and a grid that disagreed with the day agenda about
/// when a lecture starts would be worse than no grid.
abstract final class WeekLayout {
  static DateTime _local(DateTime value) => value.toLocal();

  /// A lecture shorter than this is still drawn this tall, so a 15-minute slot
  /// stays readable and tappable instead of collapsing to a line.
  static const int minimumVisibleMinutes = 30;

  /// Minutes in a day — the bottom edge of the grid.
  static const int minutesPerDay = 24 * 60;

  /// The hours the grid draws: the whole day, always.
  ///
  /// The grid used to span only the hours that happened to hold entries, which
  /// on a small phone left part of the day unreachable and hid anything
  /// outside the range entirely. A day is 00:00 to 24:00 wherever you look at
  /// it, so the grid draws all of it and lets the reader scroll.
  static const GridRange fullDay = GridRange(startHour: 0, endHour: 24);

  /// Calculates a minimum-size target around an entry without stretching the
  /// card that communicates its actual duration.
  ///
  /// The target is centred on the visual card where possible and clamped to
  /// the grid at midnight. Neighbouring targets may overlap in a dense lane;
  /// they remain distinct focus/semantics nodes, while the calendar's day and
  /// list views provide the equivalent non-spatial interaction.
  static GridHitBounds hitBoundsFor(
    PlacedEntry entry, {
    required int gridStartMinute,
    required double pixelsPerMinute,
    required double minimumExtent,
    required double gridExtent,
  }) {
    final double visualTop =
        (entry.startMinute - gridStartMinute) * pixelsPerMinute;
    final double visualHeight = entry.durationMinutes * pixelsPerMinute;
    final double height = visualHeight
        .clamp(minimumExtent, gridExtent)
        .toDouble();
    final double desiredTop = visualTop - (height - visualHeight) / 2;
    final double top = desiredTop
        .clamp(0.0, (gridExtent - height).clamp(0.0, gridExtent))
        .toDouble();
    return GridHitBounds(
      top: top,
      height: height,
      visualTop: visualTop,
      visualHeight: visualHeight,
    );
  }

  /// The hours worth showing *first*, derived from the entries.
  ///
  /// The grid itself always spans [fullDay]; this is only where it is scrolled
  /// to when it appears, so a reader whose week starts at 10:00 does not open
  /// on empty night hours. Falls back to the teaching day when there is
  /// nothing to show. Always covers whole hours, and never fewer than
  /// [minimumHours] so the anchor cannot degenerate into a single stripe.
  static GridRange rangeFor(
    Iterable<CalendarEntry> entries, {
    int defaultStartHour = 8,
    int defaultEndHour = 18,
    int minimumHours = 4,
  }) {
    final List<CalendarEntry> timed = entries
        .where((CalendarEntry e) => !e.allDay)
        .toList();
    if (timed.isEmpty) {
      return GridRange(startHour: defaultStartHour, endHour: defaultEndHour);
    }

    int earliest = 24;
    int latest = 0;
    for (final CalendarEntry entry in timed) {
      final int start = _local(entry.start).hour;
      final DateTime end = _local(entry.end ?? entry.start);
      // An entry ending exactly on the hour does not need the next row.
      final int endHour = end.minute == 0 ? end.hour : end.hour + 1;
      if (start < earliest) earliest = start;
      if (endHour > latest) latest = endHour;
    }
    earliest = earliest.clamp(0, 23);
    latest = latest.clamp(1, 24);
    if (latest - earliest < minimumHours) {
      latest = (earliest + minimumHours).clamp(1, 24);
      if (latest - earliest < minimumHours) {
        earliest = (latest - minimumHours).clamp(0, 23);
      }
    }
    return GridRange(startHour: earliest, endHour: latest);
  }

  /// Places one day's timed entries, splitting overlaps into lanes.
  ///
  /// Entries that overlap in time share the column width. The grouping is by
  /// *cluster*: A overlapping B and B overlapping C puts all three in one
  /// group even when A and C do not touch, because otherwise B would have to
  /// be in two widths at once.
  ///
  /// **Every clock reading happens once per entry, up front.** This used to be
  /// the most expensive Dart work in the whole app, and none of it was the
  /// layout: a start and an end minute were re-derived on every read, and
  /// deciding whether an entry ended on a later day built two midnight
  /// `DateTime`s each time. Constructing a *local* `DateTime` resolves the
  /// zone offset backwards and costs microseconds — some six hundred times a
  /// component getter — so with the clustering loop, the lane assignment and
  /// the [PlacedEntry] construction each asking again, a week of entries paid
  /// for that construction six times over per entry.
  ///
  /// Both numbers are therefore derived once into [starts] and [ends], and the
  /// day comparison is done on year, month and day as integers: local midnight
  /// of a later date is always the later instant, so the answer is the same
  /// without allocating anything. What is left below is plain integer
  /// arithmetic. Measured with `benchmark/hot_paths_test.dart`, laying out a
  /// week went from 3,2 ms to 0,02 ms — see `docs/performance-baseline.md`
  /// section 8.1.
  static List<PlacedEntry> placeDay(Iterable<CalendarEntry> entries) {
    final List<CalendarEntry> timed =
        entries.where((CalendarEntry e) => !e.allDay).toList()
          ..sort((CalendarEntry a, CalendarEntry b) {
            final int byStart = a.start.compareTo(b.start);
            return byStart != 0 ? byStart : a.id.compareTo(b.id);
          });
    if (timed.isEmpty) return const <PlacedEntry>[];

    final int count = timed.length;
    final List<int> starts = List<int>.filled(count, 0);
    final List<int> ends = List<int>.filled(count, 0);
    for (int i = 0; i < count; i++) {
      final CalendarEntry entry = timed[i];
      final DateTime start = _local(entry.start);
      final DateTime end = _local(entry.end ?? entry.start);
      final int startMinute = start.hour * 60 + start.minute;
      // An entry running past midnight ends at the bottom of its own day: the
      // week draws one column per day and has no row below 24:00 to continue
      // into. Decided on the calendar date, not on the clock — a party ending
      // at 02:00 reads as minute 120, which is *before* it started, and would
      // otherwise be drawn as a 30-minute box in the small hours.
      //
      // Compared field by field rather than by building two midnight
      // `DateTime`s: local midnight of a later date is always the later
      // instant, so the two answers agree, and this one costs no allocation
      // and no second zone lookup.
      final bool endsOnALaterDay = end.year != start.year
          ? end.year > start.year
          : (end.month != start.month
                ? end.month > start.month
                : end.day > start.day);
      final int endMinute = endsOnALaterDay
          ? minutesPerDay
          : (end.hour * 60 + end.minute).clamp(0, minutesPerDay);
      // The minimum wins even at the very end of the day: an entry at 23:50
      // may reach a little past 24:00 rather than shrink to a line no thumb
      // can hit. The grid reserves the room for it below the last hour.
      final int earliestVisibleEnd = startMinute + minimumVisibleMinutes;
      starts[i] = startMinute;
      ends[i] = endMinute < earliestVisibleEnd ? earliestVisibleEnd : endMinute;
    }

    final List<PlacedEntry> placed = <PlacedEntry>[];
    // Reused across clusters instead of reallocated per cluster: a day of
    // back-to-back lectures is a long run of one-entry clusters.
    final List<int> lanes = List<int>.filled(count, 0);
    final List<int> laneEnds = <int>[];
    int clusterStart = 0;
    int clusterEnd = -1;

    void flush(int endExclusive) {
      if (endExclusive <= clusterStart) return;
      laneEnds.clear();
      // Greedy lane assignment: reuse the first lane whose last entry ended.
      for (int i = clusterStart; i < endExclusive; i++) {
        int lane = -1;
        for (int l = 0; l < laneEnds.length; l++) {
          if (laneEnds[l] <= starts[i]) {
            lane = l;
            break;
          }
        }
        if (lane == -1) {
          laneEnds.add(ends[i]);
          lane = laneEnds.length - 1;
        } else {
          laneEnds[lane] = ends[i];
        }
        lanes[i] = lane;
      }
      // The width is only known once the whole cluster has a lane.
      final int laneCount = laneEnds.length;
      for (int i = clusterStart; i < endExclusive; i++) {
        placed.add(
          PlacedEntry(
            entry: timed[i],
            startMinute: starts[i],
            endMinute: ends[i],
            lane: lanes[i],
            laneCount: laneCount,
          ),
        );
      }
    }

    for (int i = 0; i < count; i++) {
      if (i > clusterStart && starts[i] >= clusterEnd) {
        flush(i);
        clusterStart = i;
        clusterEnd = -1;
      }
      if (ends[i] > clusterEnd) clusterEnd = ends[i];
    }
    flush(count);
    return List<PlacedEntry>.unmodifiable(placed);
  }
}

/// One drawn week, laid out.
///
/// Everything the week grid needs to paint: which entries land on which day,
/// which of them are all-day, where they sit on the hour axis, and which hour
/// the view should open on.
@immutable
class WeekPlan {
  const WeekPlan({
    required this.days,
    required this.allDay,
    required this.placedByDay,
    required this.openingHour,
  });

  /// The drawn days, in order — the key of [placedByDay].
  final List<DateTime> days;

  /// The all-day entries of the whole week, in merged order. They have no
  /// place on a time axis and get their own band.
  final List<CalendarEntry> allDay;

  final Map<DateTime, List<PlacedEntry>> placedByDay;

  /// The hour the grid scrolls to when it appears. The grid itself always
  /// spans [WeekLayout.fullDay].
  final int openingHour;

  List<PlacedEntry> placedOn(DateTime day) =>
      placedByDay[day] ?? const <PlacedEntry>[];
}

class _CachedPlan {
  const _CachedPlan(this.days, this.plan);

  final List<DateTime> days;
  final WeekPlan plan;
}

/// One cached plan per entry-list instance.
///
/// The grid draws one week at a time, so a single slot per list is enough and
/// cannot grow: switching week overwrites it, and a fresh merge produces a new
/// list that gets its own slot.
final Expando<_CachedPlan> _planCache = Expando<_CachedPlan>('weekPlan');

/// The layout of [days] out of [entries].
///
/// Memoised because none of this depends on the constraints or on anything a
/// rebuild changes: assigning a month's worth of merged entries to the drawn
/// days, and clustering each day into lanes, used to run again on every build
/// of the grid — a tap on a day header, the weekend switch, a theme or text
/// size change, any change to any calendar source.
WeekPlan weekPlanFor(List<CalendarEntry> entries, List<DateTime> days) {
  final _CachedPlan? cached = _planCache[entries];
  if (cached != null && listEquals(cached.days, days)) return cached.plan;
  final WeekPlan plan = _buildPlan(entries, days);
  _planCache[entries] = _CachedPlan(List<DateTime>.unmodifiable(days), plan);
  return plan;
}

WeekPlan _buildPlan(List<CalendarEntry> entries, List<DateTime> days) {
  // Entries outside the drawn days are dropped here rather than in the
  // caller: the opening hour has to come from what is actually on screen, or
  // a hidden Sunday morning would decide where every weekday opens.
  final Map<DateTime, List<CalendarEntry>> entriesByDay =
      <DateTime, List<CalendarEntry>>{
        for (final DateTime day in days) day: <CalendarEntry>[],
      };
  final Map<DateTime, DateTime> dayKeyToDay = <DateTime, DateTime>{
    for (final DateTime day in days) calendarDayKey(day): day,
  };
  final List<CalendarEntry> visible = <CalendarEntry>[];
  for (final CalendarEntry entry in entries) {
    if (entry.allDay) {
      bool onAny = false;
      for (final MapEntry<DateTime, DateTime> dk in dayKeyToDay.entries) {
        if (entry.coversDay(dk.key)) {
          entriesByDay[dk.value]!.add(entry);
          onAny = true;
        }
      }
      if (onAny) visible.add(entry);
    } else {
      final DateTime? matchingDay = dayKeyToDay[entry.day];
      if (matchingDay != null) {
        entriesByDay[matchingDay]!.add(entry);
        visible.add(entry);
      }
    }
  }

  return WeekPlan(
    days: List<DateTime>.unmodifiable(days),
    allDay: List<CalendarEntry>.unmodifiable(
      visible.where((CalendarEntry e) => e.allDay),
    ),
    placedByDay: <DateTime, List<PlacedEntry>>{
      for (final DateTime day in days)
        day: WeekLayout.placeDay(entriesByDay[day]!),
    },
    openingHour: WeekLayout.rangeFor(visible).startHour,
  );
}
