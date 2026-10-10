import { Logger } from '@nestjs/common';
import { validateEnv } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { ConditionalHeaders, IcsClientError, IcsFetchResult } from './google-public-ics.client';
import { PublicCalendarSyncService } from './public-calendar-sync.service';

/**
 * Lifecycle of a calendar across several catalogue and event runs.
 *
 * These scenarios depend on what an EARLIER run left behind (validators,
 * content hash, expansion window, status), so they run against a small
 * in-memory stand-in for the three Prisma models instead of per-call mocks.
 * The stand-in implements exactly the query shapes the sync service uses and
 * throws on anything else, so a new query shape cannot pass by accident. No
 * database is involved; test/public-calendar-sync.integration.spec.ts covers
 * the real one.
 *
 * All fixtures are synthetic: made-up calendars, no real Google ids.
 */

type Row = Record<string, unknown>;

function isFilterObject(value: unknown): value is Row {
  return value !== null && typeof value === 'object' && !(value instanceof Date);
}

function same(a: unknown, b: unknown): boolean {
  if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime();
  return a === b;
}

function time(value: unknown): number {
  if (!(value instanceof Date)) throw new Error('range filter on a non-date value');
  return value.getTime();
}

function matchesFilter(value: unknown, filter: Row): boolean {
  const insensitive = filter['mode'] === 'insensitive';
  const text = (input: unknown): string =>
    insensitive ? String(input).toLowerCase() : String(input);
  return Object.entries(filter).every(([operator, operand]) => {
    switch (operator) {
      case 'mode':
        return true;
      case 'in':
        return (operand as unknown[]).some((item) => same(value, item));
      case 'notIn':
        return !(operand as unknown[]).some((item) => same(value, item));
      case 'gte':
        return time(value) >= time(operand);
      case 'lt':
        return time(value) < time(operand);
      case 'lte':
        return time(value) <= time(operand);
      case 'not':
        return isFilterObject(operand) ? !matchesFilter(value, operand) : !same(value, operand);
      case 'startsWith':
        return typeof value === 'string' && text(value).startsWith(text(operand));
      case 'endsWith':
        return typeof value === 'string' && text(value).endsWith(text(operand));
      default:
        throw new Error(`in-memory store: unsupported filter "${operator}"`);
    }
  });
}

function matches(row: Row, where: Row | undefined): boolean {
  if (!where) return true;
  return Object.entries(where).every(([key, condition]) => {
    if (key === 'NOT') return !matches(row, condition as Row);
    if (!(key in row)) throw new Error(`in-memory store: unknown column "${key}"`);
    return isFilterObject(condition)
      ? matchesFilter(row[key], condition)
      : same(row[key], condition);
  });
}

function pick(row: Row, select: Row | undefined): Row {
  if (!select) return { ...row };
  return Object.fromEntries(Object.keys(select).map((key) => [key, row[key]]));
}

const CALENDAR_DEFAULTS: Row = {
  channelSlug: null,
  nameEn: null,
  sortOrder: 0,
  isActive: true,
  defaultSubscribed: false,
  includeEventDescription: false,
  includeEventLocation: false,
  source: 'strapi',
  operationalStatus: 'pending',
  lastEtag: null,
  lastModified: null,
  lastContentHash: null,
  lastExpandedTo: null,
  lastCatalogSyncAt: null,
  lastSuccessfulSyncAt: null,
};

interface Args {
  where?: Row;
  select?: Row;
  data?: Row;
  create?: Row;
  update?: Row;
}

class InMemoryStore {
  calendars: Row[] = [];
  events: Row[] = [];
  runs: Row[] = [];
  private sequence = 0;

  private nextId(prefix: string): string {
    this.sequence += 1;
    return `${prefix}-${this.sequence}`;
  }

  readonly publicCalendar = {
    findUnique: ({ where }: Args) => {
      const row = this.calendars.find((candidate) => matches(candidate, where));
      return Promise.resolve(row ? { ...row } : null);
    },
    findMany: ({ where, select }: Args) =>
      Promise.resolve(
        this.calendars.filter((row) => matches(row, where)).map((row) => pick(row, select)),
      ),
    upsert: ({ where, create, update }: Args) => {
      const existing = this.calendars.find((row) => matches(row, where));
      if (existing) {
        Object.assign(existing, update);
        return Promise.resolve({ ...existing });
      }
      const row = { ...CALENDAR_DEFAULTS, id: this.nextId('calendar'), ...create };
      this.calendars.push(row);
      return Promise.resolve({ ...row });
    },
    update: ({ where, data }: Args) => {
      const row = this.calendars.find((candidate) => matches(candidate, where));
      if (!row) throw new Error('in-memory store: calendar to update not found');
      Object.assign(row, data);
      return Promise.resolve({ ...row });
    },
    updateMany: ({ where, data }: Args) => {
      const rows = this.calendars.filter((row) => matches(row, where));
      for (const row of rows) Object.assign(row, data);
      return Promise.resolve({ count: rows.length });
    },
  };

  readonly publicCalendarEvent = {
    findMany: ({ where, select }: Args) =>
      Promise.resolve(
        this.events.filter((row) => matches(row, where)).map((row) => pick(row, select)),
      ),
    createMany: ({ data }: { data: Row[] }) => {
      for (const item of data) {
        const duplicate = this.events.some(
          (row) =>
            row['calendarId'] === item['calendarId'] &&
            row['occurrenceKey'] === item['occurrenceKey'],
        );
        if (duplicate) throw new Error('in-memory store: unique (calendarId, occurrenceKey)');
        const now = new Date();
        this.events.push({
          id: this.nextId('event'),
          importedAt: now,
          lastSeenAt: now,
          ...item,
        });
      }
      return Promise.resolve({ count: data.length });
    },
    update: ({ where, data }: Args) => {
      const key = where?.['calendarId_occurrenceKey'] as Row;
      const row = this.events.find(
        (candidate) =>
          candidate['calendarId'] === key['calendarId'] &&
          candidate['occurrenceKey'] === key['occurrenceKey'],
      );
      if (!row) throw new Error('in-memory store: event to update not found');
      Object.assign(row, data);
      return Promise.resolve({ ...row });
    },
    updateMany: ({ where, data }: Args) => {
      const rows = this.events.filter((row) => matches(row, where));
      for (const row of rows) Object.assign(row, data);
      return Promise.resolve({ count: rows.length });
    },
    deleteMany: ({ where }: Args) => {
      const before = this.events.length;
      this.events = this.events.filter((row) => !matches(row, where));
      return Promise.resolve({ count: before - this.events.length });
    },
  };

  readonly publicCalendarSyncRun = {
    create: ({ data }: Args) => {
      const row = { id: this.nextId('run'), ...data };
      this.runs.push(row);
      return Promise.resolve({ ...row });
    },
    update: ({ where, data }: Args) => {
      const row = this.runs.find((candidate) => matches(candidate, where));
      if (row) Object.assign(row, data);
      return Promise.resolve({ ...row });
    },
  };

  $transaction<T>(operation: (tx: InMemoryStore) => Promise<T>): Promise<T> {
    return operation(this);
  }

  calendar(slug: string): Row {
    const row = this.calendars.find((candidate) => candidate['slug'] === slug);
    if (!row) throw new Error(`no calendar ${slug}`);
    return row;
  }

  eventsOf(slug: string): Row[] {
    const id = this.calendar(slug)['id'];
    return this.events.filter((row) => row['calendarId'] === id);
  }
}

const ID_A = 'beispielkalender-a@group.calendar.google.com';
const ID_B = 'beispielkalender-b@group.calendar.google.com';
const SLUG = 'beispielkalender';

function shareUrl(calendarId: string): string {
  const cid = Buffer.from(calendarId, 'utf8').toString('base64url');
  return `https://calendar.google.com/calendar/u/0?cid=${cid}`;
}

function strapiEntry(overrides: Row = {}): Row {
  return {
    slug: SLUG,
    name: 'Beispielkalender',
    googleShareUrl: shareUrl(ID_A),
    colorHex: '#5B3FD0',
    sortOrder: 1,
    isActive: true,
    defaultSubscribed: true,
    includeEventDescription: true,
    includeEventLocation: true,
    ...overrides,
  };
}

function stamp(at: Date): string {
  return at
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}Z$/, 'Z');
}

/** One timed event `dayOffset` days from now, with description and location. */
function singleEventFeed(uid = 'termin-1', summary = 'Beispielsitzung'): string {
  const at = new Date(Date.now() + 2 * 86_400_000);
  return (
    [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Synthetic//Test//EN',
      'BEGIN:VEVENT',
      `UID:${uid}`,
      'DTSTAMP:20260101T000000Z',
      `DTSTART:${stamp(at)}`,
      `DTEND:${stamp(new Date(at.getTime() + 3_600_000))}`,
      `SUMMARY:${summary}`,
      'DESCRIPTION:Beschreibung des Beispieltermins',
      'LOCATION:Beispielraum 1',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n') + '\r\n'
  );
}

/** An open-ended weekly series that started a few weeks ago. */
function weeklySeriesFeed(): string {
  const start = new Date(Date.now() - 21 * 86_400_000);
  start.setUTCHours(9, 0, 0, 0);
  return (
    [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Synthetic//Test//EN',
      'BEGIN:VEVENT',
      'UID:wochenserie',
      'DTSTAMP:20260101T000000Z',
      `DTSTART:${stamp(start)}`,
      `DTEND:${stamp(new Date(start.getTime() + 3_600_000))}`,
      'RRULE:FREQ=WEEKLY',
      'SUMMARY:Wöchentliche Sprechstunde',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n') + '\r\n'
  );
}

class FakeStrapi {
  de: Row[] = [];
  get = (_path: string, query?: Row): Promise<unknown> => {
    const data = query?.['locale'] === 'en' ? [] : this.de;
    return Promise.resolve({
      data,
      meta: { pagination: { page: 1, pageSize: 100, pageCount: 1, total: data.length } },
    });
  };
}

/**
 * Behaves like Google's public feed: answers 304 whenever the request carries
 * the ETag it currently serves, and 404 for a feed it does not (or no longer)
 * serve.
 */
class FakeGoogle {
  feeds = new Map<string, { body: string; etag: string | null }>();
  calls: Array<{ calendarId: string; conditional: ConditionalHeaders }> = [];
  onFetch: (() => void) | null = null;

  fetchCalendar = (
    calendarId: string,
    conditional: ConditionalHeaders = {},
  ): Promise<IcsFetchResult> => {
    this.calls.push({ calendarId, conditional: { ...conditional } });
    this.onFetch?.();
    const feed = this.feeds.get(calendarId);
    if (!feed) {
      return Promise.reject(
        new IcsClientError('feedNotFound', 'The calendar feed does not exist.', 404),
      );
    }
    if (feed.etag !== null && conditional.etag === feed.etag) {
      return Promise.resolve({ kind: 'notModified' });
    }
    return Promise.resolve({
      kind: 'ok',
      body: feed.body,
      etag: feed.etag,
      lastModified: null,
    });
  };

  lastCall(): { calendarId: string; conditional: ConditionalHeaders } {
    const call = this.calls[this.calls.length - 1];
    if (!call) throw new Error('Google was never contacted');
    return call;
  }
}

describe('PublicCalendarSyncService lifecycle', () => {
  const env = validateEnv(process.env);
  let store: InMemoryStore;
  let strapi: FakeStrapi;
  let google: FakeGoogle;
  let sync: PublicCalendarSyncService;

  beforeEach(() => {
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    store = new InMemoryStore();
    strapi = new FakeStrapi();
    google = new FakeGoogle();
    sync = new PublicCalendarSyncService(
      store as unknown as PrismaService,
      strapi as never,
      google as never,
      env,
    );
  });

  afterEach(() => jest.restoreAllMocks());

  /** Runs the event sync as if the clock read `now`. */
  async function syncAt(now: Date, slug = SLUG) {
    const realWindow = PublicCalendarSyncService.prototype.window.bind(sync);
    const spy = jest.spyOn(sync, 'window').mockImplementation(() => realWindow(now));
    try {
      return await sync.syncCalendarEvents(slug);
    } finally {
      spy.mockRestore();
    }
  }

  async function seedReady(
    entry: Row = {},
    feed = singleEventFeed(),
    etag: string | null = '"v1"',
  ) {
    strapi.de = [strapiEntry(entry)];
    await sync.syncCatalog();
    google.feeds.set(ID_A, { body: feed, etag });
    const outcome = await sync.syncCalendarEvents(SLUG);
    expect(outcome.status).toBe('success');
    expect(store.calendar(SLUG)['operationalStatus']).toBe('ready');
  }

  describe('description and location flags (B-01)', () => {
    it('re-parses an unchanged feed after the flags were switched off, despite a 304', async () => {
      await seedReady();
      expect(store.eventsOf(SLUG)[0]).toMatchObject({
        description: 'Beschreibung des Beispieltermins',
        location: 'Beispielraum 1',
      });

      strapi.de = [strapiEntry({ includeEventDescription: false, includeEventLocation: false })];
      await sync.syncCatalog();
      const outcome = await sync.syncCalendarEvents(SLUG);

      expect(outcome.status).toBe('success');
      expect(google.lastCall().conditional.etag ?? null).toBeNull();
      expect(store.eventsOf(SLUG)).toHaveLength(1);
      expect(store.eventsOf(SLUG)[0]).toMatchObject({ description: null, location: null });
    });

    it('re-parses an unchanged feed after a flag was switched on, despite an equal hash', async () => {
      // No ETag: the unchanged content hash is the shortcut here.
      await seedReady(
        { includeEventDescription: false, includeEventLocation: false },
        undefined,
        null,
      );
      expect(store.eventsOf(SLUG)[0]).toMatchObject({ description: null, location: null });

      strapi.de = [strapiEntry({ includeEventDescription: true, includeEventLocation: false })];
      await sync.syncCatalog();
      const outcome = await sync.syncCalendarEvents(SLUG);

      expect(outcome.status).toBe('success');
      expect(store.eventsOf(SLUG)[0]).toMatchObject({
        description: 'Beschreibung des Beispieltermins',
        location: null,
      });
    });

    it('keeps the validators when nothing that shapes the parse changed', async () => {
      await seedReady();
      strapi.de = [strapiEntry({ colorHex: '#123456', sortOrder: 7 })];
      await sync.syncCatalog();

      expect(store.calendar(SLUG)['lastEtag']).toBe('"v1"');
      const outcome = await sync.syncCalendarEvents(SLUG);
      expect(outcome.status).toBe('notModified');
    });

    it('never keeps validators of a run whose flags the catalogue changed mid-download', async () => {
      await seedReady();
      // The feed changed, so this run parses — but while it downloads, the
      // catalogue job switches the description off and resets the validators.
      google.feeds.set(ID_A, { body: singleEventFeed('termin-1', 'Geändert'), etag: '"v2"' });
      google.onFetch = () => {
        Object.assign(store.calendar(SLUG), {
          includeEventDescription: false,
          lastEtag: null,
          lastModified: null,
          lastContentHash: null,
        });
      };

      const raced = await sync.syncCalendarEvents(SLUG);

      expect(raced.status).toBe('failed');
      expect(raced.errorCode).toBe('calendarChanged');
      expect(store.calendar(SLUG)['lastEtag']).toBeNull();
      expect(store.calendar(SLUG)['lastContentHash']).toBeNull();
      // Nothing parsed under the old flags was written.
      expect(store.eventsOf(SLUG)[0]).toMatchObject({ title: 'Beispielsitzung' });

      google.onFetch = null;
      const next = await sync.syncCalendarEvents(SLUG);
      expect(next.status).toBe('success');
      expect(store.eventsOf(SLUG)[0]).toMatchObject({ title: 'Geändert', description: null });
    });
  });

  describe('replacing the Google calendar behind a slug (VB-N03)', () => {
    it('drops every stored occurrence and all sync state of the previous feed', async () => {
      await seedReady();
      const calendarId = store.calendar(SLUG)['id'];
      // An occurrence of the old feed far outside the sync window, which the
      // windowed reconciliation of the new feed would never reach.
      store.events.push({
        id: 'old-outside-window',
        calendarId,
        occurrenceKey: 'alt-termin',
        uid: 'alt-termin',
        recurrenceId: null,
        sequence: null,
        title: 'Termin des alten Kalenders',
        description: null,
        location: null,
        startsAt: new Date(Date.now() - 700 * 86_400_000),
        endsAt: new Date(Date.now() - 700 * 86_400_000 + 3_600_000),
        allDay: false,
        status: 'confirmed',
        sourceUpdatedAt: null,
      });

      strapi.de = [strapiEntry({ googleShareUrl: shareUrl(ID_B) })];
      await sync.syncCatalog();

      expect(store.eventsOf(SLUG)).toHaveLength(0);
      expect(store.calendar(SLUG)).toMatchObject({
        googleCalendarId: ID_B,
        operationalStatus: 'pending',
        lastSuccessfulSyncAt: null,
        lastEtag: null,
        lastModified: null,
        lastContentHash: null,
        lastExpandedTo: null,
      });

      // The new feed happens to use the same ETag string; it must not be sent.
      google.feeds.set(ID_B, { body: singleEventFeed('neu-1', 'Neuer Kalender'), etag: '"v1"' });
      const outcome = await sync.syncCalendarEvents(SLUG);

      expect(google.lastCall()).toEqual({ calendarId: ID_B, conditional: {} });
      expect(outcome.status).toBe('success');
      expect(store.eventsOf(SLUG).map((row) => row['title'])).toEqual(['Neuer Kalender']);
    });
  });

  describe('a feed that disappears and comes back (VB-N02)', () => {
    it('clears events and validators together, then restores an unchanged feed', async () => {
      await seedReady();

      google.feeds.delete(ID_A);
      const gone = await sync.syncCalendarEvents(SLUG);
      expect(gone.status).toBe('revoked');
      expect(store.eventsOf(SLUG)).toHaveLength(0);
      expect(store.calendar(SLUG)).toMatchObject({
        operationalStatus: 'unavailable',
        lastEtag: null,
        lastModified: null,
        lastContentHash: null,
      });

      // Google serves the very same feed (and ETag) again.
      google.feeds.set(ID_A, { body: singleEventFeed(), etag: '"v1"' });
      const back = await sync.syncCalendarEvents(SLUG);

      expect(back.status).toBe('success');
      expect(store.eventsOf(SLUG)).toHaveLength(1);
      expect(store.calendar(SLUG)['operationalStatus']).toBe('ready');
    });

    it('recovers a calendar withdrawn before this fix that still holds old validators', async () => {
      await seedReady();
      // What the previous code left behind: events gone, validators kept.
      Object.assign(store.calendar(SLUG), { operationalStatus: 'revoked' });
      store.events = [];

      const back = await sync.syncCalendarEvents(SLUG);

      expect(google.lastCall().conditional).toEqual({});
      expect(back.status).toBe('success');
      expect(store.eventsOf(SLUG)).toHaveLength(1);
      expect(store.calendar(SLUG)['operationalStatus']).toBe('ready');
    });
  });

  describe('recurrences at the moving window edge (B-02)', () => {
    it('re-expands an unchanged feed once the window moved on by more than a day', async () => {
      const first = new Date();
      strapi.de = [strapiEntry()];
      await sync.syncCatalog();
      google.feeds.set(ID_A, { body: weeklySeriesFeed(), etag: '"v1"' });
      expect((await syncAt(first)).status).toBe('success');
      const firstEnd = sync.window(first).to;
      expect(store.eventsOf(SLUG).every((row) => (row['startsAt'] as Date) < firstEnd)).toBe(true);

      const later = new Date(first.getTime() + 8 * 86_400_000);
      const outcome = await syncAt(later);

      expect(outcome.status).toBe('success');
      expect(google.lastCall().conditional).toEqual({});
      const edge = store.eventsOf(SLUG).filter((row) => (row['startsAt'] as Date) >= firstEnd);
      expect(edge.length).toBeGreaterThanOrEqual(1);
      expect(store.calendar(SLUG)['lastExpandedTo']).toEqual(sync.window(later).to);
    });

    it('keeps the conditional fast path while the window has barely moved', async () => {
      const first = new Date();
      strapi.de = [strapiEntry()];
      await sync.syncCatalog();
      google.feeds.set(ID_A, { body: weeklySeriesFeed(), etag: '"v1"' });
      await syncAt(first);
      const stored = store.eventsOf(SLUG).length;

      const outcome = await syncAt(new Date(first.getTime() + 3_600_000));

      expect(outcome.status).toBe('notModified');
      expect(google.lastCall().conditional.etag).toBe('"v1"');
      expect(store.eventsOf(SLUG)).toHaveLength(stored);
    });
  });

  describe('retention of past occurrences (one year)', () => {
    function pastEvent(id: string, endedDaysAgo: number, now: Date): Row {
      const end = new Date(now.getTime() - endedDaysAgo * 86_400_000);
      return {
        id,
        calendarId: store.calendar(SLUG)['id'],
        occurrenceKey: id,
        uid: id,
        recurrenceId: null,
        sequence: null,
        title: id,
        description: null,
        location: null,
        startsAt: new Date(end.getTime() - 3_600_000),
        endsAt: end,
        allDay: false,
        status: 'confirmed',
        sourceUpdatedAt: null,
      };
    }

    it('drops occurrences that ended more than a year ago on every event run', async () => {
      await seedReady();
      const now = new Date();
      store.events.push(
        pastEvent('vor-400-tagen', 400, now),
        pastEvent('vor-367-tagen', 367, now),
        pastEvent('vor-300-tagen', 300, now),
        pastEvent('vor-40-tagen', 40, now),
      );

      await sync.syncEvents();

      const titles = store.eventsOf(SLUG).map((row) => row['title']);
      expect(titles).not.toContain('vor-400-tagen');
      expect(titles).not.toContain('vor-367-tagen');
      expect(titles).toEqual(expect.arrayContaining(['vor-300-tagen', 'vor-40-tagen']));
    });

    it('keeps the year boundary to the calendar year, not 365 days', async () => {
      await seedReady();
      // Only the two occurrences below count; the seeded one is dated today.
      store.events = [];
      const now = new Date('2028-03-01T12:00:00.000Z'); // 2028 is a leap year
      store.events.push(
        // Ended 2027-03-01T11:00Z: a year and an hour ago — removed.
        {
          ...pastEvent('ein-jahr-und-eine-stunde', 0, now),
          endsAt: new Date('2027-03-01T11:00:00.000Z'),
        },
        // Ended 2027-03-01T13:00Z: 366 days minus an hour ago, inside the year — kept.
        { ...pastEvent('knapp-ein-jahr', 0, now), endsAt: new Date('2027-03-01T13:00:00.000Z') },
      );

      expect(await sync.pruneExpiredEvents(now)).toBe(1);
      const titles = store.eventsOf(SLUG).map((row) => row['title']);
      expect(titles).toContain('knapp-ein-jahr');
      expect(titles).not.toContain('ein-jahr-und-eine-stunde');
    });
  });

  describe('synthetic user-test calendars (B-07)', () => {
    function seedUserTestCalendar(): void {
      store.calendars.push({
        ...CALENDAR_DEFAULTS,
        id: 'user-test-calendar',
        slug: 'user-test-stura',
        googleCalendarId: 'user-test-stura@user-test.invalid',
        nameDe: 'Testkalender',
        colorHex: '#5B3FD0',
        source: 'user-test',
        operationalStatus: 'ready',
        lastSuccessfulSyncAt: new Date(),
      });
      store.events.push({
        id: 'user-test-event',
        calendarId: 'user-test-calendar',
        occurrenceKey: 'stura-sitzung-1@user-test.invalid',
        uid: 'stura-sitzung-1@user-test.invalid',
        title: 'Synthetische Sitzung',
        startsAt: new Date(Date.now() + 86_400_000),
        endsAt: new Date(Date.now() + 90_000_000),
      });
    }

    it('never retires a seeded calendar that Strapi does not publish', async () => {
      seedUserTestCalendar();
      strapi.de = [strapiEntry()];

      const outcome = await sync.syncCatalog();

      expect(outcome).toMatchObject({ status: 'success', deactivated: 0 });
      expect(store.calendar('user-test-stura')['isActive']).toBe(true);
    });

    it('still retires a Strapi calendar that is no longer published', async () => {
      strapi.de = [strapiEntry(), strapiEntry({ slug: 'zweiter-kalender' })];
      await sync.syncCatalog();
      strapi.de = [strapiEntry()];

      const outcome = await sync.syncCatalog();

      expect(outcome.deactivated).toBe(1);
      expect(store.calendar('zweiter-kalender')['isActive']).toBe(false);
    });

    it('never downloads a seeded calendar or any id under the reserved .invalid TLD', async () => {
      seedUserTestCalendar();
      // A Strapi-owned row that still points at a reserved id, as a synthetic
      // performance dataset writes them.
      store.calendars.push({
        ...CALENDAR_DEFAULTS,
        id: 'reserved-calendar',
        slug: 'perf-kalender',
        googleCalendarId: 'perf-kalender@perf.INVALID',
        nameDe: 'Lastkalender',
        colorHex: '#5B3FD0',
        operationalStatus: 'ready',
        lastSuccessfulSyncAt: new Date(),
      });
      strapi.de = [strapiEntry()];
      await sync.syncCatalog();
      google.feeds.set(ID_A, { body: singleEventFeed(), etag: '"v1"' });

      const outcomes = await sync.syncEvents();

      expect(outcomes.map((outcome) => outcome.slug)).toEqual([SLUG]);
      expect(google.calls.map((call) => call.calendarId)).toEqual([ID_A]);
      expect(store.eventsOf('user-test-stura')).toHaveLength(1);
      expect(store.calendar('user-test-stura')['operationalStatus']).toBe('ready');
      expect(store.calendar('perf-kalender')['operationalStatus']).toBe('ready');

      // A direct call is refused just as firmly, without touching the row.
      const direct = await sync.syncCalendarEvents('user-test-stura');
      expect(direct).toMatchObject({ status: 'failed', errorCode: 'notSyncable' });
      expect(google.calls).toHaveLength(1);
      expect(store.eventsOf('user-test-stura')).toHaveLength(1);
    });

    it('lets Strapi take over a slug the seed used, together with its feed', async () => {
      seedUserTestCalendar();
      strapi.de = [strapiEntry({ slug: 'user-test-stura' })];

      await sync.syncCatalog();

      expect(store.calendar('user-test-stura')).toMatchObject({
        source: 'strapi',
        googleCalendarId: ID_A,
        operationalStatus: 'pending',
      });
      expect(store.eventsOf('user-test-stura')).toHaveLength(0);
    });
  });
});
