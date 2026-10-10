import { Logger } from '@nestjs/common';
import { validateEnv } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { IcsClientError } from './google-public-ics.client';
import { PublicCalendarSyncService } from './public-calendar-sync.service';

/**
 * Cost contract of the event reconciliation.
 *
 * Reconciliation only runs when the feed body changed, and what changes in a
 * feed is normally one appointment — while an expanded window can hold
 * thousands of occurrences. Writing every one of them back to record a single
 * move cost a round-trip and a row update each, inside one transaction. What
 * ends up stored is proven against a real database in
 * test/public-calendar-sync.integration.spec.ts.
 */
describe('PublicCalendarSyncService reconciliation', () => {
  const env = validateEnv(process.env);

  afterEach(() => jest.restoreAllMocks());

  /** A synthetic feed with `count` timed events, all inside the sync window. */
  function ics(count: number): string {
    const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Synthetic//Test//EN'];
    for (let index = 0; index < count; index += 1) {
      const at = new Date(Date.now() + (index + 1) * 3_600_000)
        .toISOString()
        .replace(/[-:]/g, '')
        .replace(/\.\d{3}Z$/, 'Z');
      lines.push(
        'BEGIN:VEVENT',
        `UID:event-${index}`,
        'DTSTAMP:20260101T000000Z',
        `DTSTART:${at}`,
        `DTEND:${at}`,
        `SUMMARY:Termin ${index}`,
        'END:VEVENT',
      );
    }
    lines.push('END:VCALENDAR');
    return lines.join('\r\n') + '\r\n';
  }

  const calendarRow = {
    id: 'calendar-1',
    slug: 'beispielkalender-a',
    isActive: true,
    googleCalendarId: 'beispielkalender-a@group.calendar.google.com',
    lastEtag: null,
    lastModified: null,
    lastContentHash: null,
    lastExpandedTo: null,
    source: 'strapi',
    includeEventDescription: false,
    includeEventLocation: false,
    operationalStatus: 'ready',
    lastSuccessfulSyncAt: new Date(),
  };

  /**
   * Runs one event sync over `body` against a store that already holds
   * `stored` occurrences, and reports what the write phase did.
   */
  async function run(body: string | Error, stored: Array<Record<string, unknown>>) {
    const tx = {
      publicCalendar: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      publicCalendarEvent: {
        findMany: jest.fn().mockResolvedValue(stored),
        createMany: jest.fn().mockResolvedValue({ count: 0 }),
        update: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };
    const prisma = {
      publicCalendar: {
        findUnique: jest.fn().mockResolvedValue(calendarRow),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      publicCalendarSyncRun: {
        create: jest.fn().mockResolvedValue({ id: 'run-1' }),
        update: jest.fn(),
      },
      $transaction: jest.fn(async (operation: (transaction: typeof tx) => Promise<number>) =>
        operation(tx),
      ),
    } as unknown as PrismaService;

    const service = new PublicCalendarSyncService(
      prisma,
      {} as never,
      {
        fetchCalendar: async () => {
          if (body instanceof Error) throw body;
          return { kind: 'ok', body, etag: null, lastModified: null };
        },
      } as never,
      env,
    );

    const outcome = await service.syncCalendarEvents('beispielkalender-a');
    return { outcome, tx };
  }

  /** The row the parser would produce for `index`, as already stored. */
  function storedOccurrence(index: number, parsed: { occurrenceKey: string; startsAt: Date }) {
    return {
      id: `row-${index}`,
      occurrenceKey: parsed.occurrenceKey,
      uid: `event-${index}`,
      recurrenceId: null,
      sequence: null,
      title: `Termin ${index}`,
      description: null,
      location: null,
      startsAt: parsed.startsAt,
      endsAt: parsed.startsAt,
      allDay: false,
      status: 'confirmed',
      sourceUpdatedAt: null,
    };
  }

  /** Reads back what the parser made of `body`, so the fake store can match it. */
  async function parsedRows(body: string, count: number) {
    const { tx } = await run(body, []);
    const created = (tx.publicCalendarEvent.createMany.mock.calls[0] as [{ data: unknown[] }])[0]
      .data as Array<{ occurrenceKey: string; startsAt: Date }>;
    expect(created).toHaveLength(count);
    return created.map((row, index) => storedOccurrence(index, row));
  }

  it('reads only the slug when listing the calendars to sync', async () => {
    // `syncCalendarEvents` reads the row it needs itself. Selecting the whole
    // record here pulled every calendar twice per run — including the
    // validator and content-hash columns — only to discard the first copy.
    const findMany = jest.fn().mockResolvedValue([]);
    const prisma = {
      publicCalendar: { findMany },
    } as unknown as PrismaService;

    const service = new PublicCalendarSyncService(prisma, {} as never, {} as never, env);
    await expect(service.syncEvents()).resolves.toEqual([]);

    expect(findMany).toHaveBeenCalledTimes(1);
    const args = findMany.mock.calls[0]![0] as { select?: Record<string, boolean> };
    expect(args.select).toEqual({ slug: true });
  });

  it('runs at most four calendar feeds at once and preserves result order', async () => {
    const calendars = Array.from({ length: 11 }, (_, index) => ({ slug: `calendar-${index}` }));
    const prisma = {
      publicCalendar: { findMany: jest.fn().mockResolvedValue(calendars) },
    } as unknown as PrismaService;
    const service = new PublicCalendarSyncService(prisma, {} as never, {} as never, env);
    let active = 0;
    let peak = 0;

    jest.spyOn(service, 'syncCalendarEvents').mockImplementation(async (slug) => {
      active += 1;
      peak = Math.max(peak, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active -= 1;
      return { slug, status: 'success', received: 0, written: 0, removed: 0 };
    });

    const outcomes = await service.syncEvents();

    expect(peak).toBe(4);
    expect(outcomes.map((outcome) => outcome.slug)).toEqual(calendars.map((row) => row.slug));
  });

  it('keeps syncing other feeds when one isolated feed throws unexpectedly', async () => {
    const calendars = [{ slug: 'first' }, { slug: 'broken' }, { slug: 'last' }];
    const prisma = {
      publicCalendar: { findMany: jest.fn().mockResolvedValue(calendars) },
    } as unknown as PrismaService;
    const service = new PublicCalendarSyncService(prisma, {} as never, {} as never, env);

    jest.spyOn(service, 'syncCalendarEvents').mockImplementation(async (slug) => {
      if (slug === 'broken') throw new Error('database details must not escape');
      return { slug, status: 'success', received: 0, written: 0, removed: 0 };
    });

    const outcomes = await service.syncEvents();

    expect(outcomes.map((outcome) => outcome.status)).toEqual(['success', 'failed', 'success']);
    expect(outcomes[1]).toMatchObject({ slug: 'broken', errorCode: 'unexpected' });
  });

  it('logs one structured, identifier-free metric with actual UTF-8 bytes per feed', async () => {
    const body = ics(1).replace('Termin 0', 'Termin Köthen');
    const log = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);

    await run(body, []);

    const metric = log.mock.calls.find(
      ([message, details]) =>
        message === 'Public-calendar feed sync' &&
        typeof details === 'object' &&
        details !== null &&
        (details as { event?: string }).event === 'publicCalendar.feedSync',
    )?.[1] as Record<string, unknown> | undefined;
    expect(metric).toMatchObject({
      event: 'publicCalendar.feedSync',
      status: 'success',
      responseBytes: Buffer.byteLength(body, 'utf8'),
      errorClass: null,
      durationMs: expect.any(Number),
    });
    expect(JSON.stringify(metric)).not.toContain(calendarRow.slug);
    expect(JSON.stringify(metric)).not.toContain(calendarRow.googleCalendarId);
    expect(JSON.stringify(metric)).not.toContain('Termin Köthen');
    log.mockRestore();
  });

  it('reports a safe error class without logging the calendar identifier', async () => {
    const warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);

    await run(new IcsClientError('timeout', 'secret upstream detail'), []);

    const metric = warn.mock.calls.find(
      ([message, details]) =>
        message === 'Public-calendar feed sync' &&
        typeof details === 'object' &&
        details !== null &&
        (details as { event?: string }).event === 'publicCalendar.feedSync',
    )?.[1] as Record<string, unknown> | undefined;
    expect(metric).toMatchObject({
      event: 'publicCalendar.feedSync',
      status: 'stale',
      responseBytes: 0,
      errorClass: 'timeout',
      durationMs: expect.any(Number),
    });
    expect(JSON.stringify(metric)).not.toContain(calendarRow.slug);
    expect(JSON.stringify(metric)).not.toContain(calendarRow.googleCalendarId);
    expect(JSON.stringify(metric)).not.toContain('secret upstream detail');
    warn.mockRestore();
  });

  it('inserts a brand-new window in one statement', async () => {
    const { outcome, tx } = await run(ics(200), []);

    expect(outcome.status).toBe('success');
    expect(tx.publicCalendarEvent.createMany).toHaveBeenCalledTimes(1);
    expect(tx.publicCalendarEvent.update).not.toHaveBeenCalled();
    expect(tx.publicCalendarEvent.updateMany).not.toHaveBeenCalled();
  });

  it('touches nothing but the seen-stamp when the window is unchanged', async () => {
    const body = ics(200);
    const stored = await parsedRows(body, 200);

    const { tx } = await run(body, stored);

    expect(tx.publicCalendarEvent.createMany).not.toHaveBeenCalled();
    expect(tx.publicCalendarEvent.update).not.toHaveBeenCalled();
    expect(tx.publicCalendarEvent.updateMany).toHaveBeenCalledTimes(1);
    expect(tx.publicCalendarEvent.updateMany).toHaveBeenCalledWith({
      where: { id: { in: stored.map((row) => row.id) } },
      data: { lastSeenAt: expect.any(Date) },
    });
  });

  it('writes one row for the single appointment that moved', async () => {
    // One body, so the two runs see the same instants; only the summary of a
    // single appointment differs — exactly what a real feed edit looks like.
    const body = ics(200);
    const stored = await parsedRows(body, 200);
    const renamed = body.replace('SUMMARY:Termin 42\r\n', 'SUMMARY:Termin 42 (verschoben)\r\n');
    expect(renamed).not.toBe(body);

    const { tx } = await run(renamed, stored);

    expect(tx.publicCalendarEvent.createMany).not.toHaveBeenCalled();
    expect(tx.publicCalendarEvent.update).toHaveBeenCalledTimes(1);
    expect(tx.publicCalendarEvent.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ title: 'Termin 42 (verschoben)' }),
      }),
    );
    expect(tx.publicCalendarEvent.updateMany).toHaveBeenCalledTimes(1);
  });
});
