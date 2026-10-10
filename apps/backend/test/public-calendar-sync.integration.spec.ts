import { validateEnv } from '../src/config/env.schema';
import {
  IcsClientError,
  IcsFetchResult,
} from '../src/modules/public-calendar/google-public-ics.client';
import { PublicCalendarSyncService } from '../src/modules/public-calendar/public-calendar-sync.service';
import { PublicCalendarService } from '../src/modules/public-calendar/public-calendar.service';
import type { PrismaService } from '../src/prisma/prisma.service';
import { createTestPrisma, resetDatabase } from './helpers/database';

// Real PostgreSQL setup and cleanup can exceed Jest's 5s default on shared CI.
jest.setTimeout(60_000);

/**
 * Integration tests for the public-calendar sync against a REAL Postgres.
 * All fixtures are synthetic (fictional calendars, no real Google ids).
 */

const CID = Buffer.from('beispielkalender-a@group.calendar.google.com', 'utf8').toString(
  'base64url',
);
const SHARE = `https://calendar.google.com/calendar/u/0?cid=${CID}`;

function strapiEntry(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    slug: 'beispielkalender-a',
    name: 'Beispielkalender A',
    description: 'Öffentliche Veranstaltungen',
    googleShareUrl: SHARE,
    colorHex: '#5B3FD0',
    iconKey: 'calendar',
    sortOrder: 1,
    isActive: true,
    defaultSubscribed: true,
    includeEventDescription: true,
    includeEventLocation: true,
    ...overrides,
  };
}

function icsWith(events: Array<{ uid: string; dayOffset: number; summary: string }>): string {
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Synthetic//Test//EN'];
  for (const e of events) {
    const d = new Date(Date.now() + e.dayOffset * 86_400_000);
    const stamp = d
      .toISOString()
      .replace(/[-:]/g, '')
      .replace(/\.\d{3}Z$/, 'Z');
    lines.push(
      'BEGIN:VEVENT',
      `UID:${e.uid}`,
      'DTSTAMP:20260101T000000Z',
      `DTSTART:${stamp}`,
      `DTEND:${stamp}`,
      `SUMMARY:${e.summary}`,
      'END:VEVENT',
    );
  }
  lines.push('END:VCALENDAR');
  return lines.join('\r\n') + '\r\n';
}

class FakeStrapi {
  de: unknown[] = [];
  en: unknown[] = [];
  error: Error | null = null;
  get = async (_path: string, query?: Record<string, unknown>): Promise<unknown> => {
    if (this.error) throw this.error;
    const data = query?.locale === 'en' ? this.en : this.de;
    return {
      data,
      meta: { pagination: { page: 1, pageSize: 100, pageCount: 1, total: data.length } },
    };
  };
}

class FakeIcs {
  next: IcsFetchResult | Error = { kind: 'ok', body: '', etag: null, lastModified: null };
  fetchCalendar = async (): Promise<IcsFetchResult> => {
    if (this.next instanceof Error) throw this.next;
    return this.next;
  };
}

describe('PublicCalendarSyncService (integration)', () => {
  const env = validateEnv(process.env);
  let prisma: PrismaService;
  let strapi: FakeStrapi;
  let ics: FakeIcs;
  let sync: PublicCalendarSyncService;
  let read: PublicCalendarService;

  const okBody = (body: string): IcsFetchResult => ({
    kind: 'ok',
    body,
    etag: null,
    lastModified: null,
  });

  beforeAll(() => {
    prisma = createTestPrisma() as unknown as PrismaService;
  });
  afterAll(async () => {
    await (prisma as unknown as { $disconnect: () => Promise<void> }).$disconnect();
  });
  beforeEach(async () => {
    await resetDatabase(prisma);
    strapi = new FakeStrapi();
    ics = new FakeIcs();
    sync = new PublicCalendarSyncService(prisma, strapi as never, ics as never, env);
    read = new PublicCalendarService(prisma, env);
  });

  async function seedReadyCalendar(
    body = icsWith([{ uid: 'a', dayOffset: 2, summary: 'Beispielsitzung' }]),
  ): Promise<void> {
    strapi.de = [strapiEntry()];
    await sync.syncCatalog();
    ics.next = okBody(body);
    await sync.syncCalendarEvents('beispielkalender-a');
  }

  describe('catalogue', () => {
    it('mirrors a valid definition as pending (not yet servable)', async () => {
      strapi.de = [strapiEntry()];
      const outcome = await sync.syncCatalog();
      expect(outcome.status).toBe('success');
      const row = await prisma.publicCalendar.findUnique({ where: { slug: 'beispielkalender-a' } });
      expect(row?.googleCalendarId).toBe('beispielkalender-a@group.calendar.google.com');
      expect(row?.operationalStatus).toBe('pending');
      // Not servable until a first successful event sync.
      const listed = await read.listCalendars({ requestedLocale: 'de', resolvedLocale: 'de' });
      expect(listed.data).toHaveLength(0);
    });

    it('an empty catalogue keeps the last good definitions', async () => {
      strapi.de = [strapiEntry()];
      await sync.syncCatalog();
      strapi.de = [];
      const outcome = await sync.syncCatalog();
      expect(outcome.status).toBe('empty');
      const count = await prisma.publicCalendar.count();
      expect(count).toBe(1);
    });

    it('mirrors channelSlug from Strapi and resolves duplicates deterministically', async () => {
      strapi.de = [
        strapiEntry({ slug: 'cal-1', channel: { slug: 'shared-channel' } }),
        strapiEntry({ slug: 'cal-2', channel: { slug: 'shared-channel' } }),
      ];
      const outcome = await sync.syncCatalog();
      expect(outcome.status).toBe('success');

      const cal1 = await prisma.publicCalendar.findUnique({ where: { slug: 'cal-1' } });
      const cal2 = await prisma.publicCalendar.findUnique({ where: { slug: 'cal-2' } });

      expect(cal1?.channelSlug).toBe('shared-channel');
      expect(cal2?.channelSlug).toBeNull(); // cleared on duplicate
    });

    it('a Strapi failure keeps the last good definitions', async () => {
      strapi.de = [strapiEntry()];
      await sync.syncCatalog();
      strapi.error = new Error('boom');
      const outcome = await sync.syncCatalog();
      expect(outcome.status).toBe('failed');
      expect(await prisma.publicCalendar.count()).toBe(1);
    });
  });

  describe('events', () => {
    it('a successful sync makes the calendar servable with events', async () => {
      await seedReadyCalendar();
      const row = await prisma.publicCalendar.findUnique({ where: { slug: 'beispielkalender-a' } });
      expect(row?.operationalStatus).toBe('ready');
      expect(await prisma.publicCalendarEvent.count()).toBe(1);
      const listed = await read.listCalendars({ requestedLocale: 'de', resolvedLocale: 'de' });
      expect(listed.data).toHaveLength(1);
      expect(listed.data[0]?.googleOpenUrl).toContain('calendar.google.com/calendar/render');
    });

    it('reconciliation removes stale events within the window', async () => {
      await seedReadyCalendar();
      ics.next = okBody(icsWith([{ uid: 'b', dayOffset: 3, summary: 'Neuer Termin' }]));
      await sync.syncCalendarEvents('beispielkalender-a');
      const events = await prisma.publicCalendarEvent.findMany();
      expect(events).toHaveLength(1);
      expect(events[0]?.uid).toBe('b');
    });

    it('rewrites only the occurrence the feed actually changed', async () => {
      const body = icsWith([
        { uid: 'a', dayOffset: 2, summary: 'Sitzung A' },
        { uid: 'b', dayOffset: 3, summary: 'Sitzung B' },
        { uid: 'c', dayOffset: 4, summary: 'Sitzung C' },
      ]);
      await seedReadyCalendar(body);

      const before = await prisma.publicCalendarEvent.findMany({ orderBy: { uid: 'asc' } });
      expect(before).toHaveLength(3);

      // One appointment was renamed upstream; the rest of the feed is
      // byte-for-byte what the previous run already stored.
      ics.next = okBody(body.replace('SUMMARY:Sitzung B', 'SUMMARY:Sitzung B (verschoben)'));
      const outcome = await sync.syncCalendarEvents('beispielkalender-a');
      expect(outcome.status).toBe('success');

      const after = await prisma.publicCalendarEvent.findMany({ orderBy: { uid: 'asc' } });
      // Nothing was recreated: reconciliation is an update, not a rewrite.
      expect(after.map((event) => event.id)).toEqual(before.map((event) => event.id));
      expect(after.find((event) => event.uid === 'b')!.title).toBe('Sitzung B (verschoben)');

      for (const uid of ['a', 'c']) {
        const previous = before.find((event) => event.uid === uid)!;
        const current = after.find((event) => event.uid === uid)!;
        expect({ ...current, lastSeenAt: null, updatedAt: null }).toEqual({
          ...previous,
          lastSeenAt: null,
          updatedAt: null,
        });
        // Untouched in content, but still confirmed as seen by this run.
        expect(current.lastSeenAt.getTime()).toBeGreaterThanOrEqual(previous.lastSeenAt.getTime());
      }
    });

    it('a temporary error keeps the last good events and marks the calendar stale', async () => {
      await seedReadyCalendar();
      ics.next = new IcsClientError('timeout', 'The calendar feed request timed out.');
      const outcome = await sync.syncCalendarEvents('beispielkalender-a');
      expect(outcome.status).toBe('stale');
      expect(await prisma.publicCalendarEvent.count()).toBe(1); // kept
      const row = await prisma.publicCalendar.findUnique({ where: { slug: 'beispielkalender-a' } });
      expect(row?.operationalStatus).toBe('stale');
      // A stale calendar is still served (with the age reported).
      const listed = await read.listCalendars({ requestedLocale: 'de', resolvedLocale: 'de' });
      expect(listed.data).toHaveLength(1);
      expect(listed.data[0]?.dataStale).toBe(true);
    });

    it('a revoked feed hides the calendar and clears its events', async () => {
      await seedReadyCalendar();
      ics.next = new IcsClientError('permissionRevoked', 'The calendar is no longer public.', 410);
      const outcome = await sync.syncCalendarEvents('beispielkalender-a');
      expect(outcome.status).toBe('revoked');
      expect(await prisma.publicCalendarEvent.count()).toBe(0);
      const row = await prisma.publicCalendar.findUnique({ where: { slug: 'beispielkalender-a' } });
      expect(row?.operationalStatus).toBe('revoked');
      const listed = await read.listCalendars({ requestedLocale: 'de', resolvedLocale: 'de' });
      expect(listed.data).toHaveLength(0);
    });

    it('a feed that comes back unchanged after a 404 is restored, not "ready" and empty', async () => {
      const body = icsWith([{ uid: 'a', dayOffset: 2, summary: 'Beispielsitzung' }]);
      await seedReadyCalendar(body);
      ics.next = new IcsClientError('feedNotFound', 'The calendar feed does not exist.', 404);
      await sync.syncCalendarEvents('beispielkalender-a');
      const gone = await prisma.publicCalendar.findUnique({
        where: { slug: 'beispielkalender-a' },
      });
      expect(gone).toMatchObject({ operationalStatus: 'unavailable', lastContentHash: null });

      ics.next = okBody(body);
      const outcome = await sync.syncCalendarEvents('beispielkalender-a');
      expect(outcome.status).toBe('success');
      expect(await prisma.publicCalendarEvent.count()).toBe(1);
    });

    it('switching a text flag forces a re-parse of an unchanged feed', async () => {
      const body =
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:mit-text\r\n' +
        'DTSTAMP:20260101T000000Z\r\n' +
        `DTSTART:${new Date(Date.now() + 2 * 86_400_000)
          .toISOString()
          .replace(/[-:]/g, '')
          .replace(/\.\d{3}Z$/, 'Z')}\r\n` +
        'DURATION:PT1H\r\nSUMMARY:Sitzung\r\nDESCRIPTION:Beschreibung\r\n' +
        'LOCATION:Beispielraum\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
      await seedReadyCalendar(body);
      expect((await prisma.publicCalendarEvent.findFirst())?.description).toBe('Beschreibung');

      strapi.de = [strapiEntry({ includeEventDescription: false })];
      await sync.syncCatalog();
      ics.next = okBody(body);
      const outcome = await sync.syncCalendarEvents('beispielkalender-a');

      expect(outcome.status).toBe('success');
      const stored = await prisma.publicCalendarEvent.findFirst();
      expect(stored).toMatchObject({ description: null, location: 'Beispielraum' });
    });

    it('never retires or downloads a seeded user-test calendar', async () => {
      await prisma.publicCalendar.create({
        data: {
          slug: 'user-test-stura',
          googleCalendarId: 'user-test-stura@user-test.invalid',
          nameDe: 'Testkalender',
          colorHex: '#5B3FD0',
          source: 'user-test',
          operationalStatus: 'ready',
          lastSuccessfulSyncAt: new Date(),
        },
      });
      await prisma.publicCalendar.create({
        data: {
          slug: 'perf-kalender',
          googleCalendarId: 'perf-kalender@perf.invalid',
          nameDe: 'Lastkalender',
          colorHex: '#5B3FD0',
        },
      });
      await seedReadyCalendar();

      const outcomes = await sync.syncEvents();

      expect(outcomes.map((outcome) => outcome.slug)).toEqual(['beispielkalender-a']);
      const seeded = await prisma.publicCalendar.findUnique({ where: { slug: 'user-test-stura' } });
      expect(seeded).toMatchObject({ isActive: true, operationalStatus: 'ready' });
    });

    it('an unchanged content hash skips re-processing but stays ready', async () => {
      const body = icsWith([{ uid: 'a', dayOffset: 2, summary: 'Beispielsitzung' }]);
      await seedReadyCalendar(body);
      ics.next = okBody(body);
      // Same body → same hash → notModified fast-path.
      const outcome = await sync.syncCalendarEvents('beispielkalender-a');
      expect(outcome.status).toBe('notModified');
      expect(await prisma.publicCalendarEvent.count()).toBe(1);
    });

    it('keeps past occurrences for one year after they ended, then removes them', async () => {
      await seedReadyCalendar();
      const calendar = await prisma.publicCalendar.findUniqueOrThrow({
        where: { slug: 'beispielkalender-a' },
      });
      const day = 86_400_000;
      const past = (key: string, endedDaysAgo: number) => {
        const endsAt = new Date(Date.now() - endedDaysAgo * day);
        return {
          calendarId: calendar.id,
          occurrenceKey: key,
          uid: key,
          title: key,
          startsAt: new Date(endsAt.getTime() - 3_600_000),
          endsAt,
        };
      };
      await prisma.publicCalendarEvent.createMany({
        data: [past('vor-400-tagen', 400), past('vor-300-tagen', 300)],
      });

      await sync.syncEvents();

      const keys = (await prisma.publicCalendarEvent.findMany({ select: { occurrenceKey: true } }))
        .map((row) => row.occurrenceKey)
        .sort();
      expect(keys).not.toContain('vor-400-tagen');
      expect(keys).toContain('vor-300-tagen');
    });
  });

  describe('read model', () => {
    it('aggregated events with an empty selection returns nothing (never all)', async () => {
      await seedReadyCalendar();
      const from = new Date(Date.now() - 86_400_000);
      const to = new Date(Date.now() + 30 * 86_400_000);
      expect((await read.getAggregatedEvents([], from, to)).events).toHaveLength(0);
      expect(
        (await read.getAggregatedEvents(['beispielkalender-a'], from, to)).events,
      ).toHaveLength(1);
    });

    it('returns an event that starts before from and ends within the window', async () => {
      // Event spanning from -2 days to +1 day
      const ics =
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n' +
        'UID:spanning-event\r\nDTSTAMP:20260101T000000Z\r\n' +
        `DTSTART:${new Date(Date.now() - 2 * 86_400_000)
          .toISOString()
          .replace(/[-:]/g, '')
          .replace(/\.\d{3}Z$/, 'Z')}\r\n` +
        `DTEND:${new Date(Date.now() + 1 * 86_400_000)
          .toISOString()
          .replace(/[-:]/g, '')
          .replace(/\.\d{3}Z$/, 'Z')}\r\n` +
        'SUMMARY:Spanning Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

      await seedReadyCalendar(ics);

      const from = new Date();
      const to = new Date(Date.now() + 3 * 86_400_000);

      const { events, truncated } = await read.getAggregatedEvents(
        ['beispielkalender-a'],
        from,
        to,
      );
      expect(events).toHaveLength(1);
      expect(events[0]?.title).toBe('Spanning Event');
      expect(truncated).toBe(false);
    });

    it('builds a combined Google embed URL for selected calendars', async () => {
      await seedReadyCalendar();
      const url = await read.buildGoogleViewUrl(['beispielkalender-a', 'beispielkalender-a'], 'de');
      expect(url).toContain('https://calendar.google.com/calendar/embed');
      expect(url).toContain('ctz=Europe%2FBerlin');
      // Deduplicated to a single src.
      expect(url.match(/src=/g)).toHaveLength(1);
    });
  });
});
