// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';

import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/week_layout.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEntry _e(
  String id, {
  required int fromH,
  int fromM = 0,
  required int toH,
  int toM = 0,
  bool allDay = false,
}) => CalendarEntry(
  id: id,
  source: CalendarSource.timetable,
  title: id,
  start: DateTime(2026, 5, 12, fromH, fromM),
  end: DateTime(2026, 5, 12, toH, toM),
  allDay: allDay,
);

Map<String, PlacedEntry> _byId(List<PlacedEntry> placed) =>
    <String, PlacedEntry>{for (final PlacedEntry p in placed) p.entry.id: p};

CalendarEntry _utc(
  String id, {
  required int fromH,
  int fromM = 0,
  required int durationMinutes,
}) {
  final DateTime start = DateTime.utc(2026, 5, 12, fromH, fromM);
  return CalendarEntry(
    id: id,
    source: CalendarSource.timetable,
    title: id,
    start: start,
    end: start.add(Duration(minutes: durationMinutes)),
  );
}

void main() {
  group('time zones', () {
    // The API sends absolute instants: `2026-08-04T07:15:00.000Z` is a lecture
    // that starts at 09:15 in Köthen. Every other view runs the value through
    // `toLocal()` before showing it, so the grid has to agree — otherwise the
    // week says 07:15 while the day agenda, the dashboard and the wall clock
    // all say 09:15.
    //
    // Written against `toLocal()` rather than a fixed offset so the expectation
    // holds wherever the suite runs. On a machine in UTC the two coincide and
    // the assertion is trivially true; on any other machine it is the real
    // check, and the device this was found on runs Europe/Berlin.
    test('an entry is placed at its local wall clock, not at UTC', () {
      final CalendarEntry entry = _utc(
        'lecture',
        fromH: 7,
        fromM: 15,
        durationMinutes: 90,
      );
      final DateTime local = entry.start.toLocal();

      final PlacedEntry placed = WeekLayout.placeDay(<CalendarEntry>[
        entry,
      ]).single;

      expect(placed.startMinute, local.hour * 60 + local.minute);
      expect(placed.endMinute, placed.startMinute + 90);
    });

    test('the same instant places identically however it is expressed', () {
      final DateTime instant = DateTime.utc(2026, 5, 12, 7, 15);
      final CalendarEntry asUtc = _utc(
        'a',
        fromH: 7,
        fromM: 15,
        durationMinutes: 60,
      );
      final CalendarEntry asLocal = CalendarEntry(
        id: 'a',
        source: CalendarSource.timetable,
        title: 'a',
        start: instant.toLocal(),
        end: instant.toLocal().add(const Duration(minutes: 60)),
      );

      expect(
        WeekLayout.placeDay(<CalendarEntry>[asUtc]).single.startMinute,
        WeekLayout.placeDay(<CalendarEntry>[asLocal]).single.startMinute,
      );
    });

    test('the week opens on the local hours of its entries', () {
      // P3 (LEVIORA-178): this used to assert `range.startHour == local.hour`
      // exactly, which only holds while the entry sits far enough from
      // midnight. In UTC+14 the same 07:15 UTC entry is 21:15 local, the
      // four-hour minimum window would run past 24:00, and `rangeFor`
      // correctly pulls the start back to 20:00 — a correct result failing a
      // test whose own name is "time zones". The expectation now states what
      // `rangeFor` actually promises: the window contains the entry's local
      // start and is at least the minimum wide.
      final CalendarEntry entry = _utc(
        'lecture',
        fromH: 7,
        fromM: 15,
        durationMinutes: 90,
      );
      final DateTime local = entry.start.toLocal();

      final GridRange range = WeekLayout.rangeFor(<CalendarEntry>[entry]);

      expect(range.startHour, lessThanOrEqualTo(local.hour));
      expect(range.endHour, greaterThan(local.hour));
      expect(range.hourCount, greaterThanOrEqualTo(4));
      // And the window never leaves the day.
      expect(range.startHour, greaterThanOrEqualTo(0));
      expect(range.endHour, lessThanOrEqualTo(24));
    });
  });

  // `rangeFor` no longer decides how much of the day exists — the grid always
  // spans all of it. It decides where the week is scrolled to when it opens.
  group('the hours the week opens on', () {
    test('an empty week still looks like a calendar', () {
      final GridRange range = WeekLayout.rangeFor(const <CalendarEntry>[]);
      expect(range.startHour, 8);
      expect(range.endHour, 18);
      expect(range.hourCount, 10);
    });

    test('spans the entries that exist', () {
      final GridRange range = WeekLayout.rangeFor(<CalendarEntry>[
        _e('a', fromH: 10, toH: 12),
        _e('b', fromH: 14, toH: 16),
      ]);
      expect(range.startHour, 10);
      expect(range.endHour, 16);
    });

    test('an entry ending on the hour does not add an empty row', () {
      final GridRange range = WeekLayout.rangeFor(<CalendarEntry>[
        _e('a', fromH: 9, toH: 13),
      ]);
      expect(range.endHour, 13);
    });

    test('an entry ending mid-hour gets its row', () {
      final GridRange range = WeekLayout.rangeFor(<CalendarEntry>[
        _e('a', fromH: 9, toH: 13, toM: 30),
      ]);
      expect(range.endHour, 14);
    });

    test('never degenerates into a single stripe', () {
      // One 15-minute entry must not produce a grid one row tall.
      final GridRange range = WeekLayout.rangeFor(<CalendarEntry>[
        _e('a', fromH: 10, toH: 10, toM: 15),
      ]);
      expect(range.hourCount, greaterThanOrEqualTo(4));
    });

    test('all-day entries do not stretch the grid', () {
      final GridRange range = WeekLayout.rangeFor(<CalendarEntry>[
        _e('deadline', fromH: 0, toH: 23, allDay: true),
        _e('lecture', fromH: 10, toH: 12),
      ]);
      expect(range.startHour, 10);
      expect(range.endHour, greaterThanOrEqualTo(12));
    });
  });

  group('the day the grid spans', () {
    test('is the whole day, always', () {
      // Not derived from the entries any more: a range that stopped at the
      // last lecture made the evening unreachable, and one that started at the
      // first hid the early morning.
      expect(WeekLayout.fullDay.startHour, 0);
      expect(WeekLayout.fullDay.endHour, 24);
      expect(WeekLayout.fullDay.hourCount, 24);
    });
  });

  group('placing a day', () {
    test('an entry just before midnight keeps a tappable height', () {
      // 23:50 to 23:55 is five minutes at the very bottom of the grid. It may
      // reach past 24:00 — the grid keeps room below the last hour — but it
      // may not be squeezed into a line no thumb can hit.
      final PlacedEntry only = WeekLayout.placeDay(<CalendarEntry>[
        _e('late', fromH: 23, fromM: 50, toH: 23, toM: 55),
      ]).single;

      expect(only.startMinute, 23 * 60 + 50);
      expect(
        only.durationMinutes,
        greaterThanOrEqualTo(WeekLayout.minimumVisibleMinutes),
      );
    });

    test('an entry at midnight starts at the very top', () {
      final PlacedEntry only = WeekLayout.placeDay(<CalendarEntry>[
        _e('nightshift', fromH: 0, toH: 2),
      ]).single;

      expect(only.startMinute, 0);
      expect(only.endMinute, 120);
    });

    test('an entry running past midnight ends at the bottom of its day', () {
      // 22:00 to 02:00 the next morning. Read off the clock alone this ends at
      // minute 120 — before it started — and used to be drawn as a 30-minute
      // box in the small hours of the wrong day.
      final CalendarEntry party = CalendarEntry(
        id: 'party',
        source: CalendarSource.publicCalendar,
        title: 'party',
        start: DateTime(2026, 5, 12, 22),
        end: DateTime(2026, 5, 13, 2),
      );

      final PlacedEntry only = WeekLayout.placeDay(<CalendarEntry>[
        party,
      ]).single;

      expect(only.startMinute, 22 * 60);
      expect(only.endMinute, WeekLayout.minutesPerDay);
    });

    test('a lone entry gets the full width', () {
      final PlacedEntry only = WeekLayout.placeDay(<CalendarEntry>[
        _e('a', fromH: 10, toH: 12),
      ]).single;
      expect(only.lane, 0);
      expect(only.laneCount, 1);
      expect(only.startMinute, 600);
      expect(only.endMinute, 720);
    });

    test('two overlapping entries share the width', () {
      final Map<String, PlacedEntry> placed = _byId(
        WeekLayout.placeDay(<CalendarEntry>[
          _e('a', fromH: 10, toH: 12),
          _e('b', fromH: 11, toH: 13),
        ]),
      );
      expect(placed['a']!.laneCount, 2);
      expect(placed['b']!.laneCount, 2);
      expect(placed['a']!.lane, isNot(placed['b']!.lane));
    });

    test('entries that only touch do not overlap', () {
      // 10–12 and 12–14 are back to back, not simultaneous.
      final Map<String, PlacedEntry> placed = _byId(
        WeekLayout.placeDay(<CalendarEntry>[
          _e('a', fromH: 10, toH: 12),
          _e('b', fromH: 12, toH: 14),
        ]),
      );
      expect(placed['a']!.laneCount, 1);
      expect(placed['b']!.laneCount, 1);
    });

    test('a chain of overlaps is laid out as one group', () {
      // A overlaps B, B overlaps C, A and C do not touch. B cannot be two
      // widths at once, so all three belong to the same group and must agree
      // on how wide that group is — two lanes here, because A and C can share
      // one. What matters is the agreement, not the number.
      final Map<String, PlacedEntry> placed = _byId(
        WeekLayout.placeDay(<CalendarEntry>[
          _e('a', fromH: 10, toH: 12),
          _e('b', fromH: 11, toH: 14),
          _e('c', fromH: 13, toH: 15),
        ]),
      );
      final Set<int> widths = <int>{
        placed['a']!.laneCount,
        placed['b']!.laneCount,
        placed['c']!.laneCount,
      };
      expect(widths, hasLength(1), reason: 'one group, one width');
      expect(widths.single, 2);
      // B is simultaneous with both, so it cannot share their lane.
      expect(placed['b']!.lane, isNot(placed['a']!.lane));
      expect(placed['b']!.lane, isNot(placed['c']!.lane));
    });

    test('a lane is reused once its entry has ended', () {
      final Map<String, PlacedEntry> placed = _byId(
        WeekLayout.placeDay(<CalendarEntry>[
          _e('morning', fromH: 8, toH: 10),
          _e('parallel', fromH: 9, toH: 16),
          _e('afternoon', fromH: 11, toH: 13),
        ]),
      );
      // "afternoon" can take the lane "morning" vacated.
      expect(placed['afternoon']!.lane, placed['morning']!.lane);
    });

    test('a very short entry is still drawn tall enough to hit', () {
      final PlacedEntry only = WeekLayout.placeDay(<CalendarEntry>[
        _e('quick', fromH: 10, toH: 10, toM: 5),
      ]).single;
      expect(
        only.durationMinutes,
        greaterThanOrEqualTo(WeekLayout.minimumVisibleMinutes),
      );
    });

    test('a short visual entry receives an independent 48 dp hit region', () {
      final PlacedEntry only = WeekLayout.placeDay(<CalendarEntry>[
        _e('quick', fromH: 10, toH: 10, toM: 5),
      ]).single;

      final GridHitBounds bounds = WeekLayout.hitBoundsFor(
        only,
        gridStartMinute: 0,
        pixelsPerMinute: 56 / 60,
        minimumExtent: 48,
        gridExtent: 56 * 24 + 28,
      );

      expect(bounds.height, 48);
      expect(bounds.visualTop, greaterThanOrEqualTo(bounds.top));
      expect(bounds.visualBottom, lessThanOrEqualTo(bounds.bottom));
    });

    test('a hit region stays inside the grid at both day edges', () {
      final List<PlacedEntry> placed = WeekLayout.placeDay(<CalendarEntry>[
        _e('early', fromH: 0, toH: 0, toM: 5),
        _e('late', fromH: 23, fromM: 55, toH: 23, toM: 59),
      ]);

      final List<GridHitBounds> bounds = placed
          .map(
            (PlacedEntry entry) => WeekLayout.hitBoundsFor(
              entry,
              gridStartMinute: 0,
              pixelsPerMinute: 56 / 60,
              minimumExtent: 48,
              gridExtent: 56 * 24 + 28,
            ),
          )
          .toList(growable: false);

      expect(bounds.first.top, 0);
      expect(bounds.last.bottom, lessThanOrEqualTo(56 * 24 + 28));
    });

    test('all-day entries are not placed on the grid', () {
      // They belong in the header band, not in a time slot.
      expect(
        WeekLayout.placeDay(<CalendarEntry>[
          _e('deadline', fromH: 0, toH: 23, allDay: true),
        ]),
        isEmpty,
      );
    });

    test('the order is stable for identical starts', () {
      List<String> ids() => WeekLayout.placeDay(<CalendarEntry>[
        _e('b', fromH: 10, toH: 11),
        _e('a', fromH: 10, toH: 11),
      ]).map((PlacedEntry p) => p.entry.id).toList();
      expect(ids(), ids());
    });

    test('an empty day places nothing', () {
      expect(WeekLayout.placeDay(const <CalendarEntry>[]), isEmpty);
    });
  });

  group('weekPlanFor', () {
    final List<DateTime> week = <DateTime>[
      for (int i = 0; i < 5; i++) DateTime(2026, 5, 11 + i),
    ];

    test('the same entries and week are laid out exactly once', () {
      final List<CalendarEntry> entries = <CalendarEntry>[
        _e('vorlesung', fromH: 10, toH: 12),
      ];

      final WeekPlan first = weekPlanFor(entries, week);
      final WeekPlan second = weekPlanFor(entries, <DateTime>[...week]);

      expect(identical(first, second), isTrue);
    });

    test('another week is laid out again', () {
      final List<CalendarEntry> entries = <CalendarEntry>[
        _e('vorlesung', fromH: 10, toH: 12),
      ];
      final List<DateTime> nextWeek = <DateTime>[
        for (int i = 0; i < 5; i++) DateTime(2026, 5, 18 + i),
      ];

      expect(
        identical(weekPlanFor(entries, week), weekPlanFor(entries, nextWeek)),
        isFalse,
      );
      // …and back again, without the previous answer leaking into it.
      expect(weekPlanFor(entries, week).placedOn(week[1]), hasLength(1));
      expect(weekPlanFor(entries, nextWeek).placedOn(nextWeek[1]), isEmpty);
    });

    test('places each entry on its own day and keeps all-day items apart', () {
      final CalendarEntry timed = _e('vorlesung', fromH: 10, toH: 12);
      final CalendarEntry allDay = _e(
        'projektwoche',
        fromH: 0,
        toH: 23,
        allDay: true,
      );

      final WeekPlan plan = weekPlanFor(<CalendarEntry>[timed, allDay], week);

      // 12 May 2026 is the Tuesday of this week.
      expect(
        plan.placedOn(week[1]).map((PlacedEntry p) => p.entry.id),
        <String>['vorlesung'],
      );
      expect(plan.placedOn(week[0]), isEmpty);
      expect(plan.allDay.map((CalendarEntry e) => e.id), <String>[
        'projektwoche',
      ]);
      expect(plan.openingHour, 10);
    });

    test('an entry outside the drawn days decides nothing', () {
      final CalendarEntry offWeek = CalendarEntry(
        id: 'sonntag',
        source: CalendarSource.timetable,
        title: 'sonntag',
        start: DateTime(2026, 5, 17, 6),
        end: DateTime(2026, 5, 17, 7),
      );

      final WeekPlan plan = weekPlanFor(<CalendarEntry>[
        offWeek,
        _e('vorlesung', fromH: 10, toH: 12),
      ], week);

      expect(plan.openingHour, 10);
      expect(
        plan.placedByDay.values.expand((List<PlacedEntry> p) => p).length,
        1,
      );
    });
  });
  group('the minute derivation, against a straightforward reference', () {
    // `placeDay` derives every start and end minute once, up front, and
    // decides "does this end on a later day?" by comparing year, month and day
    // as numbers instead of building two midnight `DateTime`s. Both changes
    // are performance work on the hottest Dart path in the app
    // (`docs/performance-baseline.md`, section 8.1), and both are only allowed
    // to be faster — never to place an entry anywhere else.
    //
    // The guard is therefore not a wall-clock assertion, which would be flaky
    // in CI and meaningless on a build runner. It is an equivalence check
    // against `_reference`, a deliberately naive transcription of the
    // pre-optimisation implementation: same sort, same clustering, same greedy
    // lanes, and the two midnight `DateTime`s that the fast path avoids. If a
    // later change to `placeDay` ever moves an entry, this fails with the
    // entry that moved.

    test('agrees on a semester of generated days', () {
      int count = 0;
      for (int day = 0; day < 120; day++) {
        final List<CalendarEntry> entries = _generatedDay(day);
        count += entries.length;
        _expectSamePlacement(entries, reason: 'generated day $day');
      }
      // A guard that silently stopped generating entries would pass forever.
      expect(count, greaterThan(1000));
    });

    test('agrees across a month boundary', () {
      _expectSamePlacement(<CalendarEntry>[
        _span('night', DateTime(2026, 1, 31, 22), DateTime(2026, 2, 1, 2)),
        _span('short', DateTime(2026, 1, 31, 23), DateTime(2026, 1, 31, 23, 5)),
      ]);
    });

    test('agrees across a year boundary', () {
      _expectSamePlacement(<CalendarEntry>[
        _span('silvester', DateTime(2025, 12, 31, 21), DateTime(2026, 1, 1, 3)),
      ]);
    });

    test('agrees on an entry ending exactly at the next midnight', () {
      // 22:00 to 00:00 is the boundary case of the day comparison: the end
      // instant belongs to the following calendar date, so it is the bottom of
      // this day's column and not minute zero of it.
      _expectSamePlacement(<CalendarEntry>[
        _span('late', DateTime(2026, 5, 12, 22), DateTime(2026, 5, 13)),
      ]);
      expect(
        WeekLayout.placeDay(<CalendarEntry>[
          _span('late', DateTime(2026, 5, 12, 22), DateTime(2026, 5, 13)),
        ]).single.endMinute,
        WeekLayout.minutesPerDay,
      );
    });

    test('agrees where one cluster ends exactly as the next begins', () {
      // Two simultaneous entries make a two-lane cluster. The entry starting
      // exactly when they end belongs to a *new* cluster and keeps the full
      // width — folding it into the previous one would silently halve its box
      // for no reason a reader could see. The greedy lane assignment alone
      // does not notice: it hands out lane 0 either way, and only the width
      // differs.
      final List<CalendarEntry> entries = <CalendarEntry>[
        _e('a', fromH: 10, toH: 12),
        _e('b', fromH: 10, toH: 12),
        _e('c', fromH: 12, toH: 14),
      ];
      _expectSamePlacement(entries);

      final Map<String, PlacedEntry> placed = _byId(
        WeekLayout.placeDay(entries),
      );
      expect(placed['a']!.laneCount, 2);
      expect(placed['b']!.laneCount, 2);
      expect(placed['c']!.laneCount, 1);
    });

    test('agrees on entries expressed in UTC', () {
      _expectSamePlacement(<CalendarEntry>[
        _utc('a', fromH: 7, fromM: 15, durationMinutes: 90),
        _utc('b', fromH: 8, fromM: 0, durationMinutes: 45),
        _utc('c', fromH: 22, fromM: 30, durationMinutes: 300),
      ]);
    });

    test('agrees on an entry without an end', () {
      _expectSamePlacement(<CalendarEntry>[
        CalendarEntry(
          id: 'openEnded',
          source: CalendarSource.moodle,
          title: 'openEnded',
          start: DateTime(2026, 5, 12, 14, 20),
        ),
      ]);
    });

    test('agrees on a day that is nothing but all-day entries', () {
      _expectSamePlacement(<CalendarEntry>[
        _e('a', fromH: 0, toH: 23, allDay: true),
        _e('b', fromH: 0, toH: 23, allDay: true),
      ]);
    });
  });

  group('the shape of the minute derivation', () {
    // The equivalence group above proves `placeDay` still puts every entry
    // where the old code put it. It cannot prove the optimisation is still
    // there: restoring the per-entry `DateTime` construction places every
    // entry identically and leaves the whole mobile suite green, while costing
    // roughly sixty times more (LEVIORA-185). Section 8.1 of
    // `docs/performance-baseline.md` would quietly stop being true.
    //
    // A wall-clock assertion cannot close that gap. Measured across
    // environments, the cost of constructing a local `DateTime` — the very
    // thing the optimisation removed — moves by more than an order of
    // magnitude with the timezone configuration alone: with `TZ` unset the
    // naive reference needs ~2 800 us for a week, with `TZ=Europe/Berlin` (the
    // value CI pins) ~200 us for the identical code. Any threshold, absolute
    // or relative, sits inside that variation and fails on a correct tree.
    //
    // So this asserts the SHAPE instead, the way the icon and `image_url`
    // guards in this repository do: the hot loop must not construct a
    // `DateTime` per entry. That is exactly the invariant section 8.1
    // established, it is decided by reading the source rather than by timing
    // it, and it therefore gives the same verdict on every machine.
    test('placeDay constructs no DateTime per entry', () {
      final String source = File(
        'lib/features/calendar/domain/week_layout.dart',
      ).readAsStringSync();

      final String body = _methodBody(
        source,
        'static List<PlacedEntry> placeDay(',
      );

      // `DateTime.now()`, `DateTime.utc(...)` and a plain `DateTime(...)` all
      // allocate; only the qualified reads (`entry.start.year`) are free. The
      // pattern deliberately does not match `DateTime` used as a type name,
      // which is why it looks for the opening parenthesis.
      final RegExp construction = RegExp(r'\bDateTime\s*(?:\.\w+\s*)?\(');
      final Iterable<Match> found = construction.allMatches(body);

      expect(
        found.map((Match m) => m.group(0)).toList(),
        isEmpty,
        reason:
            'placeDay builds a DateTime again. Constructing a local DateTime '
            'resolves the zone offset backwards and costs microseconds, '
            'against nanoseconds for reading .year/.month/.day — which is why '
            'docs/performance-baseline.md section 8.1 replaced the two '
            'midnight DateTimes with a numeric comparison. Compare the '
            'calendar date field by field instead.',
      );
    });

    test('the guard is reading the real method', () {
      // A rename or a refactor must break this loudly rather than make the
      // check above vacuous: an empty body would pass it for free.
      final String source = File(
        'lib/features/calendar/domain/week_layout.dart',
      ).readAsStringSync();
      final String body = _methodBody(
        source,
        'static List<PlacedEntry> placeDay(',
      );

      expect(body, contains('minimumVisibleMinutes'));
      expect(body, contains('laneEnds'));
      expect(body.length, greaterThan(1000));
    });
  });
}

/// The body of the method whose declaration starts with [signature].
///
/// Brace matching rather than a regular expression: the body contains nested
/// closures and collection literals, and a non-greedy match would stop at the
/// first of them.
String _methodBody(String source, String signature) {
  final int start = source.indexOf(signature);
  if (start < 0) {
    throw StateError(
      'Could not find "$signature" in week_layout.dart. If the method was '
      'renamed, update this guard rather than deleting it — it protects the '
      'optimisation recorded in docs/performance-baseline.md section 8.1.',
    );
  }
  final int open = source.indexOf('{', start);
  int depth = 0;
  for (int i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  throw StateError('Unbalanced braces after "$signature".');
}

/// One deterministic day of entries, built to hit the awkward cases.
///
/// Seeded per day so a failure names a reproducible day rather than a run.
/// The mix is deliberate: identical starts (the sort tie-break), minute-long
/// slots (`minimumVisibleMinutes`), entries into the small hours of the next
/// day (the day comparison), some expressed in UTC as the API sends them, and
/// all-day items that must not reach the grid at all.
List<CalendarEntry> _generatedDay(int dayOffset) {
  int seed = 20260302 + dayOffset * 7919;
  int next(int bound) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % bound;
  }

  final DateTime day = DateTime(2025, 12, 20).add(Duration(days: dayOffset));
  final int howMany = 6 + next(12);
  return List<CalendarEntry>.generate(howMany, (int i) {
    final int startHour = next(24);
    final int startMinute = next(4) * 15;
    final int durationMinutes = switch (next(6)) {
      0 => 1 + next(20), // shorter than the minimum visible height
      1 => 60 * 24 + next(600), // well past midnight
      2 => 60 * (2 + next(8)), // a long block
      _ => 30 + next(4) * 30, // an ordinary slot
    };
    final DateTime start = DateTime(
      day.year,
      day.month,
      day.day,
      startHour,
      startMinute,
    );
    // Identical starts on every third entry, so the tie-break by id is
    // exercised rather than assumed.
    final DateTime tied = i % 3 == 0
        ? DateTime(day.year, day.month, day.day, 9, 0)
        : start;
    final bool asUtc = next(4) == 0;
    return CalendarEntry(
      id: 'd$dayOffset-e${(i * 37) % howMany}-$i',
      source: CalendarSource.values[i % CalendarSource.values.length],
      title: 'entry $i',
      start: asUtc ? tied.toUtc() : tied,
      end: (asUtc ? tied.toUtc() : tied).add(
        Duration(minutes: durationMinutes),
      ),
      allDay: next(9) == 0,
    );
  });
}

CalendarEntry _span(String id, DateTime start, DateTime end) => CalendarEntry(
  id: id,
  source: CalendarSource.publicCalendar,
  title: id,
  start: start,
  end: end,
);

void _expectSamePlacement(List<CalendarEntry> entries, {String? reason}) {
  expect(
    WeekLayout.placeDay(entries).map(_describe).toList(),
    _reference(entries).map(_describe).toList(),
    reason: reason,
  );
}

String _describe(PlacedEntry p) =>
    '${p.entry.id}@${p.startMinute}-${p.endMinute} lane ${p.lane}/${p.laneCount}';

/// The implementation `WeekLayout.placeDay` replaced, kept verbatim.
///
/// Slow on purpose — it re-derives every minute value on every read and builds
/// two `DateTime`s per entry to compare calendar dates. That is exactly what
/// makes it a useful oracle: it owes nothing to the optimisation it checks.
List<PlacedEntry> _reference(Iterable<CalendarEntry> entries) {
  DateTime local(DateTime value) => value.toLocal();

  final List<CalendarEntry> timed =
      entries.where((CalendarEntry e) => !e.allDay).toList()
        ..sort((CalendarEntry a, CalendarEntry b) {
          final int byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
  if (timed.isEmpty) return const <PlacedEntry>[];

  int startOf(CalendarEntry e) {
    final DateTime start = local(e.start);
    return start.hour * 60 + start.minute;
  }

  int endOf(CalendarEntry e) {
    final DateTime start = local(e.start);
    final DateTime end = local(e.end ?? e.start);
    final bool endsOnALaterDay = DateTime(
      end.year,
      end.month,
      end.day,
    ).isAfter(DateTime(start.year, start.month, start.day));
    final int minutes = endsOnALaterDay
        ? WeekLayout.minutesPerDay
        : (end.hour * 60 + end.minute).clamp(0, WeekLayout.minutesPerDay);
    final int earliestVisibleEnd =
        startOf(e) + WeekLayout.minimumVisibleMinutes;
    return minutes < earliestVisibleEnd ? earliestVisibleEnd : minutes;
  }

  final List<PlacedEntry> placed = <PlacedEntry>[];
  List<CalendarEntry> cluster = <CalendarEntry>[];
  int clusterEnd = -1;

  void flush() {
    if (cluster.isEmpty) return;
    final List<int> laneEnds = <int>[];
    final List<int> lanes = <int>[];
    for (final CalendarEntry entry in cluster) {
      int lane = laneEnds.indexWhere((int end) => end <= startOf(entry));
      if (lane == -1) {
        laneEnds.add(endOf(entry));
        lane = laneEnds.length - 1;
      } else {
        laneEnds[lane] = endOf(entry);
      }
      lanes.add(lane);
    }
    for (int i = 0; i < cluster.length; i++) {
      placed.add(
        PlacedEntry(
          entry: cluster[i],
          startMinute: startOf(cluster[i]),
          endMinute: endOf(cluster[i]),
          lane: lanes[i],
          laneCount: laneEnds.length,
        ),
      );
    }
    cluster = <CalendarEntry>[];
    clusterEnd = -1;
  }

  for (final CalendarEntry entry in timed) {
    if (cluster.isNotEmpty && startOf(entry) >= clusterEnd) flush();
    cluster.add(entry);
    final int end = endOf(entry);
    if (end > clusterEnd) clusterEnd = end;
  }
  flush();
  return List<PlacedEntry>.unmodifiable(placed);
}
