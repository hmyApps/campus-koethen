// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/loaded.dart';
import '../../timetable/application/timetable_week.dart';
import '../data/public_calendars_repository.dart';
import '../domain/calendar_entry.dart';
import '../domain/public_calendar.dart';
import 'calendar_merge.dart';
import 'calendar_providers.dart';
import 'public_calendar_selection.dart';

/// The public-calendar catalogue. Fetching it also folds `defaultSubscribed`
/// into the local selection exactly once per slug (the single place defaults
/// are applied), mirroring the news-channel wiring.
final FutureProvider<Loaded<List<PublicCalendar>>>
publicCalendarsCatalogProvider = FutureProvider<Loaded<List<PublicCalendar>>>((
  Ref ref,
) async {
  final String locale = ref.watch(localeCodeProvider);
  final Loaded<List<PublicCalendar>> loaded = await ref
      .watch(publicCalendarsRepositoryProvider)
      .fetchCalendars(locale: locale);
  await ref
      .read(publicCalendarSelectionProvider.notifier)
      .reconcile(loaded.value);
  return loaded;
}, retry: (_, _) => null);

/// Bounds of the visible month (± a week), as YYYY-MM-DD, for the events query.
({String from, String to}) _monthWindow(DateTime focused) {
  final List<DateTime> weeks = monthWeekStarts(focused);
  final DateTime from = weeks.first;
  final DateTime to = TimetableWeek.shift(
    weeks.last,
    TimetableWeek.lengthInDays,
  );
  String iso(DateTime d) => d.toIso8601String().slice10();
  return (from: iso(from), to: iso(to));
}

/// Public-calendar events for the currently selected calendars in the month
/// around [anchor], already mapped to source-neutral [CalendarEntry] values.
///
/// Keyed by an explicit anchor rather than reading the calendar screen's
/// focused day: the dashboard asks about *today* while the calendar screen may
/// be browsing another month, and a shared focus would make one of them wrong.
///
/// Returns an empty list when nothing is selected — an empty selection means
/// "no public events", never "all". A failure here is isolated by the
/// aggregator and never hides the timetable or Moodle.
///
/// Any two days of the same month ask for the identical window, so the family
/// key is normalised to the first of the month before anything is requested.
/// Keyed by the raw day, every step through the week strip fired a full
/// `/v1/public-calendars/events` request for a range that had just been
/// fetched. Retrying stays switched off on both entries: a failure is surfaced
/// to the aggregator, which isolates it per source.
final publicCalendarMonthEntriesProvider =
    FutureProvider.family<List<CalendarEntry>, DateTime>(
      (Ref ref, DateTime anchor) => ref.watch(
        _monthEntriesProvider(DateTime(anchor.year, anchor.month)).future,
      ),
      retry: (_, _) => null,
    );

final _monthEntriesProvider =
    FutureProvider.family<List<CalendarEntry>, DateTime>((
      Ref ref,
      DateTime anchor,
    ) async {
      final ({String from, String to}) window = _monthWindow(anchor);
      return _loadEntries(ref, from: window.from, to: window.to);
    }, retry: (_, _) => null);

/// Public-calendar events for the full horizon advertised by the backend.
///
/// The outer provider normalises its key to today at local midnight. Rebuilds
/// during the same day therefore reuse the same backend response, while the
/// next day naturally advances both inclusive bounds by one.
final publicCalendarListEntriesProvider =
    FutureProvider.family<List<CalendarEntry>, DateTime>(
      (Ref ref, DateTime today) =>
          ref.watch(_listEntriesProvider(calendarDayKey(today)).future),
      retry: (_, _) => null,
    );

final _listEntriesProvider =
    FutureProvider.family<List<CalendarEntry>, DateTime>(
      (Ref ref, DateTime today) => _loadListEntries(ref, today),
      retry: (_, _) => null,
    );

/// Public-calendar entries for an explicit inclusive export window. Unlike
/// the rolling list provider this preserves the backend's advertised historic
/// lower bound instead of shifting the horizon to today.
final publicCalendarRangeEntriesProvider =
    FutureProvider.family<List<CalendarEntry>, CalendarDateWindow>(
      (Ref ref, CalendarDateWindow window) async {
        final Loaded<List<PublicCalendar>> catalogue = await ref.watch(
          publicCalendarsCatalogProvider.future,
        );
        return _loadWindowEntries(ref, window, catalogue);
      },
      retry: (_, _) => null,
      isAutoDispose: true,
    );

Future<List<CalendarEntry>> _loadListEntries(Ref ref, DateTime today) async {
  final Loaded<List<PublicCalendar>>? catalogue = ref
      .watch(publicCalendarsCatalogProvider)
      .value;
  if (catalogue == null) return const <CalendarEntry>[];
  final PublicCalendarSelectionState selection = ref.watch(
    publicCalendarSelectionProvider,
  );
  final List<String> slugs = PublicCalendarSelectionRules.effectiveSelection(
    available: catalogue.value,
    selected: selection.selectedSlugs,
  );
  if (slugs.isEmpty) return const <CalendarEntry>[];

  final CalendarDateWindow window = calendarListWindow(
    today,
    catalogue.meta.from,
    catalogue.meta.to,
  );
  return _loadWindowEntries(ref, window, catalogue, slugs: slugs);
}

Future<List<CalendarEntry>> _loadWindowEntries(
  Ref ref,
  CalendarDateWindow window,
  Loaded<List<PublicCalendar>> catalogue, {
  List<String>? slugs,
}) async {
  final String locale = ref.watch(localeCodeProvider);
  final PublicCalendarSelectionState selection = ref.watch(
    publicCalendarSelectionProvider,
  );
  final List<String> selected =
      slugs ??
      PublicCalendarSelectionRules.effectiveSelection(
        available: catalogue.value,
        selected: selection.selectedSlugs,
      );
  if (selected.isEmpty) return const <CalendarEntry>[];
  // Old backend versions do not advertise their request limit; they used
  // 120-day list requests, so keep that safe fallback during rollout.
  final int maxDays = catalogue.meta.maxRangeDays ?? 120;
  final PublicCalendarsRepository repository = ref.watch(
    publicCalendarsRepositoryProvider,
  );

  Future<List<PublicCalendarEvent>> load(CalendarDateWindow part) async {
    final Loaded<List<PublicCalendarEvent>> response = await repository
        .fetchEvents(
          locale: locale,
          slugs: selected,
          from: part.from.toIso8601String().slice10(),
          to: part.to.toIso8601String().slice10(),
        );
    if (!response.meta.truncated) return response.value;
    if (!part.from.isBefore(part.to)) {
      throw StateError('Calendar event response remains truncated for one day');
    }
    final int days =
        DateTime.utc(part.to.year, part.to.month, part.to.day)
            .difference(
              DateTime.utc(part.from.year, part.from.month, part.from.day),
            )
            .inDays +
        1;
    final List<CalendarDateWindow> halves = splitCalendarWindow(
      part,
      (days / 2).ceil(),
    );
    final List<List<PublicCalendarEvent>> results = await Future.wait(
      halves.map(load),
    );
    return results.expand((chunk) => chunk).toList(growable: false);
  }

  final List<List<PublicCalendarEvent>> chunks = await Future.wait(
    splitCalendarWindow(window, maxDays).map(load),
  );
  final Map<String, PublicCalendar> bySlug = <String, PublicCalendar>{
    for (final PublicCalendar calendar in catalogue.value)
      calendar.slug: calendar,
  };
  return publicCalendarEventsToCalendarEntries(
    chunks.expand((chunk) => chunk).toList(growable: false),
    bySlug,
  );
}

Future<List<CalendarEntry>> _loadEntries(
  Ref ref, {
  required String from,
  required String to,
}) async {
  final String locale = ref.watch(localeCodeProvider);
  final List<PublicCalendar> catalog =
      ref.watch(publicCalendarsCatalogProvider).value?.value ??
      const <PublicCalendar>[];
  final PublicCalendarSelectionState selection = ref.watch(
    publicCalendarSelectionProvider,
  );
  final List<String> slugs = PublicCalendarSelectionRules.effectiveSelection(
    available: catalog,
    selected: selection.selectedSlugs,
  );
  if (slugs.isEmpty) return const <CalendarEntry>[];

  final Loaded<List<PublicCalendarEvent>> loaded = await ref
      .watch(publicCalendarsRepositoryProvider)
      .fetchEvents(locale: locale, slugs: slugs, from: from, to: to);
  final Map<String, PublicCalendar> bySlug = <String, PublicCalendar>{
    for (final PublicCalendar c in catalog) c.slug: c,
  };
  return publicCalendarEventsToCalendarEntries(loaded.value, bySlug);
}

extension _Slice on String {
  /// The `YYYY-MM-DD` prefix of an ISO-8601 string.
  String slice10() => length >= 10 ? substring(0, 10) : this;
}
