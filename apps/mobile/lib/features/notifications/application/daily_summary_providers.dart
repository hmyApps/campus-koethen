// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/loaded.dart';
import '../../../l10n/l10n.dart';
import '../../calendar/application/calendar_merge.dart';
import '../../calendar/application/public_calendar_providers.dart';
import '../../calendar/domain/calendar_entry.dart';
import '../../calendar/domain/public_calendar.dart';
import '../../canteen/application/canteen_filter_controller.dart';
import '../../canteen/application/canteen_providers.dart';
import '../../canteen/data/canteen_models.dart';
import '../../canteen/domain/canteen_filter.dart';
import '../../events/application/saved_events_controller.dart';
import '../../events/domain/saved_event_snapshot.dart';
import '../../moodle/application/moodle_account_controller.dart';
import '../../moodle/application/moodle_controller.dart';
import '../../timetable/application/timetable_lesson_info_filter.dart';
import '../../timetable/application/timetable_providers.dart';
import '../../timetable/application/timetable_week.dart';
import '../../timetable/data/timetable_models.dart';
import '../domain/notification_category.dart';
import '../domain/notification_permission.dart';
import '../domain/notification_preferences.dart';
import '../domain/notification_request.dart';
import 'daily_summary.dart';
import 'daily_summary_content.dart';
import 'notification_providers.dart';
import 'notification_settings_controller.dart';
import 'saved_event_scope.dart';

/// The local calendar day every planning contributor treats as "today".
///
/// A provider rather than a `DateTime.now()` inside each contributor, for one
/// reason: the planning horizon has to move on when the day does. An app left
/// open overnight would otherwise keep yesterday's fourteen days and quietly
/// plan one day fewer with every night that passes. `NotificationHost` calls
/// [NotificationPlanningDayController.refresh] at midnight and on resume, and
/// every contributor watching this rebuilds.
class NotificationPlanningDayController extends Notifier<DateTime> {
  @override
  DateTime build() => _today();

  DateTime _today() {
    final DateTime now = ref.read(notificationClockProvider).now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Moves to the current day, if it has actually changed. Comparing first
  /// keeps a resume that happens on the same day from invalidating every
  /// candidate list for nothing.
  void refresh() {
    final DateTime today = _today();
    if (today != state) state = today;
  }
}

final NotifierProvider<NotificationPlanningDayController, DateTime>
notificationPlanningDayProvider =
    NotifierProvider<NotificationPlanningDayController, DateTime>(
      NotificationPlanningDayController.new,
    );

/// The `daily.summary` candidates — one per non-empty day of the horizon.
///
/// Everything it reads is a source the app already keeps locally, through the
/// very providers the screens use: the timetable of the **selected group**,
/// the events of the **activated public calendars** plus the reader's saved
/// events, the cached Moodle deadlines and the cached canteen menu. There is
/// no second cache, no second fetch path and no second mapper anywhere in
/// here — only the existing ones, read and combined.
///
/// Watching those providers is also the entire update mechanism (ADR-0001
/// § 7.1). A newly fetched timetable, a bookmarked event, a changed group, a
/// different canteen, a Moodle sync, a language change — each one rebuilds
/// this list, and the planner replaces the whole registered set. Cancelling a
/// stale overview is not a code path; it is what happens when this list stops
/// producing it.
///
/// **Nothing is read at all until the reader has opted in and the operating
/// system allows delivery.** The planner would drop every candidate in that
/// state anyway, so building them would be work with no effect — and, more to
/// the point, it would pull the timetable, the calendars and the menu over the
/// network at every cold start for somebody who never asked for a single
/// notification.
final Provider<List<NotificationRequest>> dailySummaryCandidatesProvider =
    Provider<List<NotificationRequest>>((Ref ref) {
      final NotificationPreferences preferences = ref.watch(
        notificationSettingsProvider,
      );
      if (!preferences.optedIn ||
          !preferences.isCategoryEnabled(NotificationCategory.dailySummary)) {
        return const <NotificationRequest>[];
      }
      final NotificationPermissionStatus? permission = ref
          .watch(notificationPermissionProvider)
          .value;
      if (permission == null || !permission.allowsDelivery) {
        return const <NotificationRequest>[];
      }

      final DateTime today = ref.watch(notificationPlanningDayProvider);
      final DateTime lastDay = DateTime(
        today.year,
        today.month,
        today.day + kDailySummaryHorizonDays - 1,
      );

      final List<DailySummaryDay> days = buildDailySummaryDays(
        firstDay: today,
        entries: <CalendarEntry>[
          ..._timetableEntries(ref, today, lastDay),
          ..._eventEntries(ref, today, lastDay),
          ..._moodleEntries(ref),
        ],
        canteenByDay: _canteenByDay(ref),
      );

      // Resolved from the chosen locale rather than from a `BuildContext`:
      // this runs above the widget tree, and the text of a notification the
      // operating system will show in three days has to be written now.
      final AppLocalizations l10n = lookupAppLocalizations(
        ref.watch(activeLocaleProvider),
      );
      final String localeCode = ref.watch(localeCodeProvider);

      return <NotificationRequest>[
        for (final DailySummaryDay day in days)
          ?dailySummaryRequest(
            day: day,
            l10n: l10n,
            localeCode: localeCode,
            deliveryMinutes: preferences.dailySummaryMinutes,
          ),
      ];
    });

/// The lectures of every subscribed group across the horizon.
///
/// Nothing at all without a chosen group: there is deliberately no default
/// timetable in the app, and a summary built from someone else's lectures
/// would be worse than none.
Iterable<CalendarEntry> _timetableEntries(
  Ref ref,
  DateTime today,
  DateTime lastDay,
) sync* {
  final List<String> groupIds = ref.watch(selectedTimetableGroupIdsProvider);
  if (groupIds.isEmpty) return;
  final TimetableLessonInfoFilter lessonInfoFilter = ref.watch(
    timetableLessonInfoFilterProvider,
  );
  final Map<String, Set<String>> moduleKeysByGroup = ref.watch(
    selectedTimetableModuleKeysByGroupProvider,
  );
  final Set<String> yielded = <String>{};
  for (
    DateTime weekStart = TimetableWeek.startOf(today);
    !weekStart.isAfter(lastDay);
    weekStart = TimetableWeek.shift(weekStart, TimetableWeek.lengthInDays)
  ) {
    for (final String groupId in groupIds) {
      final Loaded<Timetable>? week = ref
          .watch(
            timetableWeekProvider(
              TimetableWeekRequest(groupId: groupId, weekStart: weekStart),
            ),
          )
          .value;
      if (week == null) continue;
      for (final CalendarEntry entry in timetableToCalendarEntries(
        week.value,
        include: (TimetableEntry entry) =>
            (moduleKeysByGroup[groupId] == null ||
                (entry.moduleKey != null &&
                    moduleKeysByGroup[groupId]!.contains(entry.moduleKey))) &&
            (groupId != lessonInfoFilter.groupId ||
                lessonInfoFilter.acceptsEntry(entry)),
      )) {
        if (yielded.add(entry.id)) yield entry;
      }
    }
  }
}

/// The relevant events: the activated public calendars plus the saved events
/// that no live calendar entry already covers.
///
/// The deduplication is the events feature's own rule, asked rather than
/// reimplemented — a saved bookmark of a calendar occurrence must not turn
/// into a second entry and inflate the day's count.
Iterable<CalendarEntry> _eventEntries(
  Ref ref,
  DateTime today,
  DateTime lastDay,
) {
  final List<CalendarEntry> live = <CalendarEntry>[];
  for (final DateTime anchor in _monthAnchors(today, lastDay)) {
    live.addAll(
      ref.watch(publicCalendarMonthEntriesProvider(anchor)).value ??
          const <CalendarEntry>[],
    );
  }

  // The same bookmarks N1 may remind about: never an orphaned or cancelled
  // one, which would otherwise fill a day with something that is gone (F-04).
  final List<SavedEventSnapshot> saved = notifiableSavedEvents(
    ref.watch(savedEventsControllerProvider).value ??
        const <SavedEventSnapshot>[],
  );
  if (saved.isEmpty) return live;

  final List<PublicCalendar> catalog =
      ref.watch(publicCalendarsCatalogProvider).value?.value ??
      const <PublicCalendar>[];
  return <CalendarEntry>[
    ...live,
    ...savedEventEntriesForCalendar(
      saved: saved,
      liveEntries: live,
      channelSlugByCalendarSlug: <String, String?>{
        for (final PublicCalendar calendar in catalog)
          calendar.slug: calendar.channelSlug,
      },
    ),
  ];
}

/// The cached Moodle deadlines, and only while an account is connected.
///
/// Read from the cache the overview already holds — this never triggers a
/// Moodle call of its own, and no credential is touched here.
Iterable<CalendarEntry> _moodleEntries(Ref ref) {
  if (ref.watch(moodleAccountControllerProvider).value == null) {
    return const <CalendarEntry>[];
  }
  final MoodleOverviewState? overview = ref
      .watch(moodleControllerProvider)
      .value;
  if (overview == null) return const <CalendarEntry>[];
  return moodleDeadlinesToCalendarEntries(overview.deadlines);
}

/// What the preferred canteen offers, per day, reduced to what a notification
/// may say: whether there is a menu at all, and the name of a favourite dish
/// if one is on it.
///
/// The reader's allergen and trait filters are deliberately not applied. They
/// narrow a *list*; a favourite is a dish the reader named themselves, and
/// hiding it here would silently contradict the favourites screen.
Map<DateTime, DailySummaryCanteen> _canteenByDay(Ref ref) {
  final String? slug = ref.watch(selectedCanteenSlugProvider);
  if (slug == null) return const <DateTime, DailySummaryCanteen>{};
  final CanteenMenu? menu = ref.watch(canteenMenuProvider(slug)).value?.value;
  if (menu == null) return const <DateTime, DailySummaryCanteen>{};

  final CanteenFilter filter = ref.watch(canteenFilterProvider);
  final Map<DateTime, DailySummaryCanteen> byDay =
      <DateTime, DailySummaryCanteen>{};
  for (final MenuDay day in menu.days) {
    if (day.meals.isEmpty) continue;
    String? favourite;
    for (final Meal meal in day.meals) {
      if (filter.isFavourite(meal)) {
        favourite = meal.name;
        break;
      }
    }
    byDay[DateTime(day.date.year, day.date.month, day.date.day)] =
        DailySummaryCanteen(hasMenu: true, favouriteMealName: favourite);
  }
  return byDay;
}

/// The first of every month the horizon touches — one or two, never more,
/// because the horizon is shorter than the shortest month.
///
/// The public-calendar provider is keyed by month and normalises its own key,
/// so asking for these anchors reuses whatever the calendar screen has
/// already loaded instead of firing a second request for the same window.
List<DateTime> _monthAnchors(DateTime today, DateTime lastDay) {
  final DateTime first = DateTime(today.year, today.month);
  final DateTime last = DateTime(lastDay.year, lastDay.month);
  return first == last ? <DateTime>[first] : <DateTime>[first, last];
}
