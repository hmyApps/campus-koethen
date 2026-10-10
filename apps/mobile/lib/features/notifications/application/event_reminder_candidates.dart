// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/locale/formatters.dart';
import '../../../core/locale/locale_providers.dart';
import '../../calendar/application/calendar_merge.dart';
import '../../calendar/application/public_calendar_providers.dart';
import '../../calendar/domain/calendar_entry.dart';
import '../../calendar/domain/public_calendar.dart';
import '../../events/application/saved_events_controller.dart';
import '../../events/domain/saved_event_snapshot.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/delivery_window.dart';
import '../domain/notification_category.dart';
import '../domain/notification_request.dart';
import 'daily_summary_providers.dart' show notificationPlanningDayProvider;
import 'notification_providers.dart';
import 'notification_settings_controller.dart';

/// N1 · `event.reminder` — at most one locally configured reminder per event
/// (ADR-0001 amendment of 2026-10-07).
///
/// This file holds the whole category: the entries it is allowed to look at,
/// the rule that turns one of them into a request, and the text that request
/// carries. The planner below it stays a pure function and learns nothing
/// about calendars.

/// How far ahead the public-calendar side of the scope reaches.
///
/// The current month **and the next one**, because a reminder is due the day
/// before its event: an event on the first of next month is reminded about on
/// the last day of this one, and a horizon of "this month" would have nothing
/// to remind about. Two months is also comfortably more than the sixty-slot
/// budget can hold (ADR-0001 § 7.5), so widening it further would only cost
/// work whose result is dropped.
///
/// Saved events have no horizon at all — they are a local Hive box and are
/// always fully in scope, however far out they lie.
const int kEventReminderHorizonMonths = 2;

/// Default lead. Every selected lead remains an **absolute duration** rather
/// than a wall-clock rule across daylight-saving changes.
const Duration kEventReminderLead = Duration(hours: 24);

/// The already-localised text of one reminder.
///
/// An interface rather than an `AppLocalizations` argument so that
/// [eventReminderRequests] stays a pure function that can be tested with
/// fixed strings — the planner's own convention, one level up.
abstract interface class EventReminderCopy {
  /// `Morgen: Campus Sommerfest 2026`, the `Heute` variant when the reminder
  /// is delivered on the day of the event itself, or
  /// `Mittwoch, 22. Juli: Campus Sommerfest 2026` when it is delivered two or
  /// more days ahead.
  String title(CalendarEntry entry, {required EventReminderDay day});

  /// `Morgen um 16:00 Uhr, Campuswiese.`
  String body(CalendarEntry entry, {required EventReminderDay day});
}

/// The event's day, seen from the day the reminder is delivered on.
@immutable
class EventReminderDay {
  const EventReminderDay({required this.daysAhead, required this.date});

  /// Calendar days from delivery to the event: `0` today, `1` tomorrow.
  ///
  /// Counted on the calendar, not in 24-hour blocks: a reminder at 20:00 the
  /// evening before a 19:30 event on the night the clocks go forward is only
  /// 22.5 hours ahead, and still "tomorrow".
  final int daysAhead;

  /// The event's calendar day; only its date parts are meaningful.
  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is EventReminderDay &&
      other.daysAhead == daysAhead &&
      other.date == date;

  @override
  int get hashCode => Object.hash(daysAhead, date);
}

/// Whole calendar days from the date of [from] to the date of [to].
///
/// Built from the date parts in UTC, where every day has 24 hours, so a
/// daylight-saving change in between never turns into a day more or less.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The sources N1 is allowed to read (ADR-0001 § 7.2).
///
/// Deliberately a closed set rather than "everything the calendar merged":
/// Lectures remain excluded, while Moodle deadlines use their own neutral,
/// configurable category rather than the event category. Both sources are
/// entries in exactly the same merged list. A source added to
/// [CalendarSource] later is therefore out of scope until somebody names it
/// here, which is a product decision.
const Set<CalendarSource> kEventReminderSources = <CalendarSource>{
  CalendarSource.publicCalendar,
  CalendarSource.savedEvents,
};

/// Turns the in-scope calendar entries into one reminder request each.
///
/// A pure function: no provider, no clock of its own, no platform. What it
/// drops, and why:
///
/// * a source that is not [kEventReminderSources] — lectures have no
///   individual reminder; Moodle deadlines are handled by their own provider;
/// * `isCancelled` — a cancelled event is not something to look forward to;
/// * an event that has already started, and a desired instant already past.
///   The planner drops past moments too, but doing it here as well keeps the
///   rule readable where it is stated rather than only as a side effect;
/// * nothing else. In particular an `allDay` entry is kept: it has a defined
///   `start`, and the configured lead applies to it unchanged.
///
/// Deduplication is **not** done here. It has already happened in
/// [notificationEventEntriesProvider], through the events feature's own
/// reusable rule, and the planner's duplicate-key drop is the last net below
/// that — three chances for the same event to produce two reminders, none of
/// which it takes.
List<NotificationRequest> eventReminderRequests({
  required Iterable<CalendarEntry> entries,
  required tz.TZDateTime now,
  required EventReminderCopy copy,
  Duration defaultLead = kEventReminderLead,
  Map<String, int> overrides = const <String, int>{},
}) {
  final tz.Location location = now.location;
  final List<NotificationRequest> requests = <NotificationRequest>[];

  for (final CalendarEntry entry in entries) {
    if (!kEventReminderSources.contains(entry.source)) continue;
    if (entry.isCancelled) continue;

    final tz.TZDateTime start = tz.TZDateTime.from(entry.start, location);
    if (!start.isAfter(now)) continue;

    final int? overrideMinutes = overrides[entry.id];
    if (overrideMinutes == -1) continue;
    final Duration lead = overrideMinutes == null
        ? defaultLead
        : Duration(minutes: overrideMinutes);

    final tz.TZDateTime desired = start.subtract(lead);
    // The same shift the planner will apply to this trigger — asked here only
    // to choose the wording of the day. Both call [DeliveryWindow] with the
    // event start as the target, so the text and the schedule cannot disagree
    // about which day the reminder lands on, and a short lead before an early,
    // late or all-day event falls back to the latest 20:00 before it rather
    // than arriving after it has begun.
    final tz.TZDateTime delivered = DeliveryWindow.shiftIntoWindowBefore(
      desired,
      start,
    );
    if (!delivered.isAfter(now)) continue;

    // An all-day date is read from its own fields, exactly as the calendar
    // shows it (`calendarDayOf`); a timed event on the dial of the device zone.
    final DateTime eventDate = entry.allDay
        ? calendarDayOf(entry.start, allDay: true)
        : DateTime(start.year, start.month, start.day);
    final EventReminderDay day = EventReminderDay(
      daysAhead: calendarDaysBetween(delivered, eventDate),
      date: eventDate,
    );

    requests.add(
      NotificationRequest(
        category: NotificationCategory.eventReminder,
        // Taken over, never re-derived: `CalendarEntry.id` is already stable
        // and source-prefixed (ADR-0001 § 4.1, § 7.6).
        target: entry.id,
        trigger: AbsoluteTrigger(desired, before: start),
        title: copy.title(entry, day: day),
        body: copy.body(entry, day: day),
        // Public campus data: title, time and place may show on the lock
        // screen (P9, ADR-0001 § 7.7).
        visibility: NotificationVisibility.publicContent,
      ),
    );
  }

  return requests;
}

/// The merged, deduplicated event stock N1 plans from.
///
/// Two sources, and deliberately **not** the calendar screen's own
/// `CalendarData`: that one applies the display switches, and a notification's
/// scope is the notification settings plus the activated public calendars —
/// never a view filter (ADR-0001 § 7.2).
///
/// * **Public calendars**, only from the reader's activated selection, over
///   [kEventReminderHorizonMonths]. Read as `.value`, never awaited: a plan
///   must never wait on a network answer, and a month still in flight simply
///   contributes nothing to *this* run — Riverpod rebuilds the plan when it
///   arrives.
/// * **Saved events**, independent of the calendar's "Meine gemerkten Events"
///   switch, minus the ones that are cancelled or orphaned. An orphaned entry
///   is one a successful load of its own source no longer contained;
///   reminding about it would be reminding about something that is gone.
///
/// The two are deduplicated with `savedEventEntriesForCalendar`, the events
/// feature's own reusable rule, so a bookmarked event that is also a live
/// calendar entry appears exactly once — and therefore produces exactly one
/// reminder (ADR-0001 § 7.3, "genau eine").
final Provider<List<CalendarEntry>> notificationEventEntriesProvider =
    Provider<List<CalendarEntry>>((Ref ref) {
      // The planning day, not a clock read: the clock is no app state and
      // would never rebuild this provider, so an app left open across the end
      // of a month would keep the old two-month horizon (VF-N03).
      // `NotificationHost` moves the planning day on at midnight and on resume.
      final DateTime today = ref.watch(notificationPlanningDayProvider);

      final List<CalendarEntry> live = <CalendarEntry>[];
      for (int i = 0; i < kEventReminderHorizonMonths; i++) {
        final DateTime month = DateTime(today.year, today.month + i);
        live.addAll(
          ref.watch(publicCalendarMonthEntriesProvider(month)).value ??
              const <CalendarEntry>[],
        );
      }

      final List<SavedEventSnapshot> saved =
          (ref.watch(savedEventsControllerProvider).value ??
                  const <SavedEventSnapshot>[])
              .where((SavedEventSnapshot s) => !s.isOrphaned && !s.isCancelled)
              .toList(growable: false);

      final List<PublicCalendar> catalog =
          ref.watch(publicCalendarsCatalogProvider).value?.value ??
          const <PublicCalendar>[];

      return mergeCalendarEntries(<CalendarEntry>[
        ...live,
        ...savedEventEntriesForCalendar(
          saved: saved,
          liveEntries: live,
          channelSlugByCalendarSlug: <String, String?>{
            for (final PublicCalendar c in catalog) c.slug: c.channelSlug,
          },
        ),
      ]);
    });

/// The entry a tapped `event.reminder` payload points at, or `null`.
///
/// The payload carries a `CalendarEntry.id` and nothing else (ADR-0001 § 7.6),
/// so this is the "Auflösung der Kennung gegen den zusammengeführten Bestand"
/// of § 7.8. `null` is an ordinary answer, not an error: the event may have
/// been removed from its calendar, or the bookmark deleted, since the
/// reminder was scheduled.
final calendarEntryForNotificationProvider =
    Provider.family<CalendarEntry?, String>((Ref ref, String id) {
      for (final CalendarEntry entry in ref.watch(
        notificationEventEntriesProvider,
      )) {
        if (entry.id == id) return entry;
      }
      return null;
    });

/// N1's contribution to the plan.
final Provider<List<NotificationRequest>> eventReminderCandidatesProvider =
    Provider<List<NotificationRequest>>((Ref ref) {
      final tz.Location? location = ref
          .watch(notificationLocationProvider)
          .value;
      // Without a resolved zone there is no local 07:00–20:00 window. The
      // plan is empty until it arrives.
      if (location == null) return const <NotificationRequest>[];

      final preferences = ref.watch(notificationSettingsProvider);
      return eventReminderRequests(
        entries: ref.watch(notificationEventEntriesProvider),
        now: tz.TZDateTime.from(
          ref.watch(notificationClockProvider).now(),
          location,
        ),
        copy: ref.watch(eventReminderCopyProvider),
        defaultLead: Duration(minutes: preferences.eventReminderMinutes),
        overrides: preferences.eventReminderOverrides,
      );
    });

/// The reminder text in the app's current language.
///
/// Watches the locale, so a language change re-plans every reminder — one of
/// the triggers of ADR-0001 § 7.1, and here it needs no trigger list at all.
final Provider<EventReminderCopy> eventReminderCopyProvider =
    Provider<EventReminderCopy>((Ref ref) {
      final String code = ref.watch(localeCodeProvider);
      return LocalisedEventReminderCopy(
        l10n: lookupAppLocalizations(ref.watch(activeLocaleProvider)),
        localeCode: code,
      );
    });

/// [EventReminderCopy] over the generated localisations.
class LocalisedEventReminderCopy implements EventReminderCopy {
  const LocalisedEventReminderCopy({
    required this.l10n,
    required this.localeCode,
  });

  final AppLocalizations l10n;
  final String localeCode;

  @override
  String title(CalendarEntry entry, {required EventReminderDay day}) =>
      switch (day.daysAhead) {
        0 => l10n.notificationEventReminderTitleToday(entry.title),
        1 => l10n.notificationEventReminderTitleTomorrow(entry.title),
        _ => l10n.notificationEventReminderTitleOnDate(_date(day), entry.title),
      };

  @override
  String body(CalendarEntry entry, {required EventReminderDay day}) {
    final String when;
    if (entry.allDay) {
      when = switch (day.daysAhead) {
        0 => l10n.notificationEventReminderWhenTodayAllDay,
        1 => l10n.notificationEventReminderWhenTomorrowAllDay,
        _ => l10n.notificationEventReminderWhenOnDateAllDay(_date(day)),
      };
    } else {
      final String time = AppDateFormats.time(entry.start, localeCode);
      when = switch (day.daysAhead) {
        0 => l10n.notificationEventReminderWhenToday(time),
        1 => l10n.notificationEventReminderWhenTomorrow(time),
        _ => l10n.notificationEventReminderWhenOnDate(_date(day), time),
      };
    }
    final String? place = entry.location?.trim();
    return place == null || place.isEmpty
        ? l10n.notificationEventReminderBody(when)
        : l10n.notificationEventReminderBodyWithLocation(when, place);
  }

  /// `Mittwoch, 22. Juli` · `Wednesday, July 22` — weekday and date, no year:
  /// the longest lead is a week.
  String _date(EventReminderDay day) =>
      DateFormat.MMMMEEEEd(localeCode).format(day.date);
}
