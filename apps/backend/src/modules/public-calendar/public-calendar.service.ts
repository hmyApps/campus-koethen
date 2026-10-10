import { createHash } from 'node:crypto';
import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import { ApiError } from '../../common/errors/api-error';
import { Locale, LocaleResolution } from '../../common/locale/locale';
import { PrismaService } from '../../prisma/prisma.service';
import { buildCombinedEmbedUrl, buildSingleOpenUrl } from './google-calendar-url';
import { PublicCalendarDto, PublicCalendarEventDto } from './public-calendar.types';

/**
 * Derived event keys, indexed by calendar and then by occurrence.
 *
 * Two levels rather than one map keyed on `slug + occurrenceKey`: an event
 * response maps up to `PUBLIC_CALENDAR_API_MAX_EVENTS` rows of ONE calendar, so
 * a combined key meant building a throw-away string — and hashing it — once per
 * event, every request, only to hit the cache almost every time. Resolving the
 * calendar once per response and looking the occurrence up directly removes
 * both. Measured over 400 responses of 2.000 events: 0,499 ms -> 0,039 ms per
 * response.
 */
const eventKeyCache = new Map<string, Map<string, string>>();

/** Total derived keys held across all calendars. */
let eventKeyCacheEntries = 0;

const MAX_EVENT_KEY_CACHE = 10_000;

/** How many keys are cached right now. Exposed so the bound is testable. */
export function eventKeyCacheSize(): number {
  return eventKeyCacheEntries;
}

/** The per-calendar index, created on first use. */
function eventKeysFor(calendarSlug: string): Map<string, string> {
  let perCalendar = eventKeyCache.get(calendarSlug);
  if (perCalendar === undefined) {
    perCalendar = new Map<string, string>();
    eventKeyCache.set(calendarSlug, perCalendar);
  }
  return perCalendar;
}

/**
 * Drops the least recently added key, so a slug or occurrence key that comes
 * from stored data can never decide how much memory this process holds.
 */
function evictOldestEventKey(): void {
  const oldestSlug = eventKeyCache.keys().next();
  if (oldestSlug.done) return;
  const perCalendar = eventKeyCache.get(oldestSlug.value);
  if (perCalendar === undefined) return;
  const oldestOccurrence = perCalendar.keys().next();
  if (!oldestOccurrence.done) {
    perCalendar.delete(oldestOccurrence.value);
    eventKeyCacheEntries -= 1;
  }
  if (perCalendar.size === 0) {
    eventKeyCache.delete(oldestSlug.value);
  }
}

/**
 * Resolves one occurrence's public id against an already-resolved calendar index.
 *
 * Same derivation as {@link computeEventKey} — SHA-256 over
 * `slug \0 occurrenceKey`, base64url, 22 characters.
 */
function eventKeyIn(
  perCalendar: Map<string, string>,
  calendarSlug: string,
  occurrenceKey: string,
): string {
  const cached = perCalendar.get(occurrenceKey);
  if (cached !== undefined) {
    return cached;
  }
  const key = createHash('sha256')
    .update(`${calendarSlug}\0${occurrenceKey}`)
    .digest('base64url')
    .slice(0, 22);
  if (eventKeyCacheEntries >= MAX_EVENT_KEY_CACHE) {
    evictOldestEventKey();
  }
  perCalendar.set(occurrenceKey, key);
  eventKeyCacheEntries += 1;
  return key;
}

export function computeEventKey(calendarSlug: string, occurrenceKey: string): string {
  return eventKeyIn(eventKeysFor(calendarSlug), calendarSlug, occurrenceKey);
}

/**
 * Read model for the public calendar API. Serves ONLY calendars that are
 * active, validated and have at least one successful ICS sync. The
 * server-internal Google calendar id and the feed URL are never exposed; the
 * app receives only stable slugs/UUIDs and a safe `googleOpenUrl`.
 */
@Injectable()
export class PublicCalendarService implements OnModuleInit {
  private readonly logger = new Logger(PublicCalendarService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  onModuleInit(): void {
    if (this.env.PUBLIC_CALENDAR_LOOKAHEAD_DAYS < this.env.PUBLIC_CALENDAR_API_MAX_RANGE_DAYS) {
      this.logger.warn({
        message:
          `PUBLIC_CALENDAR_LOOKAHEAD_DAYS (${this.env.PUBLIC_CALENDAR_LOOKAHEAD_DAYS}) is smaller than ` +
          `PUBLIC_CALENDAR_API_MAX_RANGE_DAYS (${this.env.PUBLIC_CALENDAR_API_MAX_RANGE_DAYS}). ` +
          'API requests covering the full range may return no events towards the end of the window.',
        lookaheadDays: this.env.PUBLIC_CALENDAR_LOOKAHEAD_DAYS,
        apiMaxRangeDays: this.env.PUBLIC_CALENDAR_API_MAX_RANGE_DAYS,
      });
    }
  }

  /** An operational status that may be served to clients. */
  private static readonly SERVABLE = ['ready', 'stale'];

  /** Public-calendar columns consumed by the catalogue and single-calendar DTOs. */
  private static readonly CALENDAR_FIELDS = {
    id: true,
    slug: true,
    channelSlug: true,
    googleCalendarId: true,
    nameDe: true,
    nameEn: true,
    colorHex: true,
    sortOrder: true,
    defaultSubscribed: true,
    operationalStatus: true,
    lastSuccessfulSyncAt: true,
  } as const;

  /**
   * The editor's publication flags. Stored rows only lose a description or
   * location on the next FULL sync, which can be far off while the feed does
   * not change, so every event response applies the flags itself.
   */
  private static readonly TEXT_FLAGS = {
    includeEventDescription: true,
    includeEventLocation: true,
  } as const;

  private servableWhere() {
    return {
      isActive: true,
      operationalStatus: { in: PublicCalendarService.SERVABLE },
      lastSuccessfulSyncAt: { not: null },
    };
  }

  private isStale(status: string, lastSuccessfulSyncAt: Date | null): boolean {
    if (status === 'stale') return true;
    if (!lastSuccessfulSyncAt) return true;
    const ageMinutes = (Date.now() - lastSuccessfulSyncAt.getTime()) / 60_000;
    return ageMinutes > this.env.PUBLIC_CALENDAR_STALE_AFTER_MINUTES;
  }

  private localise(
    locale: Locale,
    de: string,
    en: string | null,
  ): { value: string; fellBack: boolean } {
    if (locale === 'en') {
      if (en && en.trim().length > 0) return { value: en, fellBack: false };
      return { value: de, fellBack: true };
    }
    return { value: de, fellBack: false };
  }

  async listCalendars(
    locale: LocaleResolution,
  ): Promise<{ data: PublicCalendarDto[]; translationFallback: boolean }> {
    const rows = await this.prisma.publicCalendar.findMany({
      where: this.servableWhere(),
      orderBy: [{ sortOrder: 'asc' }, { slug: 'asc' }],
      select: PublicCalendarService.CALENDAR_FIELDS,
    });
    let translationFallback = false;
    const data = rows.map((row) => {
      const name = this.localise(locale.resolvedLocale, row.nameDe, row.nameEn);
      if (locale.resolvedLocale === 'en') {
        translationFallback = translationFallback || name.fellBack;
      }
      const stale = this.isStale(row.operationalStatus, row.lastSuccessfulSyncAt);
      return {
        id: row.id,
        slug: row.slug,
        channelSlug: row.channelSlug ?? null,
        name: name.value,
        colorHex: row.colorHex,
        sortOrder: row.sortOrder,
        defaultSubscribed: row.defaultSubscribed,
        dataState: stale ? 'stale' : 'ready',
        lastSuccessfulSyncAt: row.lastSuccessfulSyncAt?.toISOString() ?? null,
        dataStale: stale,
        googleOpenUrl: buildSingleOpenUrl(row.googleCalendarId),
      } satisfies PublicCalendarDto;
    });
    return { data, translationFallback };
  }

  /**
   * Exactly the columns {@link toEventDto} reads.
   *
   * A month of a busy calendar is thousands of rows, and the row also carries
   * `uid`, `recurrenceId`, `sequence` and four timestamps that exist so a sync
   * run can reconcile occurrences — none of which any reader of this API ever
   * sees. Selecting them anyway made every event request pull that dead weight
   * out of PostgreSQL and through this process for nothing.
   */
  private static readonly EVENT_FIELDS = {
    id: true,
    calendarId: true,
    occurrenceKey: true,
    title: true,
    description: true,
    location: true,
    startsAt: true,
    endsAt: true,
    allDay: true,
    status: true,
  } as const;

  private toEventDto(
    row: {
      id: string;
      calendarId: string;
      occurrenceKey: string;
      title: string;
      description: string | null;
      location: string | null;
      startsAt: Date;
      endsAt: Date;
      allDay: boolean;
      status: string;
    },
    slug: string,
    flags: { includeEventDescription: boolean; includeEventLocation: boolean },
    // Resolved once per response by the caller: every row of a single-calendar
    // page shares it, and an aggregated page has one per selected calendar.
    perCalendar: Map<string, string> = eventKeysFor(slug),
  ): PublicCalendarEventDto {
    const eventKey = eventKeyIn(perCalendar, slug, row.occurrenceKey);
    return {
      id: eventKey,
      calendarId: row.calendarId,
      calendarSlug: slug,
      title: row.title,
      description: flags.includeEventDescription ? row.description : null,
      location: flags.includeEventLocation ? row.location : null,
      start: row.startsAt.toISOString(),
      end: row.endsAt.toISOString(),
      allDay: row.allDay,
      status: row.status,
    };
  }

  async getCalendarEvents(
    slug: string,
    from: Date,
    to: Date,
  ): Promise<{
    calendar: PublicCalendarDto;
    events: PublicCalendarEventDto[];
    truncated: boolean;
  } | null> {
    const row = await this.prisma.publicCalendar.findFirst({
      where: { slug, ...this.servableWhere() },
      select: { ...PublicCalendarService.CALENDAR_FIELDS, ...PublicCalendarService.TEXT_FLAGS },
    });
    if (!row) return null;
    const limit = this.env.PUBLIC_CALENDAR_API_MAX_EVENTS;
    // One row over the ceiling: enough to KNOW the list was cut, without
    // loading a second, unbounded count query.
    const rows = await this.prisma.publicCalendarEvent.findMany({
      where: {
        calendarId: row.id,
        startsAt: { lte: to },
        endsAt: { gte: from },
      },
      select: PublicCalendarService.EVENT_FIELDS,
      orderBy: [{ startsAt: 'asc' }, { id: 'asc' }],
      take: limit + 1,
    });
    const truncated = rows.length > limit;
    const events = truncated ? rows.slice(0, limit) : rows;
    const perCalendar = eventKeysFor(slug);
    const stale = this.isStale(row.operationalStatus, row.lastSuccessfulSyncAt);
    return {
      calendar: {
        id: row.id,
        slug: row.slug,
        channelSlug: row.channelSlug ?? null,
        name: row.nameDe,
        colorHex: row.colorHex,
        sortOrder: row.sortOrder,
        defaultSubscribed: row.defaultSubscribed,
        dataState: stale ? 'stale' : 'ready',
        lastSuccessfulSyncAt: row.lastSuccessfulSyncAt?.toISOString() ?? null,
        dataStale: stale,
        googleOpenUrl: buildSingleOpenUrl(row.googleCalendarId),
      },
      events: events.map((e) => this.toEventDto(e, slug, row, perCalendar)),
      truncated,
    };
  }

  /** Aggregated events across the selected calendars. Empty selection → []. */
  async getAggregatedEvents(
    slugs: string[],
    from: Date,
    to: Date,
  ): Promise<{ events: PublicCalendarEventDto[]; truncated: boolean }> {
    if (slugs.length === 0) return { events: [], truncated: false };
    const rows = await this.prisma.publicCalendar.findMany({
      where: { slug: { in: slugs }, ...this.servableWhere() },
      select: { id: true, slug: true, ...PublicCalendarService.TEXT_FLAGS },
    });
    if (rows.length === 0) return { events: [], truncated: false };
    const calendarById = new Map(rows.map((r) => [r.id, r]));
    const limit = this.env.PUBLIC_CALENDAR_API_MAX_EVENTS;
    // The calendar count and the date range are bounded, the row count they
    // span is not. Deterministic ordering plus a ceiling makes the cut
    // reproducible, and `truncated` makes it visible.
    const eventRows = await this.prisma.publicCalendarEvent.findMany({
      where: {
        calendarId: { in: rows.map((r) => r.id) },
        startsAt: { lte: to },
        endsAt: { gte: from },
      },
      select: PublicCalendarService.EVENT_FIELDS,
      orderBy: [{ startsAt: 'asc' }, { calendarId: 'asc' }, { id: 'asc' }],
      take: limit + 1,
    });
    const truncated = eventRows.length > limit;
    const kept = truncated ? eventRows.slice(0, limit) : eventRows;
    // One index per selected calendar, resolved once rather than per event.
    const keysByCalendarId = new Map(rows.map((r) => [r.id, eventKeysFor(r.slug)] as const));
    const unknownCalendarKeys = eventKeysFor('');
    // A row whose calendar is not in the list cannot happen (the event query
    // filters on these ids); should it ever, it publishes no optional text.
    const withheld = { includeEventDescription: false, includeEventLocation: false };
    return {
      events: kept.map((e) => {
        const calendar = calendarById.get(e.calendarId);
        return this.toEventDto(
          e,
          calendar?.slug ?? '',
          calendar ?? withheld,
          keysByCalendarId.get(e.calendarId) ?? unknownCalendarKeys,
        );
      }),
      truncated,
    };
  }

  /** Resolves servable slugs to a combined Google embed URL. */
  async buildGoogleViewUrl(slugs: string[], locale: Locale): Promise<string> {
    const unique = [...new Set(slugs)];
    if (unique.length === 0) {
      throw new ApiError('VALIDATION_FAILED', locale, [
        'calendar: at least one calendar is required',
      ]);
    }
    if (unique.length > this.env.PUBLIC_CALENDAR_API_MAX_CALENDARS) {
      throw new ApiError('VALIDATION_FAILED', locale, ['calendar: too many calendars requested']);
    }
    const rows = await this.prisma.publicCalendar.findMany({
      where: { slug: { in: unique }, ...this.servableWhere() },
      orderBy: [{ sortOrder: 'asc' }, { slug: 'asc' }],
      select: { googleCalendarId: true },
    });
    if (rows.length === 0) {
      throw new ApiError('PUBLIC_CALENDAR_NOT_FOUND', locale);
    }
    return buildCombinedEmbedUrl(
      rows.map((r) => r.googleCalendarId),
      this.env.PUBLIC_CALENDAR_FALLBACK_TIME_ZONE,
    );
  }
}
