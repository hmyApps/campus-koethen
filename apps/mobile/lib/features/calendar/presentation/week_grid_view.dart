// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/contrast.dart';
import '../../../l10n/l10n.dart';
import '../../timetable/application/timetable_week.dart';
import '../domain/calendar_entry.dart';
import '../domain/week_layout.dart';
import 'calendar_entry_sheet.dart';
import 'week_grid_event.dart';

/// A week as a time grid: one column per drawn day over an hour axis.
///
/// The drawn days **share the available width**, so the teaching week is on
/// screen at a glance — a week you have to scroll sideways to finish is not a
/// week you can see. Only when a column would fall below a touch target does
/// the grid stop shrinking and scroll horizontally instead, which on a narrow
/// phone is what the weekend does. The hour gutter stays put either way, so
/// the time is never scrolled off.
///
/// Vertically the grid draws the **whole day**, 00:00 to 24:00, and scrolls
/// through it: no phone is tall enough for 24 hours at a readable hour height,
/// and cropping the axis to the hours that happen to hold entries — which is
/// what this did before — meant the rest of the day simply did not exist. The
/// view opens scrolled to the first hour that has something on it, so the
/// scrolling is what you do to look around, not what you do to start.
///
/// Offered as an option, not as the default: the day agenda answers "what is
/// on" in far less space. This view answers "how is my week shaped", which is
/// a different and rarer question.
class WeekGridView extends StatefulWidget {
  const WeekGridView({
    required this.weekStart,
    required this.entries,
    required this.today,
    required this.selected,
    required this.dayCount,
    required this.onSelectDay,
    super.key,
  });

  final DateTime weekStart;
  final List<CalendarEntry> entries;
  final DateTime today;
  final DateTime selected;

  /// How many days from [weekStart] are drawn — five for the teaching week,
  /// seven once the reader switches the weekend on.
  final int dayCount;

  final ValueChanged<DateTime> onSelectDay;

  /// The narrowest a day column may get before the grid scrolls instead.
  ///
  /// A column is the tap target of its day header, so it does not go below one.
  static const double minColumnWidth = AppSizes.minTouchTarget;

  /// The width of one column when [dayCount] days share [available] pixels.
  static double columnWidthFor(double available, int dayCount) {
    if (dayCount <= 0) return minColumnWidth;
    final double shared = available / dayCount;
    return shared >= minColumnWidth ? shared : minColumnWidth;
  }

  /// Height of one hour row at the default text size.
  static const double hourHeight = 56;

  /// Height of the day-header row at the default text size.
  static const double headerHeight = AppSizes.minTouchTarget;

  /// Width of the fixed hour gutter at the default text size.
  static const double gutterWidth = 44;

  /// The row heights actually used, grown with the reader's text size.
  ///
  /// A row is the only thing standing between an entry and its label: at twice
  /// the text size a fixed 56 px hour leaves a half-hour box shorter than a
  /// single line, and the title would be cut mid-glyph. Growing the grid keeps
  /// the layout honest instead — the week simply becomes taller and scrolls.
  static double hourHeightOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(hourHeight);

  static double headerHeightOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(headerHeight);

  /// The gutter width actually used, grown with the reader's text size.
  ///
  /// "24:00" at twice the text size does not fit into 44 px, and a clipped
  /// hour is an unreadable one — the axis is the only thing telling the reader
  /// which part of the day they are looking at.
  static double gutterWidthOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(gutterWidth);

  /// The room kept below the 24:00 line.
  ///
  /// It carries the closing 24:00 label, which hangs off the bottom edge of
  /// the last hour, and the overhang of an entry that starts just before
  /// midnight and is drawn at [WeekLayout.minimumVisibleMinutes]. Half an hour
  /// row is exactly that minimum, so nothing at the end of the day is cut.
  static double bottomPadOf(BuildContext context) => hourHeightOf(context) / 2;

  /// The full height of the time grid: 24 hours plus the closing room.
  static double gridHeightOf(BuildContext context) =>
      hourHeightOf(context) * WeekLayout.fullDay.hourCount +
      bottomPadOf(context);

  @override
  State<WeekGridView> createState() => _WeekGridViewState();
}

class _WeekGridViewState extends State<WeekGridView> {
  /// The grid's own vertical scroll — the one the finger drives.
  final ScrollController _vertical = ScrollController();

  /// The hour gutter, dragged along by [_vertical].
  ///
  /// A single controller shared by two scroll views does **not** keep them in
  /// step: each `ScrollPosition` moves on its own, and only the one that was
  /// actually dragged moves at all. That is exactly the visible offset between
  /// hour labels and hour lines this view has to avoid, so the gutter gets its
  /// own position and is told where to be.
  final ScrollController _gutter = ScrollController();

  final ScrollController _horizontal = ScrollController();

  /// Whether the opening scroll to the first interesting hour has happened.
  ///
  /// Once only: after that the position belongs to the reader, and swiping to
  /// the next week must not yank the view back to 08:00.
  bool _anchored = false;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_syncGutter);
  }

  @override
  void dispose() {
    _vertical.removeListener(_syncGutter);
    _vertical.dispose();
    _gutter.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _syncGutter() {
    if (!_gutter.hasClients || !_vertical.hasClients) return;
    final ScrollPosition target = _gutter.position;
    // Clamped rather than passed straight through: an iOS overscroll takes the
    // grid past its own extent, and dragging the gutter along into a bounce it
    // cannot simulate would leave the two ends of the same hour apart.
    final double offset = _vertical.position.pixels.clamp(
      target.minScrollExtent,
      target.maxScrollExtent,
    );
    if ((target.pixels - offset).abs() > 0.5) target.jumpTo(offset);
  }

  /// Opens the week at [offset], once, before the reader has scrolled.
  ///
  /// [hasEntries] guards against anchoring on an empty week: the very first
  /// build usually happens before the timetable and the public calendars have
  /// answered, and anchoring then locked the opening position to the default
  /// 08:00 for good — so a week whose first lecture is at 10:00 opened two
  /// hours too early and never corrected itself (CAL-7). Waiting for the
  /// first entries costs nothing: a genuinely empty week has no better
  /// position to open at than the default anyway.
  void _anchorTo(double offset, {required bool hasEntries}) {
    if (_anchored || !hasEntries) return;
    _anchored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      final ScrollPosition position = _vertical.position;
      _vertical.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final List<DateTime> days = <DateTime>[
      for (int i = 0; i < widget.dayCount; i++)
        TimetableWeek.shift(widget.weekStart, i),
    ];
    // Which entry lands on which day, and where on the hour axis — derived
    // once per (entries, week) rather than on every build. None of it depends
    // on the constraints or on anything else a rebuild changes.
    final WeekPlan plan = weekPlanFor(widget.entries, days);

    final DateTime todayKey = calendarDayKey(widget.today);
    final DateTime selectedKey = calendarDayKey(widget.selected);

    // The grid spans the whole day; what the entries decide is only where it
    // opens, so the reader lands on their first lecture rather than on 00:00.
    const GridRange range = WeekLayout.fullDay;
    final double hourHeight = WeekGridView.hourHeightOf(context);
    final double headerHeight = WeekGridView.headerHeightOf(context);
    final double gridHeight = WeekGridView.gridHeightOf(context);
    _anchorTo(
      plan.openingHour * hourHeight,
      hasEntries: widget.entries.isNotEmpty,
    );

    final List<CalendarEntry> allDay = plan.allDay;

    return Column(
      children: <Widget>[
        // All-day items get their own band: they have no place on a time axis,
        // and stretching one across the whole column would bury the rest.
        //
        // One chip per entry rather than one joined line: an all-day entry has
        // details like any other, and a run-on string is the one place in the
        // week where an entry could not be opened.
        if (allDay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  l10n.calendarWeekAllDay,
                  style: text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final CalendarEntry entry in allDay)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.xs,
                            ),
                            child: _AllDayChip(entry: entry),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Fixed hour gutter, scrolled vertically in step with the grid.
              SizedBox(
                width: WeekGridView.gutterWidthOf(context),
                child: Column(
                  children: <Widget>[
                    SizedBox(height: headerHeight),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _gutter,
                        physics: const NeverScrollableScrollPhysics(),
                        // Labels are positioned at the hour lines instead of
                        // stacked in rows: the closing 24:00 sits *on* the
                        // bottom edge of the last hour, which no row above it
                        // could hold.
                        child: SizedBox(
                          height: gridHeight,
                          child: Stack(
                            children: <Widget>[
                              for (
                                int h = range.startHour;
                                h <= range.endHour;
                                h++
                              )
                                Positioned(
                                  top: (h - range.startHour) * hourHeight,
                                  right: AppSpacing.xs,
                                  child: Text(
                                    '${h.toString().padLeft(2, '0')}:00',
                                    style: text.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double columnWidth = WeekGridView.columnWidthFor(
                      constraints.maxWidth,
                      days.length,
                    );
                    return SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: columnWidth * days.length,
                        child: Column(
                          children: <Widget>[
                            SizedBox(
                              height: headerHeight,
                              child: Row(
                                children: <Widget>[
                                  for (final DateTime day in days)
                                    _DayHeader(
                                      day: day,
                                      locale: locale,
                                      width: columnWidth,
                                      isToday: calendarDayKey(day) == todayKey,
                                      isSelected:
                                          calendarDayKey(day) == selectedKey,
                                      onTap: () => widget.onSelectDay(day),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _vertical,
                                child: SizedBox(
                                  height: gridHeight,
                                  child: Row(
                                    children: <Widget>[
                                      for (final DateTime day in days)
                                        _DayColumn(
                                          placed: plan.placedOn(day),
                                          range: range,
                                          locale: locale,
                                          width: columnWidth,
                                          hourHeight: hourHeight,
                                          isToday:
                                              calendarDayKey(day) == todayKey,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.locale,
    required this.width,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final String locale;
  final double width;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        selected: isSelected,
        label: AppDateFormats.weekdayDate(day, locale),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? colors.primaryContainer : null,
              // Today keeps an outline of its own, so "where am I" never
              // depends on telling two fills apart.
              border: isToday
                  ? Border.all(color: colors.primary, width: 1.5)
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Center(
              child: Text(
                '${AppDateFormats.shortWeekday(day, locale)} '
                '${AppDateFormats.dayOfMonth(day, locale)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.placed,
    required this.range,
    required this.locale,
    required this.width,
    required this.hourHeight,
    required this.isToday,
  });

  final List<PlacedEntry> placed;
  final GridRange range;
  final String locale;
  final double width;
  final double hourHeight;
  final bool isToday;

  static IconData _iconFor(CalendarSource source) => switch (source) {
    CalendarSource.timetable => AppIcons.school_outlined,
    CalendarSource.moodle => AppIcons.assignment_outlined,
    CalendarSource.exchangeCalendar => AppIcons.event_outlined,
    CalendarSource.canteenFavourite => AppIcons.soup,
    CalendarSource.publicCalendar ||
    CalendarSource.postEvent ||
    CalendarSource.savedEvents => AppIcons.public,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final double pxPerMinute = hourHeight / 60;
    final int gridStart = range.startHour * 60;
    final TextStyle? titleStyle = Theme.of(context).textTheme.labelSmall;
    final double gridExtent = range.hourCount * hourHeight + hourHeight / 2;

    // Measured once per column rather than per entry: how tall one line of the
    // title actually is at the reader's text size decides how many lines fit
    // into a box, and guessing from `fontSize` alone is wrong as soon as a
    // font, a locale or a text scaler disagrees.
    final TextPainter probe = TextPainter(
      text: TextSpan(text: 'Hg', style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double lineHeight = probe.height;
    probe.dispose();

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isToday
              ? colors.primaryContainer.withValues(alpha: 0.18)
              : null,
          border: Border(
            left: BorderSide(color: colors.outline.withValues(alpha: 0.48)),
          ),
        ),
        child: Stack(
          children: <Widget>[
            // Hour lines. Positioned against the SAME height the entries use:
            // drawing them at the unscaled constant put a 10:00 lecture next to
            // the 08:00 mark as soon as the reader scaled the text up.
            for (int h = 0; h <= range.hourCount; h++)
              Positioned(
                top: h * hourHeight,
                left: 0,
                right: 0,
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.outline.withValues(alpha: 0.36),
                ),
              ),
            for (final PlacedEntry item in placed)
              WeekGridEventPosition(
                item: item,
                semanticLabel: <String>[
                  l10n.calendarWeekSemantic(
                    item.entry.title,
                    AppDateFormats.time(item.entry.start, locale),
                    AppDateFormats.time(
                      item.entry.end ?? item.entry.start,
                      locale,
                    ),
                  ),
                  if (item.entry.isCancelled) l10n.timetableStatusCancelled,
                ].join(', '),
                gridStartMinute: gridStart,
                pixelsPerMinute: pxPerMinute,
                gridExtent: gridExtent,
                left: (width / item.laneCount) * item.lane + 1,
                width: width / item.laneCount - 2,
                onPressed: () => showCalendarEntrySheet(context, item.entry),
                child: Semantics(
                  label: <String>[
                    l10n.calendarWeekSemantic(
                      item.entry.title,
                      AppDateFormats.time(item.entry.start, locale),
                      AppDateFormats.time(
                        item.entry.end ?? item.entry.start,
                        locale,
                      ),
                    ),
                    // The day view, the list view and the all-day chip all say
                    // this; the grid box said it neither visually nor in the
                    // semantics tree.
                    if (item.entry.isCancelled) l10n.timetableStatusCancelled,
                  ].join(', '),
                  excludeSemantics: true,
                  button: true,
                  child: Builder(
                    builder: (BuildContext context) {
                      final Color? calendarColor = _calendarColor(item.entry);
                      final Color foreground = calendarColor == null
                          ? colors.onSurfaceVariant
                          : _foregroundOn(calendarColor);
                      return Card(
                        margin: EdgeInsets.zero,
                        color: calendarColor ?? colors.surfaceContainerHighest,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () =>
                              showCalendarEntrySheet(context, item.entry),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xxs),
                            child: LayoutBuilder(
                              builder: (BuildContext context, BoxConstraints constraints) {
                                // A box is only as tall as its entry is long, and
                                // the shortest is barely one line. Work out how
                                // many whole lines fit and ellipsise the rest —
                                // stacking the icon above the title would leave
                                // the text a few pixels and cut the glyphs in
                                // half, which reads as a rendering fault rather
                                // than as a short appointment.
                                final int lines = lineHeight <= 0
                                    ? 1
                                    : (constraints.maxHeight / lineHeight)
                                          .floor()
                                          .clamp(1, 4);
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    // Icon and text, never colour alone.
                                    Icon(
                                      _iconFor(item.entry.source),
                                      size: 12,
                                      color: foreground,
                                    ),
                                    const SizedBox(width: AppSpacing.xxs),
                                    Expanded(
                                      child: Text(
                                        item.entry.title,
                                        // Struck through exactly as in every
                                        // other view — a shape, so it survives
                                        // greyscale and colour blindness.
                                        style: titleStyle?.copyWith(
                                          color: calendarColor == null
                                              ? null
                                              : foreground,
                                          decoration: item.entry.isCancelled
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                        maxLines: lines,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One all-day entry in the band above the grid.
///
/// Small, but a real button: it has a label, a tap target of its own and the
/// same detail view every other entry has.
class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.entry});

  final CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color? calendarColor = _calendarColor(entry);
    final Color foreground = calendarColor == null
        ? colors.onSurfaceVariant
        : _foregroundOn(calendarColor);

    return ActionChip(
      // The band is the tightest row of the week; without this the chip would
      // shrink to its text and fall short of a usable tap target.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      avatar: Icon(
        _DayColumn._iconFor(entry.source),
        size: AppSizes.iconSmall,
        color: foreground,
      ),
      label: Text(
        entry.title,
        style: TextStyle(
          color: calendarColor == null ? null : foreground,
          decoration: entry.isCancelled ? TextDecoration.lineThrough : null,
        ),
      ),
      backgroundColor: calendarColor,
      onPressed: () => showCalendarEntrySheet(context, entry),
    );
  }
}

Color? _calendarColor(CalendarEntry entry) {
  final int? argb = entry.colorArgb;
  return argb == null ? null : Color(argb).withValues(alpha: 1);
}

/// Calendar colours come from editorial data and may be arbitrarily light or
/// dark. Choose the higher-contrast of the design system's paper and ink so a
/// coloured appointment remains readable in both app themes.
Color _foregroundOn(Color background) {
  final Color ink = AppColors.light.onSurface;
  final Color paper = AppColors.light.surface;
  return Contrast.ratio(ink, background) >= Contrast.ratio(paper, background)
      ? ink
      : paper;
}
