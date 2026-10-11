/**
 * Representative data volumes for the performance baseline.
 *
 * These numbers are the measurement contract: a baseline is only comparable to
 * a later measurement if both ran against the same profile. Every value is
 * derived from something observable in the repository — a configuration
 * ceiling, a sync cadence or a documented catalogue size — and the derivation
 * is written down next to it, so a reader can challenge the number instead of
 * trusting it.
 *
 * `realistic` is what the service is expected to hold in normal operation and
 * is the profile every published baseline uses.
 *
 * `stress` is the upper bound the configured guardrails still permit. It exists
 * to show how a hot path degrades as data grows, not to set a budget.
 */

export type ProfileName = 'realistic' | 'stress';

export interface DatasetProfile {
  readonly name: ProfileName;

  /** Active canteens. Fixed by canteens.config.ts, not a free parameter. */
  readonly canteens: number;
  /** Days of canteen menu history retained in the operational database. */
  readonly canteenDays: number;
  /** Dishes per canteen per day. */
  readonly mealsPerCanteenDay: number;
  /**
   * Rows in `sync_runs`. Append-only: the canteen worker adds one row per
   * canteen per run, and CANTEEN_SYNC_CRON is "0 *[/]2 * * *" — 12 runs a day.
   * This is the table whose growth the /v1/canteens LATERAL query has to stay
   * independent of, so it is sized in service-years rather than rows.
   */
  readonly canteenSyncRunDays: number;

  /** Catalogue size. The code comment in timetable.service.ts states ~270. */
  readonly timetableGroups: number;
  /** Days of lessons retained. */
  readonly timetableDays: number;
  /** Distinct lessons per day across the whole catalogue. */
  readonly timetableEntriesPerDay: number;
  /** Average groups attending one lesson — drives timetable_entry_groups. */
  readonly groupsPerEntry: number;

  /** Servable public calendars. PUBLIC_CALENDAR_API_MAX_CALENDARS caps at 50. */
  readonly publicCalendars: number;
  /**
   * Days of occurrences stored. PUBLIC_CALENDAR_LOOKBACK_DAYS (30) plus
   * PUBLIC_CALENDAR_LOOKAHEAD_DAYS (180).
   */
  readonly publicCalendarDays: number;
  /** Occurrences per calendar per day. */
  readonly eventsPerCalendarDay: number;
}

export const PROFILES: Record<ProfileName, DatasetProfile> = {
  realistic: {
    name: 'realistic',
    // canteens.config.ts ships exactly two active canteens.
    canteens: 2,
    // A full academic year of menu history.
    canteenDays: 365,
    // Observed meine-mensa plans list roughly a dozen dishes per location.
    mealsPerCanteenDay: 12,
    // One year of a two-hourly worker: 2 canteens x 12 runs x 365 days.
    canteenSyncRunDays: 365,

    timetableGroups: 270,
    // One semester plus the surrounding exam weeks.
    timetableDays: 150,
    timetableEntriesPerDay: 90,
    groupsPerEntry: 1.6,

    publicCalendars: 12,
    publicCalendarDays: 210,
    eventsPerCalendarDay: 2,
  },
  stress: {
    name: 'stress',
    canteens: 2,
    canteenDays: 365,
    mealsPerCanteenDay: 12,
    // Three years of sync history: the growth case the LATERAL join defends.
    canteenSyncRunDays: 1095,

    // A catalogue explosion just under the take: 500 cap in listGroups.
    timetableGroups: 480,
    timetableDays: 365,
    timetableEntriesPerDay: 200,
    groupsPerEntry: 2.4,

    // The configured API ceiling.
    publicCalendars: 50,
    publicCalendarDays: 210,
    // Pushes a 120-day request past PUBLIC_CALENDAR_API_MAX_EVENTS (2000), so
    // the truncation path is measured rather than assumed.
    eventsPerCalendarDay: 4,
  },
};

/** Row counts a profile produces, for the reproducibility record. */
/**
 * The profile requested on the command line: the value after `--profile`, or
 * `realistic` when the flag is absent or has no value. Unknown names are
 * returned as given so the caller can reject them with a clear message.
 */
export function profileNameFromArgs(args: readonly string[]): string {
  const index = args.indexOf('--profile');
  if (index < 0) return 'realistic';
  return args[index + 1] ?? 'realistic';
}

export function expectedRowCounts(p: DatasetProfile): Record<string, number> {
  const meals = p.canteens * p.canteenDays * p.mealsPerCanteenDay;
  const entries = p.timetableDays * p.timetableEntriesPerDay;
  return {
    canteens: p.canteens,
    meals,
    meal_prices: meals * 3,
    sync_runs: p.canteens * 12 * p.canteenSyncRunDays,
    timetable_groups: p.timetableGroups,
    timetable_entries: entries,
    timetable_entry_groups: Math.max(entries, Math.round(entries * p.groupsPerEntry)),
    public_calendars: p.publicCalendars,
    public_calendar_events: p.publicCalendars * p.publicCalendarDays * p.eventsPerCalendarDay,
  };
}
