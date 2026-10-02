// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// All `shared_preferences` keys used by the app.
///
/// Keys are versioned. Bumping a version is how a breaking storage change is
/// rolled out without corrupting an existing installation.
abstract final class PreferenceKeys {
  /// `system` | `de` | `en`
  static const String localeMode = 'settings.localeMode.v1';

  /// `system` | `light` | `dark`.
  static const String brightnessPreference = 'settings.brightness.v2';

  /// Old brightness key read only as a migration source.
  static const String legacyThemeMode = 'settings.themeMode.v1';

  /// `pink` | `green` | `blue` | `violet` | `amber`.
  static const String accentScheme = 'settings.accent.v1';

  /// Canteen slug, or absent when the user has not chosen one yet.
  static const String preferredCanteen = 'settings.preferredCanteen.v1';

  /// **Campus** UUID of the chosen timetable group, or absent when the user has
  /// not chosen one yet. An upstream identifier is never stored.
  static const String preferredTimetableGroup =
      'settings.preferredTimetableGroup.v1';

  /// Exact WebUntis lesson information strings switched off for one Campus
  /// group. A disabled set makes every newly appearing value visible by default.
  static String timetableLessonInfoDisabled(String groupId) =>
      'timetable.lessonInfo.disabled.v1.$groupId';

  /// `1` when lessons without a lesson information text are hidden.
  static String timetableLessonInfoWithoutHidden(String groupId) =>
      'timetable.lessonInfo.withoutHidden.v1.$groupId';

  /// Exact course titles (`TimetableEntry.displayTitle`) hidden for one Campus
  /// group — distinct from [timetableLessonInfoDisabled], which filters by the
  /// lesson-info remark, not by the course itself. A newly appearing course is
  /// always visible by default.
  static String timetableHiddenCourses(String groupId) =>
      'timetable.courses.hidden.v1.$groupId';

  /// Schema version of the news channel subscription store.
  static const String channelStoreVersion = 'news.channels.version';

  /// Every channel slug the app has ever seen. Guards `defaultSubscribed` so
  /// it is evaluated exactly once per slug.
  static const String channelSeenSlugs = 'news.channels.seen.v1';

  /// The slugs the user is currently subscribed to.
  static const String channelSelectedSlugs = 'news.channels.selected.v1';

  /// `1` when the mail sync should also download attachment bytes for offline
  /// use, absent/`0` otherwise. Stored as an int flag.
  static const String mailDownloadAttachments = 'mail.downloadAttachments.v1';

  /// Current schema version of the channel subscription store.
  static const int channelStoreCurrentVersion = 1;

  /// The single tag slug the news feed currently filters by, or absent for
  /// "Alle" (no tag filter). A scalar, not a set: unlike channel
  /// subscriptions this is a content filter the reader dips in and out of,
  /// not a standing preference, so there is no seen-slugs ledger.
  static const String newsTagFilterSelected = 'news.tags.filter.selected.v1';

  // --- Public calendars (Y-of-X selection, non-sensitive) ------------------

  /// Schema version of the public-calendar selection store.
  static const String publicCalendarStoreVersion = 'calendars.public.version';

  /// Every public-calendar slug the app has ever seen. Guards
  /// `defaultSubscribed` so it is evaluated exactly once per slug.
  static const String publicCalendarSeenSlugs = 'calendars.public.seen.v1';

  /// The public-calendar slugs the user has currently activated.
  static const String publicCalendarSelectedSlugs =
      'calendars.public.selected.v1';

  /// Current schema version of the public-calendar selection store.
  static const int publicCalendarStoreCurrentVersion = 1;

  // --- Personalisation (mobile-first redesign) -----------------------------

  /// `1` when the user asked for reduced motion locally. The operating
  /// system's own setting is honoured independently of this flag.
  static const String reducedMotion = 'settings.reducedMotion.v1';

  /// The four user-chosen modules of the bottom navigation bar, as module
  /// storage values in bar order.
  ///
  /// `v2`: the bar used to be a fixed first tab, three configurable middles and
  /// More. It is now four free slots and More, over a different catalogue, so a
  /// `v1` list would repair into something the user never chose. A new key lets
  /// the old value be ignored rather than misread.
  static const String navigationTabs = 'settings.navigation.tabs.v2';

  /// buildingKey of the building the campus map opens on.
  static const String defaultBuilding = 'settings.defaultBuilding.v1';

  /// `1` once the first-run onboarding has been completed or skipped.
  static const String onboardingCompleted = 'settings.onboarding.completed.v1';

  /// Semantic properties a dish must have, as `MealTrait` keys.
  ///
  /// A new key rather than the old `canteen.filter.required.v1`: that one held
  /// the source's own marker codes. Those are a different vocabulary, and
  /// adopting them unchecked would turn "avoid code 52" into "avoid something
  /// else entirely" the day the source renumbers.
  static const String canteenTraits = 'canteen.filter.traits.v1';

  /// Allergens to avoid, as `MealAllergen` keys. New key for the same reason.
  static const String canteenAllergens = 'canteen.filter.allergens.v1';

  /// The one price group the cards show. Version 2: the value is no longer
  /// optional, and an absent key now means "student" rather than "the API's
  /// own emphasis".
  static const String canteenPriceGroup = 'canteen.filter.priceGroup.v2';

  /// Names of starred dishes. Names, not upstream ids — those change weekly.
  static const String canteenFavourites = 'canteen.favourites.v1';

  /// Calendar sources the user switched OFF, as source storage values.
  ///
  /// Stored as the disabled set rather than the enabled one on purpose: a
  /// source added in a later version is then on by default instead of
  /// invisible until the user finds the filter.
  static const String calendarDisabledSources = 'calendar.sources.off.v1';

  /// `1` while the week view also draws Saturday and Sunday.
  ///
  /// Default off: a teaching week is Monday to Friday, and two empty columns
  /// cost a fifth of the width of a phone.
  static const String calendarShowWeekend = 'calendar.weekend.v1';

  // --- Event overview source filter (Y-of-X selection) ---------------------
  //
  // A dedicated store for the event overview's per-source multi-select. It
  // deliberately never reads or writes the news feed's channel subscription
  // or the public-calendar selection — the event overview is a distinct view
  // with its own filter state, even though its source options are drawn from
  // the same channel/calendar catalogues.

  /// Schema version of the event source filter store.
  static const String eventSourceStoreVersion = 'events.sources.version';

  /// Every event source key (`filterSourceKey`) ever seen. Guards "select all
  /// on first appearance" so it is evaluated exactly once per key.
  static const String eventSourceSeenKeys = 'events.sources.seen.v1';

  /// The source keys currently selected in the event overview.
  static const String eventSourceSelectedKeys = 'events.sources.selected.v1';

  /// Current schema version of the event source filter store.
  static const int eventSourceStoreCurrentVersion = 1;

  /// `1` while the "Meine gemerkten Events" calendar switch is on. Off by
  /// default — it is an optional, opt-in source, not one of the three
  /// classic calendar sources every install starts with.
  static const String calendarSavedEventsEnabled =
      'calendar.savedEvents.enabled.v1';

  /// `1` while the preferred canteen's favourited dishes appear on the
  /// calendar. Off by default, same reasoning as [calendarSavedEventsEnabled].
  static const String calendarShowFavouriteMeals =
      'calendar.favouriteMeals.enabled.v1';

  // --- Local notifications (device-only, no registration) -----------------
  //
  // Four small scalars and nothing else. There is no token, no installation
  // id and no server-side record anywhere in this feature — ADR-0001 § 10.

  /// `1` once the reader has opted in to local notifications. Absent means
  /// "not yet asked", which is why no system prompt appears on a cold start.
  static const String notificationsOptedIn = 'notifications.optedIn.v1';

  /// Local wall-clock minute of the daily overview; absent means 08:00.
  static const String notificationsDailySummaryMinutes =
      'notifications.dailySummary.minutes.v1';

  /// The notification categories the reader switched OFF, as category storage
  /// values.
  ///
  /// The off-set, like [calendarDisabledSources] and for the same reason:
  /// after the opt-in every category is on (LEVIORA-159 P2), and a category
  /// introduced later has to be on as well rather than invisible.
  static const String notificationCategoriesDisabled =
      'notifications.categories.off.v1';

  /// `1` once the reader has answered "not now" to the in-app pre-permission
  /// sheet. Keeps a contextual trigger point from asking again; the switch in
  /// the settings always asks.
  static const String notificationsPrePromptDeclined =
      'notifications.prePrompt.declined.v1';

  /// `1` once this installation has actually asked the operating system for
  /// notification permission. iOS and Android can both report "disabled"
  /// before their first prompt; this marker distinguishes that fresh state
  /// from a real refusal without storing an identifier or permission result.
  static const String notificationsSystemPromptRequested =
      'notifications.systemPrompt.requested.v1';
}
