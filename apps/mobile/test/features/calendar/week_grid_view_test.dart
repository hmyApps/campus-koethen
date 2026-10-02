// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/theme/app_dimensions.dart';
import 'package:campus_koethen/core/theme/contrast.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/week_layout.dart';
import 'package:campus_koethen/features/calendar/presentation/calendar_entry_sheet.dart';
import 'package:campus_koethen/features/calendar/presentation/week_grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

final DateTime _monday = DateTime(2026, 5, 11);

CalendarEntry _allDay(String title, {int dayOffset = 0}) {
  final DateTime day = _monday.add(Duration(days: dayOffset));
  return CalendarEntry(
    id: title,
    source: CalendarSource.publicCalendar,
    title: title,
    start: DateTime(day.year, day.month, day.day),
    end: DateTime(day.year, day.month, day.day, 23, 59),
    allDay: true,
  );
}

CalendarEntry _entry({
  required String title,
  required int dayOffset,
  required int fromH,
  int fromM = 0,
  required int toH,
  int toM = 0,
  int? colorArgb,
}) {
  final DateTime day = _monday.add(Duration(days: dayOffset));
  return CalendarEntry(
    id: title,
    source: CalendarSource.publicCalendar,
    title: title,
    start: DateTime(day.year, day.month, day.day, fromH, fromM),
    end: DateTime(day.year, day.month, day.day, toH, toM),
    colorArgb: colorArgb,
  );
}

Future<void> pumpGrid(
  WidgetTester tester,
  List<CalendarEntry> entries, {
  TextScaler textScaler = TextScaler.noScaling,
  int dayCount = 5,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await pumpScreen(
    tester,
    Scaffold(
      body: WeekGridView(
        weekStart: _monday,
        entries: entries,
        today: _monday,
        selected: _monday,
        dayCount: dayCount,
        onSelectDay: (DateTime _) {},
      ),
    ),
    textScaler: textScaler,
  );
  await tester.pumpAndSettle();
}

/// The day headers the grid currently draws, in order.
List<String> _headers(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .where((String s) => RegExp(r'^\w+\.? \d+$').hasMatch(s))
    .toList(growable: false);

/// The height one line of this text needs at the width it was actually given.
double _neededHeight(WidgetTester tester, String title) {
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    find.text(title),
  );
  return paragraph.getMinIntrinsicHeight(paragraph.size.width);
}

void main() {
  testWidgets('layout matrix keeps the week grid stable', (
    WidgetTester tester,
  ) async {
    for (final (Size size, TextScaler scaler) in <(Size, TextScaler)>[
      (const Size(320, 800), TextScaler.noScaling),
      (const Size(360, 800), const TextScaler.linear(1.3)),
      (const Size(800, 360), TextScaler.noScaling),
      (const Size(320, 1000), const TextScaler.linear(2)),
    ]) {
      await pumpGrid(tester, <CalendarEntry>[], size: size, textScaler: scaler);

      expect(_headers(tester), hasLength(5));
      expect(tester.takeException(), isNull, reason: '$size at $scaler');
    }
  });

  group('calendar colours', () {
    testWidgets('a timed event uses its calendar colour', (
      WidgetTester tester,
    ) async {
      const int calendarColor = 0xFF2E7D32;
      await pumpGrid(tester, <CalendarEntry>[
        _entry(
          title: 'Grüner Kalendertermin',
          dayOffset: 0,
          fromH: 10,
          toH: 11,
          colorArgb: calendarColor,
        ),
      ]);

      final Card card = tester.widget<Card>(
        find.ancestor(
          of: find.text('Grüner Kalendertermin'),
          matching: find.byType(Card),
        ),
      );
      expect(card.color, const Color(calendarColor));
      final Text title = tester.widget<Text>(
        find.text('Grüner Kalendertermin'),
      );
      expect(
        Contrast.ratio(title.style!.color!, const Color(calendarColor)),
        greaterThanOrEqualTo(Contrast.aaBody),
      );
    });

    testWidgets('an all-day event uses its calendar colour', (
      WidgetTester tester,
    ) async {
      const int calendarColor = 0xFF6A1B9A;
      final CalendarEntry entry = CalendarEntry(
        id: 'purple-all-day',
        source: CalendarSource.publicCalendar,
        title: 'Violetter Ganztagstermin',
        start: _monday,
        end: _monday.add(const Duration(days: 1)),
        allDay: true,
        colorArgb: calendarColor,
      );

      await pumpGrid(tester, <CalendarEntry>[entry]);

      final ActionChip chip = tester.widget<ActionChip>(
        find.ancestor(
          of: find.text('Violetter Ganztagstermin'),
          matching: find.byType(ActionChip),
        ),
      );
      expect(chip.backgroundColor, const Color(calendarColor));
      expect(
        Contrast.ratio(
          (chip.label as Text).style!.color!,
          const Color(calendarColor),
        ),
        greaterThanOrEqualTo(Contrast.aaBody),
      );
    });
  });

  group('the week the grid draws', () {
    testWidgets('is Monday to Friday by default', (WidgetTester tester) async {
      // Two empty weekend columns cost a fifth of the width of a phone.
      await pumpGrid(tester, <CalendarEntry>[]);

      expect(_headers(tester), hasLength(5));
      expect(_headers(tester).first, contains('11'));
      expect(_headers(tester).last, contains('15'));
    });

    testWidgets('runs to Sunday when the weekend is switched on', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester, <CalendarEntry>[], dayCount: 7);

      expect(_headers(tester), hasLength(7));
      expect(_headers(tester).last, contains('17'));
    });

    testWidgets('a Saturday entry is not drawn in the work week', (
      WidgetTester tester,
    ) async {
      // Not just hidden columns: an entry outside the drawn days must not land
      // in a neighbouring one.
      await pumpGrid(tester, <CalendarEntry>[
        _entry(title: 'Samstagstermin', dayOffset: 5, fromH: 10, toH: 11),
        _entry(title: 'Freitagstermin', dayOffset: 4, fromH: 10, toH: 11),
      ]);

      expect(find.text('Samstagstermin'), findsNothing);
      expect(find.text('Freitagstermin'), findsOneWidget);
    });

    testWidgets('and is drawn once the weekend is on', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester, <CalendarEntry>[
        _entry(title: 'Samstagstermin', dayOffset: 5, fromH: 10, toH: 11),
      ], dayCount: 7);

      expect(find.text('Samstagstermin'), findsOneWidget);
    });
  });

  group('the width the week is given', () {
    /// The horizontal extent of the scrollable grid area, and of its content.
    (double viewport, double content) widthsOf(WidgetTester tester) {
      final Finder scroller = find.byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      );
      expect(scroller, findsOneWidget);
      final ScrollableState state = tester.state<ScrollableState>(scroller);
      final ScrollPosition position = state.position;
      return (
        position.viewportDimension,
        position.viewportDimension + position.maxScrollExtent,
      );
    }

    testWidgets('fits Monday to Friday without scrolling sideways', (
      WidgetTester tester,
    ) async {
      // "The whole teaching week at a glance" is the point of this view. A
      // fixed column width made every phone scroll to reach Friday.
      await pumpGrid(tester, <CalendarEntry>[]);

      final (double viewport, double content) = widthsOf(tester);
      expect(content, lessThanOrEqualTo(viewport + 0.5));
      expect(_headers(tester), hasLength(5));
    });

    testWidgets('still fits on a narrow phone', (WidgetTester tester) async {
      await pumpGrid(tester, <CalendarEntry>[], size: const Size(320, 800));

      final (double viewport, double content) = widthsOf(tester);
      expect(content, lessThanOrEqualTo(viewport + 0.5));
    });

    testWidgets('columns share the width evenly', (WidgetTester tester) async {
      await pumpGrid(tester, <CalendarEntry>[]);

      final List<double> headerWidths = tester
          .renderObjectList<RenderBox>(
            find.ancestor(
              of: find.textContaining('11'),
              matching: find.byType(InkWell),
            ),
          )
          .map((RenderBox box) => box.size.width)
          .toList(growable: false);
      final (double viewport, _) = widthsOf(tester);

      expect(headerWidths, isNotEmpty);
      expect(headerWidths.first, closeTo(viewport / 5, 0.5));
    });

    testWidgets('never squeezes a column below a touch target', (
      WidgetTester tester,
    ) async {
      // Seven columns on a 320 px phone would be narrower than a finger, so
      // that is where the sideways scroll comes back instead of shrinking on.
      await pumpGrid(
        tester,
        <CalendarEntry>[],
        dayCount: 7,
        size: const Size(320, 800),
      );

      final (double viewport, double content) = widthsOf(tester);
      expect(content, greaterThan(viewport));
      expect(content / 7, closeTo(WeekGridView.minColumnWidth, 0.5));
    });
  });

  testWidgets('every day header is at least one touch target tall', (
    WidgetTester tester,
  ) async {
    await pumpGrid(tester, <CalendarEntry>[]);

    final Finder headerTarget = find.ancestor(
      of: find.textContaining('11'),
      matching: find.byType(InkWell),
    );
    expect(headerTarget, findsOneWidget);
    expect(
      tester.getSize(headerTarget).height,
      greaterThanOrEqualTo(AppSizes.minTouchTarget),
    );
  });

  testWidgets('the hour lines follow the reader text size', (
    WidgetTester tester,
  ) async {
    // The lines and the entries have to agree. Entries are positioned against
    // the scaled hour height; lines drawn at the unscaled constant would sit at
    // half the spacing and a 10:00 lecture would straddle the 12:00 mark.
    await pumpGrid(tester, <CalendarEntry>[
      _entry(title: 'Vorlesung', dayOffset: 0, fromH: 10, toH: 11),
    ], textScaler: const TextScaler.linear(2));

    final List<double> lines =
        tester
            .renderObjectList<RenderBox>(find.byType(Divider))
            .map((RenderBox box) => box.localToGlobal(Offset.zero).dy)
            .toSet()
            .toList(growable: false)
          ..sort();

    expect(lines.length, greaterThan(1));
    expect(
      lines[1] - lines[0],
      closeTo(const TextScaler.linear(2).scale(WeekGridView.hourHeight), 1),
      reason: 'an hour on the grid is as tall as an hour of entries',
    );
  });

  testWidgets('the hour grid remains quietly visible', (
    WidgetTester tester,
  ) async {
    await pumpGrid(tester, <CalendarEntry>[]);

    final Divider line = tester.widget<Divider>(find.byType(Divider).first);
    final Color outline = Theme.of(
      tester.element(find.byType(WeekGridView)),
    ).colorScheme.outline;
    expect(line.color, outline.withValues(alpha: 0.36));
  });

  testWidgets('a short entry still shows its title in full', (
    WidgetTester tester,
  ) async {
    // A 15-minute slot is drawn at the 30-minute minimum — barely 28 px tall.
    // Squeezing an icon and a line of text into a column that small cuts the
    // glyphs in half, which is worse than showing no icon at all.
    await pumpGrid(tester, <CalendarEntry>[
      _entry(
        title: 'Kurzbesprechung',
        dayOffset: 2,
        fromH: 17,
        toH: 17,
        toM: 15,
      ),
    ]);

    final RenderBox box = tester.renderObject<RenderBox>(
      find.text('Kurzbesprechung'),
    );
    expect(
      box.size.height,
      greaterThanOrEqualTo(_neededHeight(tester, 'Kurzbesprechung')),
      reason: 'the title is squeezed below the height one line needs',
    );
  });

  testWidgets('a short entry keeps its source icon', (
    WidgetTester tester,
  ) async {
    // Accessibility: the source must never be carried by colour alone, so
    // making room for the title may not simply drop the icon.
    await pumpGrid(tester, <CalendarEntry>[
      _entry(
        title: 'Kurzbesprechung',
        dayOffset: 2,
        fromH: 17,
        toH: 17,
        toM: 15,
      ),
    ]);

    expect(
      find.descendant(of: find.byType(Card), matching: find.byType(Icon)),
      findsOneWidget,
    );
  });

  testWidgets('a short entry has a 48 dp target without stretching its card', (
    WidgetTester tester,
  ) async {
    await pumpGrid(tester, <CalendarEntry>[
      _entry(
        title: 'Kurzbesprechung',
        dayOffset: 2,
        fromH: 17,
        toH: 17,
        toM: 15,
      ),
    ]);

    final Finder target = find.bySemanticsLabel(RegExp('Kurzbesprechung'));
    final Finder card = find.ancestor(
      of: find.text('Kurzbesprechung'),
      matching: find.byType(Card),
    );
    expect(target, findsOneWidget);
    expect(
      tester.getSize(target).height,
      greaterThanOrEqualTo(AppSizes.minTouchTarget),
    );
    expect(tester.getSize(card).height, lessThan(AppSizes.minTouchTarget));
  });

  testWidgets('a long entry shows its title in full too', (
    WidgetTester tester,
  ) async {
    await pumpGrid(tester, <CalendarEntry>[
      _entry(title: 'Vorlesung', dayOffset: 1, fromH: 10, toH: 12),
    ]);

    final RenderBox box = tester.renderObject<RenderBox>(
      find.text('Vorlesung'),
    );
    expect(
      box.size.height,
      greaterThanOrEqualTo(_neededHeight(tester, 'Vorlesung')),
    );
  });

  testWidgets('doubled text does not clip a short entry either', (
    WidgetTester tester,
  ) async {
    await pumpGrid(tester, <CalendarEntry>[
      _entry(title: 'Kurz', dayOffset: 0, fromH: 9, toH: 9, toM: 20),
    ], textScaler: const TextScaler.linear(2));

    final RenderBox box = tester.renderObject<RenderBox>(find.text('Kurz'));
    expect(
      box.size.height,
      greaterThanOrEqualTo(_neededHeight(tester, 'Kurz')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the minimum box is tall enough for one line of text', (
    WidgetTester tester,
  ) async {
    // Guards the arithmetic the fix depends on: whatever layout the box uses,
    // the shortest entry must have room for a readable line.
    await pumpGrid(tester, <CalendarEntry>[
      _entry(title: 'Kurz', dayOffset: 0, fromH: 9, toH: 9, toM: 5),
    ]);

    const double minimumBoxHeight =
        WeekLayout.minimumVisibleMinutes * WeekGridView.hourHeight / 60;
    final RenderBox text = tester.renderObject<RenderBox>(find.text('Kurz'));
    expect(text.size.height, lessThanOrEqualTo(minimumBoxHeight));
  });

  group('the day the grid reaches', () {
    /// The two vertical scrollables: the hour gutter and the grid itself.
    ///
    /// Tree order — the gutter is the first child of the Row, the grid sits
    /// inside the horizontal scroller on its right.
    (ScrollableState gutter, ScrollableState grid) verticals(
      WidgetTester tester,
    ) {
      final Finder down = find.byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      expect(down, findsNWidgets(2));
      return (tester.state(down.first), tester.state(down.last));
    }

    /// Where the hour lines of the grid actually are on screen.
    List<double> lineDys(WidgetTester tester) =>
        tester
            .renderObjectList<RenderBox>(find.byType(Divider))
            .map((RenderBox box) => box.localToGlobal(Offset.zero).dy)
            .toSet()
            .toList(growable: false)
          ..sort();

    /// The visible rectangle of a scrollable.
    Rect viewportOf(ScrollableState state) {
      final RenderBox box = state.context.findRenderObject()! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    /// Whether an hour label is inside the visible part of the axis.
    ///
    /// Vertically only: the test font draws every glyph as a square of the
    /// font size, so a five-character label measures far wider here than any
    /// real one and would fail a full-rectangle check for no real reason.
    bool onScreen(WidgetTester tester, ScrollableState gutter, String label) {
      final Rect viewport = viewportOf(gutter);
      final Rect text = tester.getRect(find.text(label));
      return text.top >= viewport.top - 0.5 &&
          text.bottom <= viewport.bottom + 0.5;
    }

    testWidgets('is 00:00 to 24:00 on a small phone', (
      WidgetTester tester,
    ) async {
      // The grid used to span only the hours its entries happened to fall in:
      // on a short phone the rest of the day was not merely off screen, it did
      // not exist. 24 hours at the hour height is taller than any phone, so
      // what has to be true is that all of it is *scrollable to*.
      await pumpGrid(tester, <CalendarEntry>[
        _entry(title: 'Vorlesung', dayOffset: 0, fromH: 10, toH: 12),
      ], size: const Size(320, 568));

      final (_, ScrollableState grid) = verticals(tester);
      final ScrollPosition position = grid.position;
      final double reachable =
          position.viewportDimension + position.maxScrollExtent;

      expect(position.maxScrollExtent, greaterThan(0));
      expect(
        reachable,
        greaterThanOrEqualTo(WeekGridView.hourHeight * 24),
        reason: 'a whole day has to fit into what can be scrolled through',
      );
    });

    testWidgets('reaches both ends of the day by dragging', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester, <CalendarEntry>[
        _entry(title: 'Vorlesung', dayOffset: 0, fromH: 10, toH: 12),
      ], size: const Size(320, 568));

      final (ScrollableState gutter, ScrollableState grid) = verticals(tester);

      // Up to the top of the day.
      await tester.drag(find.byType(WeekGridView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(grid.position.pixels, 0);
      expect(
        onScreen(tester, gutter, '00:00'),
        isTrue,
        reason: '00:00 is the top of the day and has to be readable there',
      );

      // ...and all the way down to the end of it.
      await tester.drag(find.byType(WeekGridView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(grid.position.pixels, grid.position.maxScrollExtent);
      expect(
        onScreen(tester, gutter, '24:00'),
        isTrue,
        reason: 'the day closes at 24:00 and that has to be readable too',
      );
    });

    testWidgets('is reachable at twice the text size as well', (
      WidgetTester tester,
    ) async {
      // A doubled text size doubles the hour height, so the day is twice as
      // tall — and every bit of it still has to be reachable.
      await pumpGrid(
        tester,
        <CalendarEntry>[],
        size: const Size(320, 568),
        textScaler: const TextScaler.linear(2),
      );

      final (ScrollableState gutter, ScrollableState grid) = verticals(tester);
      await tester.drag(find.byType(WeekGridView), const Offset(0, -6000));
      await tester.pumpAndSettle();

      expect(grid.position.pixels, grid.position.maxScrollExtent);
      expect(onScreen(tester, gutter, '24:00'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the hour labels on their hour lines while scrolling', (
      WidgetTester tester,
    ) async {
      // The gutter is a scroll view of its own. Handing both of them the same
      // controller does *not* keep them in step — only the one that was
      // dragged moves — and the labels would drift off their lines.
      await pumpGrid(tester, <CalendarEntry>[], size: const Size(320, 568));

      for (final double by in <double>[-137, -400, 220]) {
        await tester.drag(find.byType(WeekGridView), Offset(0, by));
        await tester.pumpAndSettle();

        final List<double> lines = lineDys(tester);
        expect(
          tester.getTopLeft(find.text('00:00')).dy,
          closeTo(lines.first, 1),
          reason: 'the 00:00 label left its hour line after scrolling by $by',
        );
        expect(
          tester.getTopLeft(find.text('24:00')).dy,
          closeTo(lines.last, 1),
          reason: 'the 24:00 label left its hour line after scrolling by $by',
        );
      }
    });

    testWidgets('opens on the first hour that has something on it', (
      WidgetTester tester,
    ) async {
      // 24 hours of grid opening on 00:00 would mean scrolling past the night
      // every time. The entries decide where the week starts — they no longer
      // decide how much of it exists.
      await pumpGrid(tester, <CalendarEntry>[
        _entry(title: 'Vorlesung', dayOffset: 0, fromH: 10, toH: 12),
      ], size: const Size(320, 568));

      final (_, ScrollableState grid) = verticals(tester);
      expect(grid.position.pixels, closeTo(10 * WeekGridView.hourHeight, 1));
    });

    testWidgets('a midnight entry is drawn at the very top', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester, <CalendarEntry>[
        _entry(title: 'Nachtschicht', dayOffset: 0, fromH: 0, toH: 2),
      ], size: const Size(320, 568));

      await tester.drag(find.byType(WeekGridView), const Offset(0, 2000));
      await tester.pumpAndSettle();

      final List<double> lines = lineDys(tester);
      expect(
        tester.getTopLeft(find.byType(Card).first).dy,
        closeTo(lines.first, 1),
        reason: 'an entry at 00:00 sits on the top edge of the day',
      );
    });

    testWidgets('an entry just before midnight is not cut off', (
      WidgetTester tester,
    ) async {
      // The last half hour of the day is where a grid that ends exactly at the
      // 24:00 line clips its final entry.
      await pumpGrid(tester, <CalendarEntry>[
        _entry(
          title: 'Spätschicht',
          dayOffset: 0,
          fromH: 23,
          fromM: 40,
          toH: 23,
          toM: 55,
        ),
      ], size: const Size(320, 568));

      await tester.drag(find.byType(WeekGridView), const Offset(0, -3000));
      await tester.pumpAndSettle();

      final RenderBox card = tester.renderObject<RenderBox>(
        find.byType(Card).first,
      );
      final (_, ScrollableState grid) = verticals(tester);
      final Rect viewport = viewportOf(grid);
      final Rect box = card.localToGlobal(Offset.zero) & card.size;

      expect(
        box.height,
        closeTo(
          WeekLayout.minimumVisibleMinutes * WeekGridView.hourHeight / 60,
          1,
        ),
      );
      expect(
        box.bottom,
        lessThanOrEqualTo(viewport.bottom + 0.5),
        reason:
            'the last entry of the day is drawn inside the grid, not past it',
      );
    });

    testWidgets('a vertical drag does not scroll the week sideways', (
      WidgetTester tester,
    ) async {
      await pumpGrid(
        tester,
        <CalendarEntry>[],
        dayCount: 7,
        size: const Size(320, 568),
      );

      final ScrollableState sideways = tester.state(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      final double before = sideways.position.pixels;

      await tester.drag(find.byType(WeekGridView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(sideways.position.pixels, before);
    });

    testWidgets('narrow day columns still scroll sideways', (
      WidgetTester tester,
    ) async {
      // Seven columns on a 320 px phone do not fit, and reaching Sunday is the
      // one horizontal scroll inside the grid that has to keep working.
      await pumpGrid(
        tester,
        <CalendarEntry>[],
        dayCount: 7,
        size: const Size(320, 568),
      );

      final ScrollableState sideways = tester.state(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      expect(sideways.position.maxScrollExtent, greaterThan(0));

      await tester.drag(find.byType(WeekGridView), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(sideways.position.pixels, greaterThan(0));
    });
  });

  group('opening an entry', () {
    testWidgets('a timed entry opens its details', (WidgetTester tester) async {
      await pumpGrid(tester, <CalendarEntry>[
        _entry(title: 'Demotermin', dayOffset: 0, fromH: 10, toH: 12),
      ]);

      await tester.tap(find.text('Demotermin'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarEntrySheet), findsOneWidget);
    });

    testWidgets('an all-day entry is a button of its own', (
      WidgetTester tester,
    ) async {
      // The all-day band used to be one joined string: the only entries in the
      // week that could not be opened.
      await pumpGrid(tester, <CalendarEntry>[
        _allDay('Ganztagstermin'),
        _allDay('Zweiter Ganztagstermin', dayOffset: 1),
      ]);

      expect(find.byType(ActionChip), findsNWidgets(2));

      final RenderBox chip = tester.renderObject<RenderBox>(
        find.byType(ActionChip).first,
      );
      expect(
        chip.size.height,
        greaterThanOrEqualTo(AppSizes.minTouchTarget),
        reason: 'a chip is still something a thumb has to hit',
      );

      await tester.tap(find.text('Ganztagstermin'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarEntrySheet), findsOneWidget);
    });

    testWidgets('an all-day entry that starts before the week is still drawn', (
      WidgetTester tester,
    ) async {
      // A lecture-free week or an examination period starts on some Monday and
      // runs on. Anchoring the band on `start` alone made it disappear from
      // every week after the first.
      final CalendarEntry span = CalendarEntry(
        id: 'exam-period',
        source: CalendarSource.publicCalendar,
        title: 'Prüfungszeitraum',
        start: _monday.subtract(const Duration(days: 10)),
        end: _monday.add(const Duration(days: 10)),
        allDay: true,
      );

      await pumpGrid(tester, <CalendarEntry>[span]);

      expect(find.text('Prüfungszeitraum'), findsOneWidget);
    });
  });
}
