// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/api_meta.dart';
import '../../../core/network/loaded.dart';
import '../../../core/time/clock.dart';
import '../../calendar/application/public_calendar_providers.dart';
import '../../calendar/data/public_calendars_repository.dart';
import '../../calendar/domain/public_calendar.dart';
import '../../news/application/news_providers.dart';
import '../../news/data/news_models.dart';
import '../data/event_posts_repository.dart';
import '../domain/event_dedup.dart';
import '../domain/event_past_window.dart';
import '../domain/event_sort.dart';
import '../domain/event_source_label.dart';
import '../domain/event_visibility.dart';
import '../domain/saved_event_snapshot.dart';
import '../domain/unified_event.dart';
import 'event_sort_order.dart';
import 'event_source_filter.dart';
import 'event_visibility_scheduler.dart';
import 'saved_events_controller.dart';

/// The clock the event overview's visibility rules read. Overridden in tests
/// for deterministic time-boundary assertions — same convention as
/// `moodleClockProvider`/`gradeClockProvider`.
final Provider<Clock> eventsClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// All event posts across every channel, for the current locale. The client
/// sends no default window — see `EventPostsRepository`.
final FutureProvider<EventPostsResult> eventPostsOverviewProvider =
    FutureProvider<EventPostsResult>((Ref ref) async {
      final String locale = ref.watch(localeCodeProvider);
      final EventPostsResult result = await ref
          .watch(eventPostsRepositoryProvider)
          .fetchAllEventPosts(locale: locale);
      // Only a genuine, COMPLETE live success may touch the saved list's
      // orphan flag — see the repository-level rule this delegates to. A
      // cache fallback is no evidence, and neither is a truncated load: when a
      // later page failed or the 10×50 ceiling was reached, a saved post that
      // is missing may simply sit on a page that never arrived (VG-N01).
      if (!result.fromCache && !result.isTruncated) {
        await _reconcileSavedPostEvents(ref, result);
      }
      return result;
    }, retry: (_, _) => null);

/// Reconciles the saved list's orphan flag for event posts after a
/// successful `/v1/posts/events` load, using the server-resolved window
/// (`meta.from`/`meta.to`) — never the request bounds, which are usually
/// absent. Silently skipped when the response carries no resolved window
/// (defensive; should not occur on a real success).
Future<void> _reconcileSavedPostEvents(Ref ref, EventPostsResult result) async {
  final DateTime? windowFrom = _parseWindowStart(result.from);
  final DateTime? windowTo = _parseWindowEndExclusive(result.to);
  if (windowFrom == null || windowTo == null) return;
  final List<String> loadedRefs = result.articles
      .where((NewsArticle a) => a.isEventPost)
      .map((NewsArticle a) => 'post:${a.slug}')
      .toList(growable: false);
  await ref
      .read(savedEventsControllerProvider.notifier)
      .reconcileAfterSuccessfulLoad(
        loadedEventRefs: loadedRefs,
        windowFrom: windowFrom,
        windowTo: windowTo,
        belongsToThisSource: (SavedEventSnapshot s) =>
            s.kind == UnifiedEventKind.postEvent,
      );
}

/// `meta.from`/`meta.to` are `YYYY-MM-DD` dates in the API's UTC business
/// day. `from` is read as the inclusive lower bound at UTC midnight.
DateTime? _parseWindowStart(String? isoDate) =>
    isoDate == null ? null : DateTime.tryParse('${isoDate}T00:00:00.000Z');

/// `to` names the last INCLUDED day, so the exclusive upper bound the
/// window-membership check needs is the midnight that starts the day after.
DateTime? _parseWindowEndExclusive(String? isoDate) {
  final DateTime? start = _parseWindowStart(isoDate);
  return start?.add(const Duration(days: 1));
}

/// All public-calendar events across every calendar in the catalogue (not
/// only the reader's own calendar-screen selection — the event overview
/// aggregates every source, and the event-source filter is what narrows it
/// down from there), for the server's own default window.
final FutureProvider<Loaded<List<PublicCalendarEvent>>>
eventCalendarsOverviewProvider =
    FutureProvider<Loaded<List<PublicCalendarEvent>>>((Ref ref) async {
      final String locale = ref.watch(localeCodeProvider);
      final List<PublicCalendar> catalog = (await ref.watch(
        publicCalendarsCatalogProvider.future,
      )).value;
      final List<String> slugs = catalog
          .map((PublicCalendar c) => c.slug)
          .toList(growable: false);
      if (slugs.isEmpty) {
        return const Loaded<List<PublicCalendarEvent>>(
          value: <PublicCalendarEvent>[],
          meta: ApiMeta.empty,
        );
      }
      final Loaded<List<PublicCalendarEvent>> loaded = await ref
          .watch(publicCalendarsRepositoryProvider)
          .fetchEventsDefaultWindow(locale: locale, slugs: slugs);
      // Same rule as for the posts: a list the server cut at its event
      // ceiling (`meta.truncated`) is incomplete and proves no removal.
      if (!loaded.fromCache && !loaded.meta.truncated) {
        await _reconcileSavedCalendarEvents(ref, loaded);
      }
      return loaded;
    }, retry: (_, _) => null);

/// Reconciles the saved list's orphan flag for calendar events after a
/// successful `/v1/calendars/events` load, mirroring
/// [_reconcileSavedPostEvents] for the other source.
Future<void> _reconcileSavedCalendarEvents(
  Ref ref,
  Loaded<List<PublicCalendarEvent>> loaded,
) async {
  final DateTime? windowFrom = _parseWindowStart(loaded.meta.from);
  final DateTime? windowTo = _parseWindowEndExclusive(loaded.meta.to);
  if (windowFrom == null || windowTo == null) return;
  await ref
      .read(savedEventsControllerProvider.notifier)
      .reconcileAfterSuccessfulLoad(
        loadedEventRefs: loaded.value.map(
          (PublicCalendarEvent e) => 'calendar:${e.id}',
        ),
        windowFrom: windowFrom,
        windowTo: windowTo,
        belongsToThisSource: (SavedEventSnapshot s) =>
            s.kind == UnifiedEventKind.calendarEvent,
      );
}

/// Whether the reader asked for "Ältere anzeigen". Deliberately not
/// persisted: loading half a year of past events is a per-visit choice, and
/// the overview opens on what is current.
class EventShowPastController extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;

  void hide() => state = false;

  void toggle() => state = !state;
}

final NotifierProvider<EventShowPastController, bool> eventShowPastProvider =
    NotifierProvider<EventShowPastController, bool>(
      EventShowPastController.new,
    );

/// The explicit past window, fixed for one load: the last
/// [kPastEventsWindowDays] days up to and including today.
PastEventsWindow _pastWindow(Ref ref) =>
    pastEventsWindow(ref.read(eventsClockProvider).now());

/// Event posts of the past window, loaded only once the overview shows past
/// events ("Ältere anzeigen").
///
/// BOTH bounds are always sent: an older deployed backend resolves a missing
/// `to` as `from` plus its maximum range, which would pull upcoming events
/// into the past load. Caching follows [EventPostsRepository]: page 1 is
/// cached under the explicit window and served as an offline fallback; a
/// failed load never deletes a cached entry.
///
/// No saved-list reconciliation happens here, on purpose. The orphan flag
/// means "the source no longer has this event", and the past window cannot
/// prove that: public-calendar occurrences older than the backend's
/// `PUBLIC_CALENDAR_LOOKBACK_DAYS` retention are deleted server-side even
/// though they were never withdrawn, so reconciling a 180-day window would
/// flag genuinely held, saved events as "Nicht mehr verfügbar". Only the
/// current-window loads above reconcile.
final FutureProvider<EventPostsResult> eventPastPostsProvider =
    FutureProvider<EventPostsResult>((Ref ref) async {
      final String locale = ref.watch(localeCodeProvider);
      final PastEventsWindow window = _pastWindow(ref);
      return ref
          .watch(eventPostsRepositoryProvider)
          .fetchAllEventPosts(locale: locale, from: window.from, to: window.to);
    }, retry: (_, _) => null);

/// Public-calendar events of the past window across the whole catalogue —
/// the past counterpart of [eventCalendarsOverviewProvider], with the same
/// explicit-bounds and no-reconciliation rules as [eventPastPostsProvider].
final FutureProvider<Loaded<List<PublicCalendarEvent>>>
eventPastCalendarsProvider = FutureProvider<Loaded<List<PublicCalendarEvent>>>((
  Ref ref,
) async {
  final String locale = ref.watch(localeCodeProvider);
  final List<PublicCalendar> catalog = (await ref.watch(
    publicCalendarsCatalogProvider.future,
  )).value;
  final List<String> slugs = catalog
      .map((PublicCalendar c) => c.slug)
      .toList(growable: false);
  if (slugs.isEmpty) {
    return const Loaded<List<PublicCalendarEvent>>(
      value: <PublicCalendarEvent>[],
      meta: ApiMeta.empty,
    );
  }
  final PastEventsWindow window = _pastWindow(ref);
  return ref
      .watch(publicCalendarsRepositoryProvider)
      .fetchEvents(
        locale: locale,
        slugs: slugs,
        from: window.from,
        to: window.to,
      );
}, retry: (_, _) => null);

/// Every event-source filter option, built from the channel and public
/// calendar catalogues, folding a channel and its mapped calendar into one
/// option — "Filteroptionen bilden zugeordneten Channel plus Kalender genau
/// einmal ab, nicht zugeordnete Kalender einzeln". Also the single place a
/// freshly seen option is folded into the persisted filter selection.
final FutureProvider<List<EventSourceOption>> eventSourceOptionsProvider =
    FutureProvider<List<EventSourceOption>>((Ref ref) async {
      final List<NewsChannel> channels = (await ref.watch(
        newsChannelsProvider.future,
      )).value;
      final List<PublicCalendar> calendars = (await ref.watch(
        publicCalendarsCatalogProvider.future,
      )).value;

      final List<EventSourceOption> options = <EventSourceOption>[];
      final Set<String> seenKeys = <String>{};
      for (final NewsChannel channel in channels) {
        if (seenKeys.add(channel.slug)) {
          options.add(
            EventSourceOption(
              key: channel.slug,
              label: eventSourceDisplayLabel(
                channel.name,
                isChannelSource: true,
              ),
            ),
          );
        }
      }
      for (final PublicCalendar calendar in calendars) {
        if (calendar.channelSlug != null) continue; // folded into its channel
        if (seenKeys.add(calendar.slug)) {
          options.add(
            EventSourceOption(key: calendar.slug, label: calendar.name),
          );
        }
      }

      await ref.read(eventSourceFilterProvider.notifier).reconcile(options);
      return options;
    });

/// The loaded event posts, indexed by slug.
///
/// Both halves of the event screen answer the same question per row — "is the
/// live post for this event loaded, and what are its content blocks" — and
/// both used to build this map from scratch on every build, over a list the
/// contract lets grow to the 10×50 page ceiling. The overview rebuilds on
/// every visibility boundary the scheduler fires, on every filter change and
/// on every change to the saved list; the saved view rebuilds alongside it.
///
/// Derived once per loaded result instead, and shared by the two.
final Provider<Map<String, NewsArticle>> eventArticlesBySlugProvider =
    Provider<Map<String, NewsArticle>>((Ref ref) {
      final List<NewsArticle> articles =
          ref.watch(eventPostsOverviewProvider).value?.articles ??
          const <NewsArticle>[];
      return <String, NewsArticle>{
        for (final NewsArticle article in articles) article.slug: article,
      };
    });

/// Maps loaded event posts/calendar events to [UnifiedEvent]s, merges +
/// dedupes them with the one reusable function, and returns the RAW merged
/// set — before the event-source filter and the visibility rules are
/// applied. Kept separate from [eventOverviewProvider] so the calendar merge
/// (Stage 4) can reuse this exact aggregation without the overview's
/// filter/visibility narrowing.
final Provider<List<UnifiedEvent>> rawUnifiedEventsProvider =
    Provider<List<UnifiedEvent>>(
      (Ref ref) => _mergeLoaded(
        ref,
        posts:
            ref.watch(eventPostsOverviewProvider).value?.articles ??
            const <NewsArticle>[],
        calendarEvents:
            ref.watch(eventCalendarsOverviewProvider).value?.value ??
            const <PublicCalendarEvent>[],
      ),
    );

/// The past-window counterpart of [rawUnifiedEventsProvider]: merged,
/// deduped, unfiltered — and empty unless the reader asked for past events,
/// so the past requests are only ever made on demand.
final Provider<List<UnifiedEvent>> rawPastUnifiedEventsProvider =
    Provider<List<UnifiedEvent>>((Ref ref) {
      if (!ref.watch(eventShowPastProvider)) return const <UnifiedEvent>[];
      return _mergeLoaded(
        ref,
        posts:
            ref.watch(eventPastPostsProvider).value?.articles ??
            const <NewsArticle>[],
        calendarEvents:
            ref.watch(eventPastCalendarsProvider).value?.value ??
            const <PublicCalendarEvent>[],
      );
    });

List<UnifiedEvent> _mergeLoaded(
  Ref ref, {
  required List<NewsArticle> posts,
  required List<PublicCalendarEvent> calendarEvents,
}) {
  final List<PublicCalendar> catalog =
      ref.watch(publicCalendarsCatalogProvider).value?.value ??
      const <PublicCalendar>[];
  final Map<String, PublicCalendar> bySlug = <String, PublicCalendar>{
    for (final PublicCalendar c in catalog) c.slug: c,
  };

  final List<UnifiedEvent> postEvents = posts
      .where((NewsArticle a) => a.isEventPost)
      .map(postToUnifiedEvent)
      .toList();
  final List<UnifiedEvent> mappedCalendarEvents = calendarEvents.map((
    PublicCalendarEvent e,
  ) {
    final PublicCalendar? calendar = bySlug[e.calendarSlug];
    return calendarToUnifiedEvent(
      e,
      channelSlug: calendar?.channelSlug,
      calendarName: calendar?.name,
      colorHex: calendar?.colorHex,
    );
  }).toList();

  return mergeEventSources(
    postEvents: postEvents,
    calendarEvents: mappedCalendarEvents,
  );
}

/// Ticks whenever the event overview's visible set must be re-evaluated —
/// driven by [EventVisibilityScheduler] (single boundary timer, rescheduled
/// after every fire, forced on app resume). See
/// `EventOverviewClockController.handleLifecycleState`.
class EventOverviewClockController extends Notifier<DateTime> {
  EventVisibilityScheduler? _scheduler;

  @override
  DateTime build() {
    final Clock clock = ref.watch(eventsClockProvider);
    final EventVisibilityScheduler scheduler = EventVisibilityScheduler(
      onRecompute: () => state = clock.now(),
      nextBoundary: () => nextVisibilityBoundary(
        ref.read(rawUnifiedEventsProvider),
        now: clock.now(),
      ),
      clock: clock.now,
    );
    _scheduler = scheduler;
    ref.onDispose(scheduler.dispose);
    scheduler.start();
    return clock.now();
  }

  /// Call from the consuming screen's `didChangeAppLifecycleState`.
  void handleLifecycleState(AppLifecycleState state) =>
      _scheduler?.handleLifecycleState(state);

  /// Call after a fresh load changes the underlying event list, so a newly
  /// arrived event's boundary is picked up immediately instead of waiting for
  /// the previously-armed timer.
  void recomputeNow() => _scheduler?.recomputeNow();
}

final NotifierProvider<EventOverviewClockController, DateTime>
eventOverviewClockProvider =
    NotifierProvider<EventOverviewClockController, DateTime>(
      EventOverviewClockController.new,
    );

/// Everything the event overview screen needs: the visible, deduped, sorted
/// event list plus per-source resilience state. A failing source never hides
/// the other; only the total absence of data from both produces an overall
/// error (`hasTotalFailure`).
@immutable
class EventOverviewData {
  const EventOverviewData({
    required this.events,
    required this.sourceOptions,
    this.postsLoading = false,
    this.hasPostsError = false,
    this.postsFromCache = false,
    this.isTruncated = false,
    this.calendarsLoading = false,
    this.hasCalendarError = false,
    this.calendarsFromCache = false,
    this.sortOrder = EventSortOrder.chronological,
    this.showPast = false,
    this.pastEvents = const <UnifiedEvent>[],
    this.pastPostsLoading = false,
    this.hasPastPostsError = false,
    this.pastCalendarsLoading = false,
    this.hasPastCalendarError = false,
    this.isPastTruncated = false,
  });

  /// Visible (running/upcoming), filtered, deduplicated, deterministically
  /// sorted events — ready to render as-is.
  final List<UnifiedEvent> events;
  final List<EventSourceOption> sourceOptions;

  final bool postsLoading;
  final bool hasPostsError;
  final bool postsFromCache;

  /// The 10×50 page ceiling was reached before the server's last page.
  final bool isTruncated;

  final bool calendarsLoading;
  final bool hasCalendarError;
  final bool calendarsFromCache;

  /// The order both [events] and [pastEvents] are sorted in.
  final EventSortOrder sortOrder;

  /// Whether the reader asked for "Ältere anzeigen".
  final bool showPast;

  /// Already-ended, filtered, deduplicated, sorted events: everything of the
  /// past window plus whatever of the current load has ended since (e.g. an
  /// event that ended this morning). Empty unless [showPast].
  final List<UnifiedEvent> pastEvents;

  final bool pastPostsLoading;
  final bool hasPastPostsError;
  final bool pastCalendarsLoading;
  final bool hasPastCalendarError;

  /// The past window hit a source's ceiling (10×50 pages or `meta.truncated`).
  final bool isPastTruncated;

  bool get isLoading => postsLoading || calendarsLoading;

  bool get pastLoading => pastPostsLoading || pastCalendarsLoading;

  /// Only true once BOTH sources have nothing to show.
  bool get hasTotalFailure =>
      events.isEmpty && hasPostsError && hasCalendarError;
}

final Provider<EventOverviewData>
eventOverviewProvider = Provider<EventOverviewData>((Ref ref) {
  final AsyncValue<EventPostsResult> postsAsync = ref.watch(
    eventPostsOverviewProvider,
  );
  final AsyncValue<Loaded<List<PublicCalendarEvent>>> calendarsAsync = ref
      .watch(eventCalendarsOverviewProvider);
  final AsyncValue<List<EventSourceOption>> optionsAsync = ref.watch(
    eventSourceOptionsProvider,
  );
  final List<EventSourceOption> options =
      optionsAsync.value ?? const <EventSourceOption>[];

  final EventSourceFilterState filterState = ref.watch(
    eventSourceFilterProvider,
  );
  final Set<String> selectedKeys = EventSourceFilterRules.effectiveSelection(
    available: options,
    selected: filterState.selectedKeys,
  );

  bool matchesFilter(UnifiedEvent e) =>
      // The catalogue has not resolved yet: show everything rather than an
      // empty list that would look like "no events" while the real filter is
      // still loading.
      options.isEmpty || selectedKeys.contains(e.filterSourceKey);

  final List<UnifiedEvent> merged = ref.watch(rawUnifiedEventsProvider);
  final List<UnifiedEvent> filtered = merged.where(matchesFilter).toList();

  final DateTime now = ref.watch(eventOverviewClockProvider);
  final EventSortOrder sortOrder = ref.watch(eventSortOrderProvider);
  final List<UnifiedEvent> visible = visibleEventsInOverview(
    filtered,
    now: now,
  );
  final List<UnifiedEvent> sorted = sortCurrentEvents(visible, sortOrder);

  final bool showPast = ref.watch(eventShowPastProvider);
  AsyncValue<EventPostsResult>? pastPostsAsync;
  AsyncValue<Loaded<List<PublicCalendarEvent>>>? pastCalendarsAsync;
  List<UnifiedEvent> pastSorted = const <UnifiedEvent>[];
  if (showPast) {
    pastPostsAsync = ref.watch(eventPastPostsProvider);
    pastCalendarsAsync = ref.watch(eventPastCalendarsProvider);
    // The current load wins for an event both windows returned; a past
    // calendar event whose post counterpart only the current load delivered
    // is still the same event under the dedup rule and is dropped.
    final EventDedupIndex currentPosts = EventDedupIndex(
      merged.where((UnifiedEvent e) => e.kind == UnifiedEventKind.postEvent),
    );
    final List<UnifiedEvent> pastOnly = ref
        .watch(rawPastUnifiedEventsProvider)
        .where(
          (UnifiedEvent e) =>
              e.kind != UnifiedEventKind.calendarEvent ||
              !currentPosts.hasCounterpartOf(e),
        )
        .toList();
    final List<UnifiedEvent> candidates = unionEventsByRef(
      primary: merged,
      secondary: pastOnly,
    ).where(matchesFilter).toList();
    pastSorted = sortPastEvents(
      pastEventsInOverview(candidates, now: now),
      sortOrder,
    );
  }

  return EventOverviewData(
    events: sorted,
    sourceOptions: options,
    postsLoading: postsAsync.isLoading,
    hasPostsError: postsAsync.hasError,
    postsFromCache: postsAsync.value?.fromCache ?? false,
    // Either source can be cut short: the posts side by its own 10x50 page
    // ceiling, the calendar side by the server's event ceiling
    // (`meta.truncated`). One banner covers both.
    isTruncated:
        (postsAsync.value?.isTruncated ?? false) ||
        (calendarsAsync.value?.meta.truncated ?? false),
    calendarsLoading: calendarsAsync.isLoading,
    hasCalendarError: calendarsAsync.hasError,
    calendarsFromCache: calendarsAsync.value?.fromCache ?? false,
    sortOrder: sortOrder,
    showPast: showPast,
    pastEvents: pastSorted,
    pastPostsLoading: pastPostsAsync?.isLoading ?? false,
    hasPastPostsError: pastPostsAsync?.hasError ?? false,
    pastCalendarsLoading: pastCalendarsAsync?.isLoading ?? false,
    hasPastCalendarError: pastCalendarsAsync?.hasError ?? false,
    isPastTruncated:
        (pastPostsAsync?.value?.isTruncated ?? false) ||
        (pastCalendarsAsync?.value?.meta.truncated ?? false),
  );
});
