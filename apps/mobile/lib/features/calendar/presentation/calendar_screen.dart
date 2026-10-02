// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../core/documents/app_document.dart';
import '../../../core/documents/document_share_service.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../core/widgets/time_rail.dart';
import '../../../l10n/l10n.dart';
import '../../campusmap/application/campus_map_providers.dart';
import '../../campusmap/domain/map_catalog.dart';
import '../../campusmap/domain/room.dart';
import '../../campusmap/domain/room_mention.dart';
import '../../campusmap/presentation/room_link.dart';
import '../../moodle/application/moodle_account_controller.dart';
import '../../moodle/application/moodle_controller.dart';
import '../../timetable/application/timetable_week.dart';
import '../../timetable/application/timetable_lesson_info_filter.dart';
import '../../timetable/presentation/timetable_group_picker_sheet.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_entry.dart';
import '../domain/calendar_entry_details.dart';
import '../domain/calendar_ics_export.dart';
import '../domain/entry_rooms.dart';
import 'calendar_entry_sheet.dart';
import 'calendar_list_rows.dart';
import 'calendar_source_sheets.dart';
import 'week_grid_view.dart';
import 'week_strip.dart';

/// The top-level "Kalender" tab: one calendar merged from the timetable,
/// Moodle deadlines and the public calendars.
///
/// ## What changed, and why
///
/// The screen used to open with two full bands of controls — three source
/// buttons, then a view switcher — before a single appointment was visible.
/// Both are still here, but the sources have moved into the masthead as one
/// action: which calendars you are looking at is a question answered once,
/// while which day you are looking at is the one asked all day.
///
/// The day itself is drawn on the rail (see `TimeRail`), which is what turns a
/// list of appointments into a picture of a day: the times line up in one
/// column, the gaps between them are visible as gaps, and "now" is a marker
/// drawn straight across.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({
    this.exportShareService = const DocumentShareService(),
    super.key,
  });

  /// Injectable so a test can verify what the export action hands off
  /// without opening the real OS share sheet — same pattern as
  /// `DocumentViewerScreen.shareService`.
  final DocumentShareService exportShareService;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  @override
  void initState() {
    super.initState();
    // Populate Moodle deadlines lazily on open (respects the one-hour gate).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(moodleAccountControllerProvider).value != null) {
        ref.read(moodleControllerProvider.notifier).maybeAutoSync();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final CalendarViewMode mode = ref.watch(calendarViewModeProvider);
    final CalendarData data = ref.watch(focusedCalendarDataProvider);
    final TimetableLessonInfoFilter lessonInfoFilter = ref.watch(
      timetableLessonInfoFilterProvider,
    );

    // "Not everything is showing" has to be visible from the outside, or a
    // missing appointment looks like a bug rather than like a setting.
    final bool everythingVisible =
        data.enabledSources.length == kMergeableCalendarSources.length &&
        lessonInfoFilter.disabledValues.isEmpty &&
        !lessonInfoFilter.hideWithoutInfo;

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.navCalendar,
      actions: <Widget>[
        _ExportCalendarAction(shareService: widget.exportShareService),
        IconButton(
          tooltip: l10n.calendarSourcesLabel,
          onPressed: () => showCalendarSourcesSheet(context),
          isSelected: !everythingVisible,
          icon: const Icon(AppIcons.tune),
        ),
      ],
      controls: _ViewControls(mode: mode),
      body: switch (mode) {
        CalendarViewMode.day => _DayAgendaView(data: data),
        CalendarViewMode.week => _WeekView(data: data),
        CalendarViewMode.list => _ListView(data: data),
      },
    );
  }
}

/// "Kalender exportieren": writes everything currently merged into ONE
/// RFC 5545 file and hands it to the OS share sheet — a one-time, local
/// export the reader saves or forwards wherever they like, never a
/// server-hosted subscription feed (`docs/implementation-phases-quality-audit-2026-09-30.md`,
/// Phase 14 §1, flags what a live feed would need and deliberately leaves it
/// open; this sidesteps that question rather than answering it).
///
/// Reads the same wide-horizon source the list view already populates
/// (`calendarListDataProvider`) rather than only the current day/week/month —
/// an export limited to whatever view happens to be open would silently
/// leave most of the semester out. That source is only READ on a tap, never
/// watched continuously: subscribing the masthead to the list's full
/// timetable/Moodle/public-calendar fan-out on every visit, regardless of
/// which view is open or whether export is ever used, would make exporting
/// cost everyone the list view's background work just for the icon to exist.
class _ExportCalendarAction extends ConsumerStatefulWidget {
  const _ExportCalendarAction({required this.shareService});

  final DocumentShareService shareService;

  @override
  ConsumerState<_ExportCalendarAction> createState() =>
      _ExportCalendarActionState();
}

class _ExportCalendarActionState extends ConsumerState<_ExportCalendarAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return IconButton(
      tooltip: l10n.calendarExportAction,
      icon: _busy
          ? const SizedBox.square(
              dimension: AppSizes.icon,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(AppIcons.ios_share),
      onPressed: _busy ? null : _export,
    );
  }

  Future<void> _export() async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);

    try {
      final DateTime today = DateTime.now();
      CalendarData data = ref.read(calendarListDataProvider(today));
      // Bounded: a source stuck offline must not hang the export forever —
      // it exports whatever did load once the budget runs out.
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
      while (data.isLoading && DateTime.now().isBefore(deadline) && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        data = ref.read(calendarListDataProvider(today));
      }
      if (!mounted) return;

      if (data.entries.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.calendarExportEmpty)),
        );
        return;
      }
      final String ics = icsFromCalendarEntries(
        data.entries,
        calendarName: l10n.calendarExportCalendarName,
      );
      await widget.shareService.share(
        AppDocument(
          filename: 'campus-koethen-kalender.ics',
          mediaType: 'text/calendar',
          bytes: Uint8List.fromList(utf8.encode(ics)),
        ),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.calendarExportFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The scrollable header shared by all views: per-source error banners and
/// (when needed) the "pick a course" hint.
///
/// One source failing never removes the others — the banner says which one is
/// missing and the rest of the calendar keeps its data.
List<Widget> _calendarHeader(BuildContext context, CalendarData data) {
  final AppLocalizations l10n = context.l10n;
  final AppMetrics metrics = context.metrics;
  Widget banner(
    String title, {
    String? message,
    StatusTone tone = StatusTone.warning,
    IconData icon = AppIcons.sync_problem,
    Widget? action,
  }) => Padding(
    padding: EdgeInsets.fromLTRB(
      metrics.screenPadding,
      AppSpacing.sm,
      metrics.screenPadding,
      0,
    ),
    child: StatusBanner(
      tone: tone,
      icon: icon,
      title: title,
      message: message,
      action: action,
    ),
  );
  return <Widget>[
    switch (data.timetableState) {
      CalendarTimetableState.hidden => banner(
        l10n.calendarTimetableHidden,
        tone: StatusTone.info,
        icon: AppIcons.visibility_off_outlined,
        action: OutlinedButton(
          onPressed: () => showCalendarSourcesSheet(context),
          child: Text(l10n.calendarSourcesLabel),
        ),
      ),
      CalendarTimetableState.disabled => banner(
        l10n.timetableDisabledTitle,
        message: l10n.timetableDisabledMessage,
        icon: AppIcons.cloud_off_outlined,
      ),
      CalendarTimetableState.needsGroup => const _GroupHint(),
      CalendarTimetableState.pending => banner(
        l10n.timetablePendingTitle,
        message: l10n.timetablePendingMessage,
        tone: StatusTone.info,
        icon: AppIcons.schedule_outlined,
      ),
      CalendarTimetableState.unavailable => banner(
        l10n.calendarTimetableUnavailable,
      ),
      CalendarTimetableState.loading ||
      CalendarTimetableState.ready => const SizedBox.shrink(),
    },
    if (data.hasMoodleError) banner(l10n.calendarMoodleUnavailable),
    // The third source had a flag and a string and no banner, so a failed
    // public-calendar load looked exactly like a day with nothing scheduled.
    // "Not happening" and "we could not ask" are the two readings this
    // header exists to keep apart.
    if (data.hasPublicCalendarError) banner(l10n.calendarPublicUnavailable),
  ];
}

/// Day, week or list — and nothing else on the line.
class _ViewControls extends ConsumerWidget {
  const _ViewControls({required this.mode});

  final CalendarViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppMetrics metrics = context.metrics;
    // Icon *and* label do not fit three segments onto a 320 px phone once the
    // user scales text up. The label is what gets dropped, never the control:
    // the icon keeps its tooltip and its accessible name, so nothing is lost
    // for a screen reader.
    final bool roomForLabels =
        MediaQuery.textScalerOf(context).scale(14) < 20 ||
        MediaQuery.sizeOf(context).width > 360;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.screenPadding,
        AppSpacing.md,
        metrics.screenPadding,
        0,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SegmentedButton<CalendarViewMode>(
          showSelectedIcon: false,
          segments: <ButtonSegment<CalendarViewMode>>[
            ButtonSegment<CalendarViewMode>(
              value: CalendarViewMode.day,
              icon: const Icon(AppIcons.view_day_outlined),
              tooltip: l10n.calendarViewDay,
              label: roomForLabels ? Text(l10n.calendarViewDay) : null,
            ),
            ButtonSegment<CalendarViewMode>(
              value: CalendarViewMode.week,
              icon: const Icon(AppIcons.grid_on_outlined),
              tooltip: l10n.calendarViewWeek,
              label: roomForLabels ? Text(l10n.calendarViewWeek) : null,
            ),
            ButtonSegment<CalendarViewMode>(
              value: CalendarViewMode.list,
              icon: const Icon(AppIcons.view_agenda_outlined),
              tooltip: l10n.calendarViewList,
              label: roomForLabels ? Text(l10n.calendarViewList) : null,
            ),
          ],
          selected: <CalendarViewMode>{mode},
          onSelectionChanged: (Set<CalendarViewMode> selection) =>
              ref.read(calendarViewModeProvider.notifier).set(selection.first),
        ),
      ),
    );
  }
}

class _GroupHint extends ConsumerWidget {
  const _GroupHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppMetrics metrics = context.metrics;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.screenPadding,
        AppSpacing.sm,
        metrics.screenPadding,
        0,
      ),
      child: StatusBanner(
        icon: AppIcons.schedule_outlined,
        title: l10n.calendarSelectGroupHint,
        action: FilledButton(
          onPressed: () => showTimetableGroupPickerSheet(context, ref),
          // Names the action, not the source: "Stundenplan" is what the
          // control above already says.
          child: Text(l10n.timetableGroupPickerTitle),
        ),
      ),
    );
  }
}

/// The primary view: a week strip and the chosen day, drawn on the rail.
///
/// Horizontal swiping moves a day at a time, which is how a phone calendar is
/// expected to behave; the strip above shows where in the week that lands.
class _DayAgendaView extends ConsumerWidget {
  const _DayAgendaView({required this.data});

  final CalendarData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final DateTime focused = ref.watch(calendarFocusedDayProvider);
    final DateTime now = DateTime.now();
    final DateTime today = TimetableWeek.dayOf(now);
    final List<CalendarEntry> entries = data.forDay(focused);
    final bool isToday = TimetableWeek.dayOf(focused) == today;

    // From the same index the day list below reads, so a dot can never sit
    // under a different day than the entry it announces.
    final Map<DateTime, int> counts = data.entryCountsByDay;

    return Column(
      children: <Widget>[
        WeekStrip(
          selected: focused,
          today: today,
          entryCounts: counts,
          // Every day an entry actually occupies, not only the day it starts:
          // otherwise a multi-day entry leaves the strip blank on days where
          // the list right below it shows the entry.
          eventDays: data.eventDays,
          onSelect: (DateTime day) =>
              ref.read(calendarFocusedDayProvider.notifier).select(day),
          // A swipe on the strip is a week; a swipe on the day below is a day.
          // Two gestures, two areas — neither can swallow the other.
          onShiftWeeks: (int delta) =>
              ref.read(calendarFocusedDayProvider.notifier).shiftWeeks(delta),
          onToday: () => ref.read(calendarFocusedDayProvider.notifier).today(),
        ),
        Expanded(
          child: GestureDetector(
            // A day per swipe. `primaryVelocity` is negative when the finger
            // moves left, which means "forward" in a left-to-right calendar.
            onHorizontalDragEnd: (DragEndDetails details) {
              final double velocity = details.primaryVelocity ?? 0;
              if (velocity == 0) return;
              ref
                  .read(calendarFocusedDayProvider.notifier)
                  .shiftDays(velocity < 0 ? 1 : -1);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: <Widget>[
                ..._calendarHeader(context, data),
                SectionHeader(
                  label: AppDateFormats.weekdayDate(focused, locale),
                ),
                if (entries.isEmpty)
                  // `data.isLoading` exists for exactly this and was never
                  // read: an empty day during the initial load claimed "no
                  // entries" before any source had answered.
                  data.isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.xxl,
                          ),
                          child: LoadingView(),
                        )
                      : RailGap(
                          height: AppSpacing.xxxl,
                          label: l10n.calendarNoEntriesForDay,
                        )
                else
                  ..._railFor(
                    context: context,
                    entries: entries,
                    locale: locale,
                    now: isToday ? now : null,
                    l10n: l10n,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Lays the day out on the rail and drops the "now" line into the right gap.
///
/// The line goes before the first entry that has not started yet; if the day is
/// already over it closes the list instead. Either way the reader sees where
/// they are without counting rows.
List<Widget> _railFor({
  required BuildContext context,
  required List<CalendarEntry> entries,
  required String locale,
  required DateTime? now,
  required AppLocalizations l10n,
}) {
  final List<Widget> children = <Widget>[];
  bool nowPlaced = now == null;

  for (final CalendarEntry entry in entries) {
    final DateTime start = entry.start.toLocal();
    if (!nowPlaced && start.isAfter(now!)) {
      children.add(_nowRule(now: now, locale: locale, l10n: l10n));
      nowPlaced = true;
    }
    children.add(_EntryRow(entry: entry, locale: locale, now: now));
  }

  if (!nowPlaced) {
    children.add(_nowRule(now: now!, locale: locale, l10n: l10n));
  }
  return children;
}

/// The line drawn straight across the rail at the current time.
///
/// One definition for both the day agenda and the list view, so the two can
/// never label the same moment differently.
Widget _nowRule({
  required DateTime now,
  required String locale,
  required AppLocalizations l10n,
}) => NowRule(
  time: AppDateFormats.time(now, locale),
  semanticLabel: '${l10n.todayNowLabel}, ${AppDateFormats.time(now, locale)}',
);

/// One appointment on the rail — and, when the plan knows it, its room.
///
/// The room is a control **in the row**. It used to take three steps to get
/// from a lecture to where it is: tap the row, read the sheet, press the room.
/// The sheet is still there for everything else the entry knows, but the one
/// thing a reader wants while walking across campus is now one tap away.
class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.entry,
    required this.locale,
    required this.now,
  });

  final CalendarEntry entry;
  final String locale;

  /// The current time, or `null` when the day being read is not today.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    final DateTime start = entry.start.toLocal();
    final DateTime? end = entry.end?.toLocal();

    // A deadline has no duration, so it is never "now" — it is ahead of you or
    // it is behind you. Treating its start as its end says exactly that.
    final DateTime finish = end ?? start;
    final DateTime? currentTime = now;
    final TimeRailEmphasis emphasis;
    if (currentTime == null) {
      emphasis = TimeRailEmphasis.normal;
    } else if (!start.isAfter(currentTime) && finish.isAfter(currentTime)) {
      emphasis = TimeRailEmphasis.now;
    } else if (!finish.isAfter(currentTime)) {
      emphasis = TimeRailEmphasis.past;
    } else {
      emphasis = TimeRailEmphasis.normal;
    }

    // Source is always conveyed with a text label (and an icon), never by
    // colour alone; the public-calendar colour is an extra decorative accent.
    final String sourceLabel = switch (entry.source) {
      CalendarSource.moodle => l10n.calendarSourceMoodle,
      CalendarSource.timetable => l10n.calendarSourceTimetable,
      CalendarSource.canteenFavourite =>
        entry.sourceLabel ?? l10n.calendarSourceCanteenFavourite,
      CalendarSource.publicCalendar ||
      CalendarSource.postEvent ||
      CalendarSource.savedEvents =>
        entry.sourceLabel ?? l10n.calendarSourcePublic,
    };

    final List<String> meta = <String>[
      sourceLabel,
      if (entry.isCancelled) l10n.timetableStatusCancelled,
      if (entry.subtitle != null && entry.subtitle!.isNotEmpty) entry.subtitle!,
    ];

    // Only a room the bundled plan can actually show becomes a control. An
    // older app with a newer catalogue knows the name but has no geometry, and
    // a link into an empty map is worse than plain text.
    //
    // The guard comes first so a row that names no room never subscribes to
    // the room index at all — most entries in a day are exactly that.
    final Room? room;
    List<String> unmappedTimetableRooms = const <String>[];
    if (entryMayNameRoom(entry)) {
      final RoomResolver resolver = ref.watch(roomResolverProvider);
      final MapCatalog? catalog = ref.watch(mapCatalogProvider).value;
      room = roomsForEntry(
        resolver,
        entry,
      ).where((Room r) => catalog?.geometryFor(r.roomKey) != null).firstOrNull;
      if (entry.details case TimetableCalendarDetails(:final rooms)) {
        unmappedTimetableRooms = rooms.where((String designation) {
          final Room? candidate = resolver.resolveDesignation(designation);
          return candidate == null ||
              catalog?.geometryFor(candidate.roomKey) == null;
        }).toList();
      }
    } else {
      room = null;
    }

    // CAL-4: `TimeRailTile` takes a `semanticLabel` and nobody was passing one,
    // so a screen reader read a calendar row as loose fragments — a time, then
    // a title, then a source — instead of one entry. The room is included for
    // the same reason it is on the timetable card: it is what the reader is
    // usually after.
    final String semanticLabel = <String>[
      if (entry.allDay)
        '${l10n.calendarWeekAllDay}, '
            '${AppDateFormats.weekdayDate(entry.day, locale)}'
      else
        end == null
            ? AppDateFormats.time(start, locale)
            : l10n.timetableTimeRange(
                AppDateFormats.time(start, locale),
                AppDateFormats.time(end, locale),
              ),
      entry.title.isEmpty ? sourceLabel : entry.title,
      ...meta,
      if (room != null)
        room.displayName ?? room.roomNumber
      else if (entry.location != null && entry.location!.isNotEmpty)
        entry.location!,
    ].join(', ');

    return TimeRailTile(
      semanticLabel: semanticLabel,
      start: entry.allDay ? null : AppDateFormats.time(start, locale),
      end: entry.allDay || end == null
          ? null
          : AppDateFormats.time(end, locale),
      emphasis: emphasis,
      tint: entry.colorArgb == null ? null : Color(entry.colorArgb!),
      onTap: () => showCalendarEntrySheet(context, entry),
      trailing: Icon(
        AppIcons.chevron_right,
        size: AppSizes.icon,
        color: colors.textSecondary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (entry.allDay)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                l10n.calendarWeekAllDay,
                style: context.type.dataSmall,
              ),
            ),
          Text(
            entry.title.isEmpty ? sourceLabel : entry.title,
            style: text.titleMedium?.copyWith(
              decoration: entry.isCancelled ? TextDecoration.lineThrough : null,
            ),
          ),
          if (meta.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(meta.join(' · '), style: text.bodySmall),
          ],
          if (emphasis == TimeRailEmphasis.now) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            // The marker on the rail says "now" to the eye; this says it in
            // words, which is what a screen reader and a greyscale screen get.
            Text(
              l10n.todayNowLabel,
              style: text.labelSmall?.copyWith(color: colors.textPrimary),
            ),
          ],
          if (room != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _RoomChip(room: room),
          ] else if (unmappedTimetableRooms.isEmpty &&
              entry.location != null &&
              entry.location!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(entry.location!, style: text.bodySmall),
          ],
          for (final String designation in unmappedTimetableRooms) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            UnmappedRoomSearchRow(
              label: designation,
              textStyle: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// The room, as a control that goes straight to the plan.
class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;

    return Semantics(
      button: true,
      label: l10n.campusMapShowRoom(room.displayName ?? room.roomNumber),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => openRoomOnMap(context, room.roomKey),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: colors.outline.withValues(alpha: 0.56),
              width: AppSizes.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                AppIcons.place_outlined,
                size: AppSizes.iconSmall,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              // A room number is a code, so it is set in the data face.
              Text(
                room.displayName ?? room.roomNumber,
                style: context.type.dataSmall.copyWith(color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The optional graphical week.
class _WeekView extends ConsumerWidget {
  const _WeekView({required this.data});

  final CalendarData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppMetrics metrics = context.metrics;
    final String locale = Localizations.localeOf(context).languageCode;
    final DateTime focused = ref.watch(calendarFocusedDayProvider);
    final bool showWeekend = ref.watch(calendarShowWeekendProvider);

    return Column(
      children: <Widget>[
        ..._calendarHeader(context, data),
        Padding(
          padding: EdgeInsets.fromLTRB(
            metrics.screenPadding,
            AppSpacing.md,
            metrics.screenPadding,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Navigation always stays with the month. The week-range picker
              // has its own line below, so neither large text nor a narrow
              // phone can push one of the arrows away from its context.
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      AppDateFormats.monthAndYear(focused, locale),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: l10n.calendarToday,
                    onPressed: () =>
                        ref.read(calendarFocusedDayProvider.notifier).today(),
                    icon: const Icon(AppIcons.today_outlined),
                  ),
                  IconButton(
                    tooltip: l10n.calendarPreviousWeek,
                    onPressed: () => ref
                        .read(calendarFocusedDayProvider.notifier)
                        .shiftWeeks(-1),
                    icon: const Icon(AppIcons.chevron_left),
                  ),
                  IconButton(
                    tooltip: l10n.calendarNextWeek,
                    onPressed: () => ref
                        .read(calendarFocusedDayProvider.notifier)
                        .shiftWeeks(1),
                    icon: const Icon(AppIcons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // Both ranges on screen, the current one picked. A single chip
              // reading "Wochenende" left the reader to work out whether it
              // was showing the weekend or hiding it — naming the two weeks
              // outright answers that before it is asked.
              _WeekRangePicker(showWeekend: showWeekend),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            // A week per swipe, exactly like the arrows above the day
            // agenda — the two navigation paths agree on what one swipe
            // means. `onHorizontalDragEnd` only ever claims the horizontal
            // axis, so the grid's own vertical (hour) scrolling is untouched.
            onHorizontalDragEnd: (DragEndDetails details) {
              final double velocity = details.primaryVelocity ?? 0;
              if (velocity == 0) return;
              ref
                  .read(calendarFocusedDayProvider.notifier)
                  .shiftWeeks(velocity < 0 ? 1 : -1);
            },
            child: WeekGridView(
              weekStart: TimetableWeek.startOf(focused),
              entries: data.entries,
              today: TimetableWeek.dayOf(DateTime.now()),
              selected: focused,
              dayCount: ref.watch(calendarWeekDayCountProvider),
              onSelectDay: (DateTime day) {
                ref.read(calendarFocusedDayProvider.notifier).select(day);
                // Picking a day in the week grid is how you get to that day.
                ref
                    .read(calendarViewModeProvider.notifier)
                    .set(CalendarViewMode.day);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Teaching week or full week, as the two weeks themselves.
///
/// "Mo–Fr" is read at a glance but cannot be heard, so each segment carries
/// the range written out as its accessible name and as its tooltip.
class _WeekRangePicker extends ConsumerWidget {
  const _WeekRangePicker({required this.showWeekend});

  final bool showWeekend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;

    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      segments: <ButtonSegment<bool>>[
        ButtonSegment<bool>(
          value: false,
          label: Semantics(
            label: l10n.calendarWeekRangeWorkdaysSemantic,
            excludeSemantics: true,
            child: Text(l10n.calendarWeekRangeWorkdays),
          ),
          tooltip: l10n.calendarWeekRangeWorkdaysSemantic,
        ),
        ButtonSegment<bool>(
          value: true,
          label: Semantics(
            label: l10n.calendarWeekRangeFullSemantic,
            excludeSemantics: true,
            child: Text(l10n.calendarWeekRangeFull),
          ),
          tooltip: l10n.calendarWeekRangeFullSemantic,
        ),
      ],
      selected: <bool>{showWeekend},
      onSelectionChanged: (Set<bool> selection) =>
          ref.read(calendarShowWeekendProvider.notifier).set(selection.first),
    );
  }
}

/// Everything there is, day by day, on one continuous rail.
class _ListView extends ConsumerWidget {
  const _ListView({required this.data});

  final CalendarData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    if (data.entries.isEmpty) {
      return ListView(
        children: <Widget>[
          ..._calendarHeader(context, data),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: data.isLoading
                ? const LoadingView()
                : Text(l10n.calendarNoEntries, textAlign: TextAlign.center),
          ),
        ],
      );
    }

    final DateTime now = DateTime.now();
    final DateTime today = TimetableWeek.dayOf(now);
    final List<CalendarListRow> rows = _listRows(
      header: _calendarHeader(context, data),
      entries: data.entries,
      today: today,
      now: now,
    );

    // The backend's full horizon is far more than one screen, so the rows are
    // described first and built as they scroll into view. Building them all
    // up front cost a full screen's worth of work many times over on every
    // rebuild — the same reason the Moodle course tabs stopped doing it.
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int index) => switch (rows[index]) {
        StaticCalendarListRow(:final Widget child) => child,
        DayHeadingCalendarListRow(:final DateTime day) => SectionHeader(
          label: AppDateFormats.weekdayDate(day, locale),
        ),
        NowRuleCalendarListRow(:final DateTime at) => _nowRule(
          now: at,
          locale: locale,
          l10n: l10n,
        ),
        EntryCalendarListRow(
          :final CalendarEntry entry,
          :final DateTime? now,
        ) =>
          _EntryRow(entry: entry, locale: locale, now: now),
      },
    );
  }
}

/// Delegates pure row planning so this screen only maps presentation models
/// to lazily built widgets.
List<CalendarListRow> _listRows({
  required List<Widget> header,
  required List<CalendarEntry> entries,
  required DateTime today,
  required DateTime now,
}) {
  return buildCalendarListRows(
    header: header,
    entries: entries,
    today: today,
    now: now,
  );
}
