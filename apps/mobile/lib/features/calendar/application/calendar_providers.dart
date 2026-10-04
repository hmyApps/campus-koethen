// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/loaded.dart';
import '../../../core/prefs/preference_keys.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/time/clock.dart';
import '../../../l10n/l10n.dart';
import '../../canteen/application/canteen_filter_controller.dart';
import '../../canteen/application/canteen_providers.dart';
import '../../canteen/data/canteen_models.dart';
import '../../canteen/domain/canteen_filter.dart';
import '../../events/application/saved_events_controller.dart';
import '../../events/domain/saved_event_snapshot.dart';
import '../../mail/application/exchange_calendar_providers.dart';
import '../../mail/application/mail_account_controller.dart';
import '../../mail/domain/exchange_calendar_event.dart';
import '../../moodle/application/moodle_account_controller.dart';
import '../../moodle/application/moodle_controller.dart';
import '../../timetable/application/timetable_providers.dart';
import '../../timetable/application/timetable_lesson_info_filter.dart';
import '../../timetable/application/timetable_week.dart';
import '../../timetable/data/timetable_models.dart';
import '../domain/calendar_entry.dart';
import '../domain/public_calendar.dart';
import 'calendar_merge.dart';
import 'public_calendar_providers.dart';

/// Day agenda or month list — the two explicit calendar views.
///
/// The day agenda is the default. A month grid used to be, but on a phone it
/// spends most of the screen answering "which day?" and leaves almost none for
/// what is actually on that day; the week strip answers the same question in a
/// fraction of the space. A month is now only reachable as a date picker.
enum CalendarViewMode { day, week, list }

class CalendarViewModeController extends Notifier<CalendarViewMode> {
  @override
  CalendarViewMode build() => CalendarViewMode.day;

  void set(CalendarViewMode mode) => state = mode;

  /// Cycles through the views. Kept for the keyboard/back affordances that
  /// call it; the segmented control sets a mode directly.
  void toggle() => state = switch (state) {
    CalendarViewMode.day => CalendarViewMode.week,
    CalendarViewMode.week => CalendarViewMode.list,
    CalendarViewMode.list => CalendarViewMode.day,
  };
}

final NotifierProvider<CalendarViewModeController, CalendarViewMode>
calendarViewModeProvider =
    NotifierProvider<CalendarViewModeController, CalendarViewMode>(
      CalendarViewModeController.new,
    );

/// The day the calendar is focused on. The visible month and the timetable
/// weeks to load are derived from it, so navigation can never drift apart.
class CalendarFocusedDayController extends Notifier<DateTime> {
  @override
  DateTime build() => TimetableWeek.dayOf(DateTime.now());

  void select(DateTime day) => state = TimetableWeek.dayOf(day);
  void today() => select(DateTime.now());

  /// Moves [days] days, DST-safe.
  ///
  /// The day views used to step with `focused.add(Duration(days: 1))`. On a
  /// 25-hour day that lands back on the same calendar date, so the forward
  /// swipe was simply a no-op once a year — the same trap `shiftWeeks` below
  /// already documents.
  void shiftDays(int days) => state = TimetableWeek.shift(state, days);

  /// Moves [weeks] weeks, keeping the weekday.
  ///
  /// Whole weeks rather than 7×24 hours: adding a `Duration` across a daylight
  /// saving change lands an hour off and can fall on the day before.
  void shiftWeeks(int weeks) =>
      state = TimetableWeek.shift(state, weeks * TimetableWeek.lengthInDays);
}

final NotifierProvider<CalendarFocusedDayController, DateTime>
calendarFocusedDayProvider =
    NotifierProvider<CalendarFocusedDayController, DateTime>(
      CalendarFocusedDayController.new,
    );

/// Injectable because the list view is a rolling window anchored to today,
/// independent of whichever day the day/week views currently focus.
final Provider<Clock> calendarClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// Number of columns the week view draws without the weekend.
const int kWorkWeekDays = 5;

/// Whether the week view also draws Saturday and Sunday.
///
/// Off by default: a teaching week is Monday to Friday, and two empty columns
/// cost a fifth of the width of a phone. Purely local, like every other view
/// preference — nothing about it reaches a backend.
class CalendarWeekendController extends Notifier<bool> {
  @override
  bool build() =>
      ref
          .watch(keyValueStoreProvider)
          .getInt(PreferenceKeys.calendarShowWeekend) ==
      1;

  Future<void> set(bool value) async {
    state = value;
    // Written in both directions, so "off" is a decision the store remembers
    // rather than the absence of one.
    await ref
        .read(keyValueStoreProvider)
        .setInt(PreferenceKeys.calendarShowWeekend, value ? 1 : 0);
  }

  Future<void> toggle() => set(!state);
}

final NotifierProvider<CalendarWeekendController, bool>
calendarShowWeekendProvider = NotifierProvider<CalendarWeekendController, bool>(
  CalendarWeekendController.new,
);

/// How many day columns the week view draws.
final Provider<int> calendarWeekDayCountProvider = Provider<int>(
  (Ref ref) => ref.watch(calendarShowWeekendProvider)
      ? TimetableWeek.lengthInDays
      : kWorkWeekDays,
);

/// Which sources contribute to the calendar.
///
/// Every source is on by default and the user can hide any of them without
/// losing the others' data. The choice is persisted as the **disabled** set:
/// a source added in a later version is then visible by default rather than
/// hidden until someone finds the filter.
class CalendarEnabledSourcesController extends Notifier<Set<CalendarSource>> {
  @override
  Set<CalendarSource> build() {
    final Set<CalendarSource> off =
        (ref
                    .watch(keyValueStoreProvider)
                    .getStringList(PreferenceKeys.calendarDisabledSources) ??
                const <String>[])
            .map(CalendarSource.fromStorage)
            .whereType<CalendarSource>()
            .toSet();
    return kMergeableCalendarSources
        .where((CalendarSource source) => !off.contains(source))
        .toSet();
  }

  Future<void> toggle(CalendarSource source) async {
    final Set<CalendarSource> next = <CalendarSource>{...state};
    if (!next.remove(source)) next.add(source);
    state = next;
    await ref
        .read(keyValueStoreProvider)
        .setStringList(
          PreferenceKeys.calendarDisabledSources,
          kMergeableCalendarSources
              .where((CalendarSource s) => !next.contains(s))
              .map((CalendarSource s) => s.storageValue)
              .toList(growable: false),
        );
  }
}

final NotifierProvider<CalendarEnabledSourcesController, Set<CalendarSource>>
calendarEnabledSourcesProvider =
    NotifierProvider<CalendarEnabledSourcesController, Set<CalendarSource>>(
      CalendarEnabledSourcesController.new,
    );

/// The "Meine gemerkten Events" switch — an eigenständiger optional source,
/// off by default, entirely separate from [calendarEnabledSourcesProvider]'s
/// disabled-set (see [kMergeableCalendarSources]'s own doc comment on why
/// [CalendarSource.savedEvents] is excluded from it).
class CalendarSavedEventsEnabledController extends Notifier<bool> {
  @override
  bool build() =>
      ref
          .watch(keyValueStoreProvider)
          .getInt(PreferenceKeys.calendarSavedEventsEnabled) ==
      1;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(keyValueStoreProvider)
        .setInt(PreferenceKeys.calendarSavedEventsEnabled, value ? 1 : 0);
  }

  Future<void> toggle() => set(!state);
}

final NotifierProvider<CalendarSavedEventsEnabledController, bool>
calendarSavedEventsEnabledProvider =
    NotifierProvider<CalendarSavedEventsEnabledController, bool>(
      CalendarSavedEventsEnabledController.new,
    );

/// Whether the preferred canteen's favourited dishes appear on the calendar —
/// off by default, same reasoning as [CalendarSavedEventsEnabledController]:
/// an opt-in overlay, not part of the classic merge every install starts with.
/// Reachable from both the calendar's own sources sheet and the canteen
/// screen, so there is exactly one switch, never two independent ones that
/// could drift apart.
class CalendarShowFavouriteMealsController extends Notifier<bool> {
  @override
  bool build() =>
      ref
          .watch(keyValueStoreProvider)
          .getInt(PreferenceKeys.calendarShowFavouriteMeals) ==
      1;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(keyValueStoreProvider)
        .setInt(PreferenceKeys.calendarShowFavouriteMeals, value ? 1 : 0);
  }

  Future<void> toggle() => set(!state);
}

final NotifierProvider<CalendarShowFavouriteMealsController, bool>
calendarShowFavouriteMealsProvider =
    NotifierProvider<CalendarShowFavouriteMealsController, bool>(
      CalendarShowFavouriteMealsController.new,
    );

/// The merged calendar plus per-source status. Every source is isolated: a
/// timetable error never removes Moodle deadlines, and a Moodle error never
/// hides the timetable.
enum CalendarTimetableState {
  hidden,
  loading,
  disabled,
  needsGroup,
  pending,
  ready,
  unavailable,
}

@immutable
class CalendarData {
  CalendarData({
    required this.entries,
    required this.enabledSources,
    this.timetableLoading = false,
    this.hasTimetableError = false,
    this.needsGroup = false,
    this.moodleConnected = false,
    this.hasMoodleError = false,
    this.moodleLoading = false,
    this.publicCalendarsLoading = false,
    this.hasPublicCalendarError = false,
    this.exchangeCalendarConnected = false,
    this.exchangeCalendarLoading = false,
    this.hasExchangeCalendarError = false,
    CalendarTimetableState? timetableState,
  }) : timetableState =
           timetableState ??
           (!enabledSources.contains(CalendarSource.timetable)
               ? CalendarTimetableState.hidden
               : hasTimetableError
               ? CalendarTimetableState.unavailable
               : needsGroup
               ? CalendarTimetableState.needsGroup
               : timetableLoading
               ? CalendarTimetableState.loading
               : CalendarTimetableState.ready);

  final List<CalendarEntry> entries;
  final Set<CalendarSource> enabledSources;
  final bool timetableLoading;
  final bool hasTimetableError;

  /// One explicit state for the timetable calendar source. Keeping this in
  /// the merged view model prevents the UI from inferring configuration,
  /// selection and sync state from an empty list.
  final CalendarTimetableState timetableState;

  /// No timetable group chosen yet.
  final bool needsGroup;

  final bool moodleConnected;
  final bool hasMoodleError;

  final bool moodleLoading;
  final bool publicCalendarsLoading;
  final bool exchangeCalendarConnected;
  final bool exchangeCalendarLoading;

  /// Whether any enabled source has yet to answer.
  ///
  /// Read by every view that would otherwise render "nothing scheduled" over
  /// a load still in flight — a statement the app cannot yet make.
  bool get isLoading =>
      timetableLoading ||
      moodleLoading ||
      publicCalendarsLoading ||
      exchangeCalendarLoading;
  final bool hasPublicCalendarError;
  final bool hasExchangeCalendarError;

  /// Built on first use and then reused: every reader below asks about the
  /// same, unchanged list, and a fresh [CalendarData] is what a changed list
  /// produces. Lazy rather than eager because a screen that only reports a
  /// source error never asks any of these questions.
  late final CalendarDayIndex _index = CalendarDayIndex.of(entries);

  List<CalendarEntry> forDay(DateTime day) => _index.forDay(day);

  /// Entries per day for the week strip, from the index [forDay] uses.
  Map<DateTime, int> get entryCountsByDay => _index.countsByStartDay;

  late final Set<DateTime> _eventDays = calendarEventDays(entries);

  Set<DateTime> get eventDays => _eventDays;
}

/// The Monday of each week overlapping the month of [day].
List<DateTime> monthWeekStarts(DateTime day) {
  final DateTime firstOfMonth = DateTime(day.year, day.month, 1);
  final DateTime lastOfMonth = DateTime(day.year, day.month + 1, 0);
  final List<DateTime> starts = <DateTime>[];
  DateTime cursor = TimetableWeek.startOf(firstOfMonth);
  while (!cursor.isAfter(lastOfMonth)) {
    starts.add(cursor);
    cursor = TimetableWeek.shift(cursor, TimetableWeek.lengthInDays);
  }
  return starts;
}

/// Inclusive date bounds for the rolling calendar list.
@immutable
class CalendarDateWindow {
  CalendarDateWindow({required DateTime from, required DateTime to})
    : from = calendarDayKey(from),
      to = calendarDayKey(to);

  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is CalendarDateWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The backend's advertised horizon, shifted with today so a cached catalogue
/// does not gradually shorten the list. Older deployments keep their former
/// 120-day window until they can provide the metadata.
CalendarDateWindow calendarListWindow(
  DateTime now,
  String? availableFrom,
  String? availableTo,
) {
  final DateTime today = calendarDayKey(now);
  final DateTime? parsedFrom = availableFrom == null
      ? null
      : DateTime.tryParse(availableFrom);
  final DateTime? parsedTo = availableTo == null
      ? null
      : DateTime.tryParse(availableTo);
  final int? horizonDays = parsedFrom == null || parsedTo == null
      ? null
      : DateTime.utc(parsedTo.year, parsedTo.month, parsedTo.day)
            .difference(
              DateTime.utc(parsedFrom.year, parsedFrom.month, parsedFrom.day),
            )
            .inDays;
  final DateTime end = horizonDays == null
      ? TimetableWeek.shift(today, 119)
      : TimetableWeek.shift(today, horizonDays < 0 ? 0 : horizonDays);
  return CalendarDateWindow(from: today, to: end);
}

/// Breaks an inclusive range into backend-sized requests without gaps.
List<CalendarDateWindow> splitCalendarWindow(
  CalendarDateWindow window,
  int maxDays,
) {
  if (maxDays < 1) throw ArgumentError.value(maxDays, 'maxDays');
  final List<CalendarDateWindow> parts = <CalendarDateWindow>[];
  DateTime cursor = window.from;
  while (!cursor.isAfter(window.to)) {
    final DateTime candidate = TimetableWeek.shift(cursor, maxDays - 1);
    final DateTime end = candidate.isAfter(window.to) ? window.to : candidate;
    parts.add(CalendarDateWindow(from: cursor, to: end));
    cursor = TimetableWeek.shift(end, 1);
  }
  return parts;
}

/// The list has no future cut-off: Moodle and saved entries can be arbitrarily
/// far ahead, while backend sources supply their own advertised horizons.
List<CalendarEntry> calendarEntriesFrom(
  Iterable<CalendarEntry> entries,
  DateTime from,
) => entries
    .where((CalendarEntry entry) => !entry.day.isBefore(calendarDayKey(from)))
    .toList(growable: false);

/// The aggregated calendar for the month around [anchor].
///
/// Keyed by an explicit anchor date, **not** by the calendar screen's focused
/// day. The day dashboard asks about today while the calendar screen may be
/// browsing March; sharing one focus would silently make one of the two show
/// the wrong month. Callers say which day they mean.
/// Auto-disposed, like the two families below it. Every day someone browses to
/// creates a family entry, and without disposal each one lives — together with
/// the merged month behind it — until the process ends. What it holds is purely
/// derived: nothing here fetches, so releasing it costs a re-merge from data the
/// week and event providers already hold, never another request.
final calendarDataProvider = Provider.family<CalendarData, DateTime>(
  (Ref ref, DateTime anchor) => ref.watch(
    _calendarMonthDataProvider(DateTime(anchor.year, anchor.month)),
  ),
  isAutoDispose: true,
);

/// The month-keyed provider [calendarDataProvider] delegates to.
///
/// Everything below depends on the anchor's **month** and on nothing finer —
/// `monthWeekStarts` reads only the year and the month. Keyed by the day, every
/// step through the week strip created a fresh family entry that re-merged and
/// re-indexed the whole month's entries to produce a list identical to the one
/// the previous day already held. Normalising the key to the first of the month
/// makes day navigation inside a month free, and leaves the public provider's
/// contract — "pass the day you mean" — untouched.
/// Auto-disposed: a `CalendarData` carries the whole month's merged entries, its
/// day index and its set of event days, and a session that browses half a year
/// would otherwise keep every one of those months in memory for good. The
/// timetable weeks, public-calendar months and Moodle deadlines it reads are
/// their own, non-disposing providers, so returning to a month re-merges from
/// what is already there.
final _calendarMonthDataProvider = Provider.family<CalendarData, DateTime>((
  Ref ref,
  DateTime anchor,
) {
  final List<DateTime> weeks = monthWeekStarts(anchor);
  final bool publicEnabled = ref
      .watch(calendarEnabledSourcesProvider)
      .contains(CalendarSource.publicCalendar);
  return _buildCalendarData(
    ref,
    timetableWeekStarts: weeks,
    publicCalendarEntries: publicEnabled
        ? ref.watch(publicCalendarMonthEntriesProvider(anchor))
        : const AsyncData<List<CalendarEntry>>(<CalendarEntry>[]),
    exchangeWindow: CalendarDateWindow(
      from: weeks.first,
      to: TimetableWeek.shift(weeks.last, TimetableWeek.lengthInDays - 1),
    ),
  );
}, isAutoDispose: true);

/// The list reads every source to the horizon advertised by its backend.
final calendarListDataProvider = Provider.family<CalendarData, DateTime>(
  (Ref ref, DateTime today) =>
      ref.watch(_calendarListDataProvider(calendarDayKey(today))),
  isAutoDispose: true,
);

final _calendarListDataProvider = Provider.family<CalendarData, DateTime>((
  Ref ref,
  DateTime today,
) {
  final String? groupId = ref.watch(selectedTimetableGroupIdProvider);
  final bool publicEnabled = ref
      .watch(calendarEnabledSourcesProvider)
      .contains(CalendarSource.publicCalendar);
  final AsyncValue<Loaded<TimetableGroup>?>? selectedGroup = groupId == null
      ? null
      : ref.watch(selectedTimetableGroupProvider);
  final List<CalendarDateWindow> timetableRanges =
      selectedGroup != null &&
          selectedGroup.isLoading &&
          selectedGroup.value == null
      ? const <CalendarDateWindow>[]
      : splitCalendarWindow(
          calendarListWindow(
            today,
            selectedGroup?.value?.meta.from,
            selectedGroup?.value?.meta.to,
          ),
          42,
        );
  final CalendarDateWindow listWindow = calendarListWindow(
    today,
    selectedGroup?.value?.meta.from,
    selectedGroup?.value?.meta.to,
  );
  return _buildCalendarData(
    ref,
    timetableWeekStarts: const <DateTime>[],
    timetableRanges: timetableRanges,
    timetableMetadataLoading: selectedGroup?.isLoading ?? false,
    publicCalendarEntries: publicEnabled
        ? ref.watch(publicCalendarListEntriesProvider(today))
        : const AsyncData<List<CalendarEntry>>(<CalendarEntry>[]),
    windowFrom: today,
    exchangeWindow: listWindow,
  );
}, isAutoDispose: true);

/// A one-shot export view over every enabled source and its complete known
/// range. Backend sources use their advertised absolute bounds (including
/// history) instead of the list view's rolling "from today" window. Personal
/// Exchange has no advertised retention contract, so its explicit export
/// window is one year back through two years ahead.
final Provider<CalendarData>
calendarExportDataProvider = Provider<CalendarData>((Ref ref) {
  final DateTime today = calendarDayKey(ref.watch(calendarClockProvider).now());
  final Set<CalendarSource> enabled = ref.watch(calendarEnabledSourcesProvider);
  final String? groupId = ref.watch(selectedTimetableGroupIdProvider);
  final AsyncValue<Loaded<TimetableGroup>?>? selectedGroup = groupId == null
      ? null
      : ref.watch(selectedTimetableGroupProvider);

  final List<CalendarDateWindow> timetableRanges;
  if (!enabled.contains(CalendarSource.timetable) || groupId == null) {
    timetableRanges = const <CalendarDateWindow>[];
  } else if (selectedGroup?.value case final Loaded<TimetableGroup> group) {
    timetableRanges = splitCalendarWindow(
      _absoluteOrFallbackWindow(today, group.meta.from, group.meta.to),
      42,
    );
  } else {
    timetableRanges = const <CalendarDateWindow>[];
  }

  final AsyncValue<List<CalendarEntry>> publicEntries;
  if (!enabled.contains(CalendarSource.publicCalendar)) {
    publicEntries = const AsyncData<List<CalendarEntry>>(<CalendarEntry>[]);
  } else {
    final AsyncValue<Loaded<List<PublicCalendar>>> catalogue = ref.watch(
      publicCalendarsCatalogProvider,
    );
    final Loaded<List<PublicCalendar>>? loaded = catalogue.value;
    if (loaded != null) {
      publicEntries = ref.watch(
        publicCalendarRangeEntriesProvider(
          _absoluteOrFallbackWindow(today, loaded.meta.from, loaded.meta.to),
        ),
      );
    } else if (catalogue.hasError) {
      publicEntries = AsyncError<List<CalendarEntry>>(
        catalogue.error!,
        catalogue.stackTrace ?? StackTrace.current,
      );
    } else {
      publicEntries = const AsyncLoading<List<CalendarEntry>>();
    }
  }

  return _buildCalendarData(
    ref,
    timetableWeekStarts: const <DateTime>[],
    timetableRanges: timetableRanges,
    timetableMetadataLoading:
        enabled.contains(CalendarSource.timetable) &&
        groupId != null &&
        (selectedGroup?.isLoading ?? false),
    publicCalendarEntries: publicEntries,
    exchangeWindow: CalendarDateWindow(
      from: DateTime(today.year - 1, today.month, today.day),
      to: DateTime(today.year + 2, today.month, today.day),
    ),
  );
}, isAutoDispose: true);

CalendarDateWindow _absoluteOrFallbackWindow(
  DateTime today,
  String? availableFrom,
  String? availableTo,
) {
  final DateTime? from = _metadataDay(availableFrom);
  final DateTime? to = _metadataDay(availableTo);
  if (from != null && to != null && !to.isBefore(from)) {
    return CalendarDateWindow(from: from, to: to);
  }
  return CalendarDateWindow(from: today, to: TimetableWeek.shift(today, 119));
}

DateTime? _metadataDay(String? value) {
  final DateTime? parsed = value == null ? null : DateTime.tryParse(value);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

CalendarData _buildCalendarData(
  Ref ref, {
  required List<DateTime> timetableWeekStarts,
  required AsyncValue<List<CalendarEntry>> publicCalendarEntries,
  List<CalendarDateWindow>? timetableRanges,
  bool timetableMetadataLoading = false,
  DateTime? windowFrom,
  CalendarDateWindow? exchangeWindow,
}) {
  final Set<CalendarSource> enabled = ref.watch(calendarEnabledSourcesProvider);
  final TimetableLessonInfoFilter lessonInfoFilter = ref.watch(
    timetableLessonInfoFilterProvider,
  );

  // --- Source 1: timetable (Campus API), one week provider per visible week.
  final List<CalendarEntry> timetableEntries = <CalendarEntry>[];
  bool timetableLoading = timetableMetadataLoading;
  bool timetableError = false;
  bool needsGroup = false;
  CalendarTimetableState timetableState = CalendarTimetableState.hidden;
  if (enabled.contains(CalendarSource.timetable)) {
    timetableState = CalendarTimetableState.loading;
    final String? groupId = ref.watch(selectedTimetableGroupIdProvider);
    if (groupId == null) {
      // Without a selection, the small status endpoint answers availability;
      // opening the calendar must not download the group catalogue.
      final AsyncValue<Loaded<TimetableStatus>> status = ref.watch(
        timetableStatusProvider,
      );
      final Loaded<TimetableStatus>? loadedStatus = status.value;
      if (loadedStatus == null) {
        if (status.hasError) {
          timetableError = true;
          timetableState = CalendarTimetableState.unavailable;
        } else {
          timetableLoading = true;
        }
      } else if (!loadedStatus.value.featureEnabled) {
        timetableLoading = false;
        timetableState = CalendarTimetableState.disabled;
      } else {
        timetableLoading = false;
        needsGroup = true;
        timetableState = CalendarTimetableState.needsGroup;
      }
    } else {
      timetableLoading = false;
      timetableState = CalendarTimetableState.ready;
      void takeLoaded(Loaded<Timetable> loaded) {
        timetableEntries.addAll(
          timetableToCalendarEntries(
            loaded.value,
            include: lessonInfoFilter.acceptsEntry,
          ),
        );
        final CalendarTimetableState loadedState =
            loaded.meta.featureEnabled == false
            ? CalendarTimetableState.disabled
            : switch (TimetableDataState.fromWire(loaded.meta.dataState)) {
                TimetableDataState.ready => CalendarTimetableState.ready,
                TimetableDataState.pending => CalendarTimetableState.pending,
                TimetableDataState.unavailable =>
                  CalendarTimetableState.unavailable,
                TimetableDataState.unknown =>
                  CalendarTimetableState.unavailable,
              };
        timetableState = _mergeTimetableState(timetableState, loadedState);
      }

      if (timetableRanges != null) {
        for (final CalendarDateWindow range in timetableRanges) {
          final AsyncValue<Loaded<Timetable>> result = ref.watch(
            timetableRangeProvider(
              TimetableRangeRequest(
                groupId: groupId,
                from: range.from,
                to: range.to,
              ),
            ),
          );
          result.when(
            data: takeLoaded,
            loading: () {
              timetableLoading = true;
              timetableState = _mergeTimetableState(
                timetableState,
                CalendarTimetableState.loading,
              );
            },
            error: (_, _) {
              timetableError = true;
              timetableState = _mergeTimetableState(
                timetableState,
                CalendarTimetableState.unavailable,
              );
            },
          );
        }
      } else {
        for (final DateTime weekStart in timetableWeekStarts) {
          final AsyncValue<Loaded<Timetable>> week = ref.watch(
            timetableWeekProvider(
              TimetableWeekRequest(groupId: groupId, weekStart: weekStart),
            ),
          );
          week.when(
            data: takeLoaded,
            loading: () {
              timetableLoading = true;
              timetableState = _mergeTimetableState(
                timetableState,
                CalendarTimetableState.loading,
              );
            },
            error: (_, _) {
              timetableError = true;
              timetableState = _mergeTimetableState(
                timetableState,
                CalendarTimetableState.unavailable,
              );
            },
          );
        }
      }
    }
  }

  // --- Source 2: Moodle deadlines (direct, cached). Fully independent.
  final List<CalendarEntry> moodleEntries = <CalendarEntry>[];
  bool moodleError = false;
  bool moodleLoading = false;
  final bool moodleConnected =
      ref.watch(moodleAccountControllerProvider).value != null;
  if (enabled.contains(CalendarSource.moodle) && moodleConnected) {
    final AsyncValue<MoodleOverviewState> moodle = ref.watch(
      moodleControllerProvider,
    );
    final MoodleOverviewState? view = moodle.value;
    // The other two sources report their loading state; Moodle did not, so a
    // connected account whose deadlines were still being read counted as a
    // source that had answered with nothing.
    if (view == null && moodle.isLoading) moodleLoading = true;
    if (view != null) {
      moodleEntries.addAll(moodleDeadlinesToCalendarEntries(view.deadlines));
      if (view.error != null) moodleError = true;
      if (view.isSyncing && view.courses.isEmpty) moodleLoading = true;
    }
  }

  // --- Source 3: public Google calendars (via Campus API). Independent too.
  final List<CalendarEntry> publicEntries = <CalendarEntry>[];
  bool publicLoading = false;
  bool publicError = false;
  if (enabled.contains(CalendarSource.publicCalendar)) {
    publicCalendarEntries.when(
      data: (List<CalendarEntry> entries) => publicEntries.addAll(entries),
      loading: () => publicLoading = true,
      error: (_, _) => publicError = true,
    );
  }

  // --- Source 4 (optional, opt-in): "Meine gemerkten Events". Independent
  // too, and deduplicated against the live public-calendar entries above via
  // the events feature's own reusable dedup rule — never a second
  // implementation of it.
  final List<CalendarEntry> savedEventEntries = <CalendarEntry>[];
  if (ref.watch(calendarSavedEventsEnabledProvider)) {
    final List<SavedEventSnapshot> saved =
        ref.watch(savedEventsControllerProvider).value ??
        const <SavedEventSnapshot>[];
    final List<PublicCalendar> catalog =
        ref.watch(publicCalendarsCatalogProvider).value?.value ??
        const <PublicCalendar>[];
    final Map<String, String?> channelSlugByCalendarSlug = <String, String?>{
      for (final PublicCalendar c in catalog) c.slug: c.channelSlug,
    };
    savedEventEntries.addAll(
      savedEventEntriesForCalendar(
        saved: saved,
        liveEntries: publicEntries,
        channelSlugByCalendarSlug: channelSlugByCalendarSlug,
      ),
    );
  }

  // --- Source 5 (optional, opt-in): favourited dishes on the preferred
  // canteen's own menu. Independent of every other source — a canteen error
  // never removes the timetable, and vice versa.
  final List<CalendarEntry> canteenFavouriteEntries = <CalendarEntry>[];
  if (ref.watch(calendarShowFavouriteMealsProvider)) {
    final Set<String> favourites = ref.watch(
      canteenFilterProvider.select((CanteenFilter f) => f.favourites),
    );
    final String? canteenSlug = ref.watch(selectedCanteenSlugProvider);
    if (favourites.isNotEmpty && canteenSlug != null) {
      final CanteenMenu? menu = ref
          .watch(canteenMenuProvider(canteenSlug))
          .value
          ?.value;
      if (menu != null) {
        canteenFavouriteEntries.addAll(
          canteenFavouriteMealsToCalendarEntries(menu, favourites),
        );
      }
    }
  }

  // --- Source 6 (optional, opt-in): personal Exchange appointments. The
  // provider reads credentials just in time from secure storage and retains
  // neither credentials nor events after this window is disposed.
  final bool exchangeEnabled = ref.watch(
    settingsProvider.select(
      (AppSettings settings) => settings.mailExchangeCalendarEnabled,
    ),
  );
  final bool exchangeConnected =
      ref.watch(mailAccountControllerProvider).value?.isSignedIn ?? false;
  final List<CalendarEntry> exchangeEntries = <CalendarEntry>[];
  bool exchangeLoading = false;
  bool exchangeError = false;
  if (exchangeEnabled && exchangeConnected && exchangeWindow != null) {
    final AsyncValue<List<ExchangeCalendarEvent>> exchange = ref.watch(
      exchangeCalendarEventsProvider(
        ExchangeCalendarQuery(from: exchangeWindow.from, to: exchangeWindow.to),
      ),
    );
    exchange.when(
      data: (List<ExchangeCalendarEvent> events) {
        final AppLocalizations l10n = lookupAppLocalizations(
          ref.watch(activeLocaleProvider),
        );
        exchangeEntries.addAll(
          exchangeEventsToCalendarEntries(
            events,
            untitledTitle: l10n.calendarExchangeUntitled,
          ),
        );
      },
      loading: () => exchangeLoading = true,
      error: (_, _) => exchangeError = true,
    );
  }

  final bool savedEventsEnabled = ref.watch(calendarSavedEventsEnabledProvider);
  final bool favouriteMealsEnabled = ref.watch(
    calendarShowFavouriteMealsProvider,
  );
  final Set<CalendarSource> effectiveEnabled = <CalendarSource>{
    ...enabled,
    if (savedEventsEnabled) CalendarSource.savedEvents,
    if (favouriteMealsEnabled) CalendarSource.canteenFavourite,
    if (exchangeEnabled) CalendarSource.exchangeCalendar,
  };

  final List<CalendarEntry> merged = mergeCalendarEntries(<CalendarEntry>[
    ...timetableEntries,
    ...moodleEntries,
    ...publicEntries,
    ...savedEventEntries,
    ...canteenFavouriteEntries,
    ...exchangeEntries,
  ]);
  return CalendarData(
    entries: windowFrom == null
        ? merged
        : calendarEntriesFrom(merged, windowFrom),
    enabledSources: effectiveEnabled,
    timetableLoading: timetableLoading,
    moodleLoading: moodleLoading,
    hasTimetableError: timetableError,
    needsGroup: needsGroup,
    timetableState: timetableState,
    moodleConnected: moodleConnected,
    hasMoodleError: moodleError,
    publicCalendarsLoading: publicLoading,
    hasPublicCalendarError: publicError,
    exchangeCalendarConnected: exchangeConnected,
    exchangeCalendarLoading: exchangeLoading,
    hasExchangeCalendarError: exchangeError,
  );
}

CalendarTimetableState _mergeTimetableState(
  CalendarTimetableState current,
  CalendarTimetableState next,
) {
  int priority(CalendarTimetableState state) => switch (state) {
    CalendarTimetableState.ready => 0,
    CalendarTimetableState.hidden => 1,
    CalendarTimetableState.needsGroup => 2,
    CalendarTimetableState.loading => 3,
    CalendarTimetableState.pending => 4,
    CalendarTimetableState.unavailable => 5,
    CalendarTimetableState.disabled => 6,
  };
  return priority(next) > priority(current) ? next : current;
}

/// The aggregated calendar for the day the calendar screen is focused on.
///
/// A thin convenience over [calendarDataProvider] so the screen does not have
/// to repeat the lookup; everything else passes the date it actually cares
/// about.
final Provider<CalendarData> focusedCalendarDataProvider =
    Provider<CalendarData>((Ref ref) {
      if (ref.watch(calendarViewModeProvider) == CalendarViewMode.list) {
        final DateTime today = calendarDayKey(
          ref.watch(calendarClockProvider).now(),
        );
        return ref.watch(calendarListDataProvider(today));
      }
      return ref.watch(
        calendarDataProvider(ref.watch(calendarFocusedDayProvider)),
      );
    });

/// Every entry of one day, chronologically, across all enabled sources.
///
/// This is what the day dashboard reads. All-day items come first, then timed
/// ones in order — the order a person reads a day in.
/// Auto-disposed for the same reason as [calendarDataProvider]: one entry per
/// day anyone has looked at, all of them purely derived.
final dayAgendaProvider = Provider.family<DayAgenda, DateTime>((
  Ref ref,
  DateTime date,
) {
  final DateTime day = DateTime(date.year, date.month, date.day);
  final CalendarData data = ref.watch(calendarDataProvider(day));
  final List<CalendarEntry> entries = data.forDay(day);
  return DayAgenda(date: day, entries: entries, data: data);
}, isAutoDispose: true);

/// One day's entries plus the load state of the sources behind them.
@immutable
class DayAgenda {
  const DayAgenda({
    required this.date,
    required this.entries,
    required this.data,
  });

  final DateTime date;
  final List<CalendarEntry> entries;
  final CalendarData data;

  /// Whether any source is still loading. Used to tell "nothing today" apart
  /// from "not known yet" — showing an empty day while data is in flight would
  /// state something false.
  bool get isLoading => data.isLoading;

  /// True when every source that could contribute failed.
  bool get allSourcesFailed =>
      entries.isEmpty && data.hasTimetableError && data.hasPublicCalendarError;

  /// The entry happening at [now], or the next one after it.
  ///
  /// Returns `null` once the day is over — a dashboard card then says so
  /// rather than pointing at something that already finished.
  CalendarEntry? currentOrNext(DateTime now) {
    CalendarEntry? next;
    for (final CalendarEntry entry in entries) {
      if (entry.allDay) continue;
      final DateTime end = entry.end ?? entry.start;
      if (!now.isBefore(entry.start) && now.isBefore(end)) return entry;
      if (entry.start.isAfter(now)) {
        if (next == null || entry.start.isBefore(next.start)) next = entry;
      }
    }
    return next;
  }

  /// Everything still ahead at [now], excluding [currentOrNext].
  List<CalendarEntry> upcomingAfter(DateTime now) {
    final CalendarEntry? lead = currentOrNext(now);
    return entries
        .where(
          (CalendarEntry e) =>
              e.id != lead?.id && (e.allDay || (e.end ?? e.start).isAfter(now)),
        )
        .toList(growable: false);
  }
}
