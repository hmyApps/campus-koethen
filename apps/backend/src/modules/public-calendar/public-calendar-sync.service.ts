import { createHash } from 'node:crypto';
import { Inject, Injectable, Logger } from '@nestjs/common';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { StrapiClient, StrapiListResponse } from '../strapi/strapi.client';
import { GooglePublicIcsClient, IcsClientError } from './google-public-ics.client';
import { IcsParseError, ParsedEvent, parseIcs } from './ics-parser';
import { CalendarDefinition } from './public-calendar.types';
import { validateCatalog } from './public-calendar.strapi';

/**
 * Public-calendar synchronisation.
 *
 * Two independent jobs, both governed by the project's core rule: a failed,
 * invalid or unexpectedly empty upstream response NEVER deletes stored data.
 *
 *  - `syncCatalog()` mirrors the PUBLISHED, VALIDATED Strapi definitions into
 *    the operational read-model. Strapi stays the canonical editorial source;
 *    Postgres only ever holds the last fully-validated snapshot.
 *  - `syncEvents()` downloads each active calendar's public ICS feed, expands
 *    it within a bounded window and reconciles it transactionally. A calendar
 *    becomes publicly visible only after validation AND a first successful sync.
 */

export interface CatalogOutcome {
  status: 'success' | 'empty' | 'failed';
  received: number;
  accepted: number;
  rejected: number;
  written: number;
  deactivated: number;
  errorCode?: string;
}

export interface EventOutcome {
  slug: string;
  status: 'success' | 'notModified' | 'empty' | 'stale' | 'revoked' | 'failed';
  received: number;
  written: number;
  removed: number;
  errorCode?: string;
}

const PUBLIC_CALENDAR_FEED_CONCURRENCY = 4;

@Injectable()
export class PublicCalendarSyncService {
  private readonly logger = new Logger(PublicCalendarSyncService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly strapi: StrapiClient,
    private readonly ics: GooglePublicIcsClient,
    @Inject(ENV) private readonly env: Env,
  ) {}

  // -------------------------------------------------------------------------
  // Catalogue
  // -------------------------------------------------------------------------

  async syncCatalog(): Promise<CatalogOutcome> {
    const run = await this.prisma.publicCalendarSyncRun.create({
      data: { kind: 'catalog', status: 'running' },
    });
    try {
      const [de, en] = await Promise.all([this.fetchAll('de'), this.fetchAll('en')]);
      const { definitions, received, rejected } = validateCatalog(de, en);

      // An empty (or fully-rejected) catalogue is treated as suspect: it keeps
      // the last good read-model instead of deactivating every calendar.
      if (definitions.length === 0) {
        await this.finishRun(run.id, {
          status: 'empty',
          eventsReceived: received,
          recordsRejected: rejected,
          errorMessage: 'empty or fully-rejected catalogue; existing definitions kept',
        });
        this.logger.warn('Public-calendar catalogue came back empty; existing definitions kept');
        return { status: 'empty', received, accepted: 0, rejected, written: 0, deactivated: 0 };
      }

      // Resolve duplicate channelSlug assignments deterministically (keep first, clear duplicate)
      const seenChannelSlugs = new Set<string>();
      for (const def of definitions) {
        if (def.channelSlug) {
          if (seenChannelSlugs.has(def.channelSlug)) {
            this.logger.warn({
              message: `Duplicate channelSlug "${def.channelSlug}" on calendar "${def.slug}". Keeping earlier assignment; clearing on this calendar.`,
              channelSlug: def.channelSlug,
              calendarSlug: def.slug,
            });
            def.channelSlug = null;
          } else {
            seenChannelSlugs.add(def.channelSlug);
          }
        }
      }

      const now = new Date();
      await this.prisma.$transaction(async (tx) => {
        for (const def of definitions) {
          await tx.publicCalendar.upsert({
            where: { slug: def.slug },
            create: { ...this.toRow(def), operationalStatus: 'pending', lastCatalogSyncAt: now },
            update: { ...this.toRow(def), isActive: true, lastCatalogSyncAt: now },
          });
        }
      });

      // Only after a complete, non-empty success may a calendar that Strapi no
      // longer publishes be retired. It is deactivated, never deleted.
      const retired = await this.prisma.publicCalendar.updateMany({
        where: { isActive: true, slug: { notIn: definitions.map((d) => d.slug) } },
        data: { isActive: false },
      });

      await this.finishRun(run.id, {
        status: 'success',
        eventsReceived: received,
        recordsAccepted: definitions.length,
        recordsRejected: rejected,
        recordsWritten: definitions.length,
        recordsRemoved: retired.count,
      });
      this.logger.log(
        `Public-calendar catalogue: ${definitions.length} upserted, ${retired.count} retired, ${rejected} rejected`,
      );
      return {
        status: 'success',
        received,
        accepted: definitions.length,
        rejected,
        written: definitions.length,
        deactivated: retired.count,
      };
    } catch (error) {
      const code = error instanceof Error ? error.name : 'unknown';
      await this.finishRun(run.id, {
        status: 'failed',
        errorCode: 'strapiUnavailable',
        errorMessage: this.redact(error),
      });
      this.logger.warn(
        `Public-calendar catalogue sync failed (${code}); existing definitions kept`,
      );
      return {
        status: 'failed',
        received: 0,
        accepted: 0,
        rejected: 0,
        written: 0,
        deactivated: 0,
        errorCode: code,
      };
    }
  }

  private toRow(def: CalendarDefinition) {
    return {
      slug: def.slug,
      googleCalendarId: def.googleCalendarId,
      channelSlug: def.channelSlug,
      nameDe: def.nameDe,
      nameEn: def.nameEn,
      colorHex: def.colorHex,
      sortOrder: def.sortOrder,
      defaultSubscribed: def.defaultSubscribed,
      includeEventDescription: def.includeEventDescription,
      includeEventLocation: def.includeEventLocation,
    };
  }

  private async fetchAll(locale: 'de' | 'en'): Promise<unknown[]> {
    const collected: unknown[] = [];
    let page = 1;
    for (;;) {
      const response = await this.strapi.get<StrapiListResponse<unknown>>('/api/public-calendars', {
        filters: { isActive: { $eq: true } },
        sort: ['sortOrder:asc', 'slug:asc'],
        pagination: { page, pageSize: 100 },
        populate: { channel: { fields: ['slug'] } },
        locale,
      });
      collected.push(...response.data);
      const pageCount = response.meta?.pagination?.pageCount ?? 1;
      if (page >= pageCount) break;
      page += 1;
    }
    return collected;
  }

  // -------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------

  window(now = new Date()): { from: Date; to: Date } {
    const day = 86_400_000;
    return {
      from: new Date(now.getTime() - this.env.PUBLIC_CALENDAR_LOOKBACK_DAYS * day),
      to: new Date(now.getTime() + this.env.PUBLIC_CALENDAR_LOOKAHEAD_DAYS * day),
    };
  }

  async syncEvents(): Promise<EventOutcome[]> {
    // Only the slug: `syncCalendarEvents` reads the row it needs itself, so
    // selecting the whole record here meant pulling every calendar twice per
    // run — including `lastEtag`, `lastModified` and `lastContentHash`, the
    // columns that carry the most text — and discarding the first copy.
    const calendars = await this.prisma.publicCalendar.findMany({
      where: { isActive: true },
      orderBy: { sortOrder: 'asc' },
      select: { slug: true },
    });
    if (calendars.length === 0) return [];

    // Four workers apply backpressure to both Google and Postgres. Results are
    // written into their catalogue position, so limiting concurrency never
    // makes the worker output nondeterministic. The outer guard also isolates
    // infrastructure failures that happen before a per-feed run can be
    // created and therefore sit outside syncCalendarEvents' normal catch path.
    const outcomes = new Array<EventOutcome>(calendars.length);
    let nextIndex = 0;
    const worker = async (): Promise<void> => {
      for (;;) {
        const index = nextIndex;
        nextIndex += 1;
        if (index >= calendars.length) return;

        const calendar = calendars[index]!;
        const startedAt = Date.now();
        try {
          outcomes[index] = await this.syncCalendarEvents(calendar.slug);
        } catch {
          outcomes[index] = this.recordEventMetric(
            {
              slug: calendar.slug,
              status: 'failed',
              received: 0,
              written: 0,
              removed: 0,
              errorCode: 'unexpected',
            },
            0,
            startedAt,
          );
        }
      }
    };

    const workerCount = Math.min(PUBLIC_CALENDAR_FEED_CONCURRENCY, calendars.length);
    await Promise.all(Array.from({ length: workerCount }, () => worker()));
    return outcomes;
  }

  async syncCalendarEvents(slug: string): Promise<EventOutcome> {
    const startedAt = Date.now();
    let responseBytes = 0;
    const calendar = await this.prisma.publicCalendar.findUnique({ where: { slug } });
    if (!calendar || !calendar.isActive) {
      return this.recordEventMetric(
        {
          slug,
          status: 'failed',
          received: 0,
          written: 0,
          removed: 0,
          errorCode: 'unknownCalendar',
        },
        responseBytes,
        startedAt,
      );
    }

    const win = this.window();
    const run = await this.prisma.publicCalendarSyncRun.create({
      data: {
        kind: 'events',
        status: 'running',
        calendarSlug: slug,
        rangeFrom: win.from,
        rangeTo: win.to,
      },
    });

    try {
      const fetched = await this.ics.fetchCalendar(calendar.googleCalendarId, {
        etag: calendar.lastEtag,
        lastModified: calendar.lastModified,
      });

      if (fetched.kind === 'notModified') {
        await this.prisma.publicCalendar.update({
          where: { id: calendar.id },
          data: { lastSuccessfulSyncAt: new Date(), operationalStatus: 'ready' },
        });
        await this.finishRun(run.id, { status: 'notModified' });
        return this.recordEventMetric(
          { slug, status: 'notModified', received: 0, written: 0, removed: 0 },
          responseBytes,
          startedAt,
        );
      }

      responseBytes = Buffer.byteLength(fetched.body, 'utf8');
      const contentHash = createHash('sha256').update(fetched.body).digest('hex');
      if (contentHash === calendar.lastContentHash) {
        await this.prisma.publicCalendar.update({
          where: { id: calendar.id },
          data: {
            lastSuccessfulSyncAt: new Date(),
            operationalStatus: 'ready',
            lastEtag: fetched.etag,
            lastModified: fetched.lastModified,
          },
        });
        await this.finishRun(run.id, { status: 'notModified', feedBytes: responseBytes });
        return this.recordEventMetric(
          { slug, status: 'notModified', received: 0, written: 0, removed: 0 },
          responseBytes,
          startedAt,
        );
      }

      const events = parseIcs(fetched.body, {
        windowStart: win.from,
        windowEnd: win.to,
        fallbackTimeZone: this.env.PUBLIC_CALENDAR_FALLBACK_TIME_ZONE,
        includeDescription: calendar.includeEventDescription,
        includeLocation: calendar.includeEventLocation,
        maxEvents: this.env.PUBLIC_CALENDAR_MAX_EVENTS,
        maxOccurrences: this.env.PUBLIC_CALENDAR_MAX_OCCURRENCES,
        maxOccurrencesPerEvent: this.env.PUBLIC_CALENDAR_MAX_OCCURRENCES_PER_EVENT,
        maxScannedOccurrences: this.env.PUBLIC_CALENDAR_MAX_SCANNED_OCCURRENCES,
        maxTextLength: this.env.PUBLIC_CALENDAR_MAX_TEXT_LENGTH,
      });

      const removed = await this.reconcile(calendar.id, win, events);

      await this.prisma.publicCalendar.update({
        where: { id: calendar.id },
        data: {
          operationalStatus: 'ready',
          lastEtag: fetched.etag,
          lastModified: fetched.lastModified,
          lastContentHash: contentHash,
          lastSuccessfulSyncAt: new Date(),
        },
      });
      await this.finishRun(run.id, {
        status: events.length === 0 ? 'empty' : 'success',
        feedBytes: responseBytes,
        eventsExpanded: events.length,
        recordsWritten: events.length,
        recordsRemoved: removed,
      });
      return this.recordEventMetric(
        {
          slug,
          status: events.length === 0 ? 'empty' : 'success',
          received: events.length,
          written: events.length,
          removed,
        },
        responseBytes,
        startedAt,
      );
    } catch (error) {
      const outcome = await this.handleEventFailure(
        run.id,
        calendar.id,
        slug,
        calendar.operationalStatus,
        calendar.lastSuccessfulSyncAt,
        error,
      );
      return this.recordEventMetric(outcome, responseBytes, startedAt);
    }
  }

  /**
   * One machine-readable observation per feed, deliberately without slug,
   * Google calendar id, URL or content. The operational sync-run row retains
   * the internal association; logs only expose bounded performance counters.
   */
  private recordEventMetric(
    outcome: EventOutcome,
    responseBytes: number,
    startedAt: number,
  ): EventOutcome {
    const metric = {
      event: 'publicCalendar.feedSync',
      status: outcome.status,
      durationMs: Math.max(0, Date.now() - startedAt),
      responseBytes,
      errorClass: outcome.errorCode ?? null,
      received: outcome.received,
      written: outcome.written,
      removed: outcome.removed,
    };
    if (outcome.status === 'failed' || outcome.status === 'stale' || outcome.status === 'revoked') {
      this.logger.warn('Public-calendar feed sync', metric);
    } else {
      this.logger.log('Public-calendar feed sync', metric);
    }
    return outcome;
  }

  /** True when the feed carries anything the stored occurrence does not already say. */
  private static occurrenceChanged(
    stored: {
      uid: string;
      recurrenceId: string | null;
      sequence: number | null;
      title: string;
      description: string | null;
      location: string | null;
      startsAt: Date;
      endsAt: Date;
      allDay: boolean;
      status: string;
      sourceUpdatedAt: Date | null;
    },
    next: ParsedEvent,
  ): boolean {
    return (
      stored.uid !== next.uid ||
      stored.recurrenceId !== next.recurrenceId ||
      stored.sequence !== next.sequence ||
      stored.title !== next.title ||
      stored.description !== next.description ||
      stored.location !== next.location ||
      stored.startsAt.getTime() !== next.start.getTime() ||
      stored.endsAt.getTime() !== next.end.getTime() ||
      stored.allDay !== next.allDay ||
      stored.status !== next.status ||
      (stored.sourceUpdatedAt?.getTime() ?? null) !== (next.sourceUpdatedAt?.getTime() ?? null)
    );
  }

  /**
   * Transactional, windowed, non-destructive reconciliation.
   *
   * Only reached when the feed body actually changed, and what changes in a
   * feed is normally one appointment — while an expanded window can hold
   * thousands of occurrences (PUBLIC_CALENDAR_MAX_OCCURRENCES). Writing every
   * one of them back to record a single move cost a round-trip and a row
   * update each, all inside one transaction. So the stored window is read once
   * and only the genuine differences are written; everything else just gets the
   * same `lastSeenAt` stamp the upsert wrote, in one statement.
   */
  private async reconcile(
    calendarId: string,
    win: { from: Date; to: Date },
    events: ParsedEvent[],
  ): Promise<number> {
    return this.prisma.$transaction(
      async (tx) => {
        const keptKeys = events.map((event) => event.occurrenceKey);
        const now = new Date();

        const stored = await tx.publicCalendarEvent.findMany({
          where: { calendarId, occurrenceKey: { in: keptKeys } },
          select: {
            id: true,
            occurrenceKey: true,
            uid: true,
            recurrenceId: true,
            sequence: true,
            title: true,
            description: true,
            location: true,
            startsAt: true,
            endsAt: true,
            allDay: true,
            status: true,
            sourceUpdatedAt: true,
          },
        });
        const storedByKey = new Map(stored.map((row) => [row.occurrenceKey, row]));

        const toCreate: ParsedEvent[] = [];
        const toUpdate: ParsedEvent[] = [];
        const unchangedIds: string[] = [];

        for (const event of events) {
          const row = storedByKey.get(event.occurrenceKey);
          if (!row) {
            toCreate.push(event);
          } else if (PublicCalendarSyncService.occurrenceChanged(row, event)) {
            toUpdate.push(event);
          } else {
            unchangedIds.push(row.id);
          }
        }

        if (toCreate.length > 0) {
          await tx.publicCalendarEvent.createMany({
            data: toCreate.map((event) => ({
              calendarId,
              occurrenceKey: event.occurrenceKey,
              uid: event.uid,
              recurrenceId: event.recurrenceId,
              sequence: event.sequence,
              title: event.title,
              description: event.description,
              location: event.location,
              startsAt: event.start,
              endsAt: event.end,
              allDay: event.allDay,
              status: event.status,
              sourceUpdatedAt: event.sourceUpdatedAt,
            })),
          });
        }

        for (const event of toUpdate) {
          await tx.publicCalendarEvent.update({
            where: {
              calendarId_occurrenceKey: { calendarId, occurrenceKey: event.occurrenceKey },
            },
            data: {
              uid: event.uid,
              recurrenceId: event.recurrenceId,
              sequence: event.sequence,
              title: event.title,
              description: event.description,
              location: event.location,
              startsAt: event.start,
              endsAt: event.end,
              allDay: event.allDay,
              status: event.status,
              sourceUpdatedAt: event.sourceUpdatedAt,
              lastSeenAt: now,
            },
          });
        }

        if (unchangedIds.length > 0) {
          await tx.publicCalendarEvent.updateMany({
            where: { id: { in: unchangedIds } },
            data: { lastSeenAt: now },
          });
        }

        // Delete only WITHIN the confirmed window and only rows not seen this run.
        const removed = await tx.publicCalendarEvent.deleteMany({
          where: {
            calendarId,
            startsAt: { gte: win.from, lte: win.to },
            occurrenceKey: { notIn: keptKeys.length > 0 ? keptKeys : ['__none__'] },
          },
        });
        return removed.count;
      },
      { timeout: 120_000, maxWait: 10_000 },
    );
  }

  private async handleEventFailure(
    runId: string,
    calendarId: string,
    slug: string,
    currentStatus: string,
    hadSuccess: Date | null,
    error: unknown,
  ): Promise<EventOutcome> {
    let errorCode = 'unknown';
    let nextStatus = currentStatus;
    let runStatus: EventOutcome['status'] = 'failed';

    if (error instanceof IcsClientError) {
      errorCode = error.kind;
      if (error.kind === 'feedNotFound' || error.kind === 'permissionRevoked') {
        // The feed is gone / no longer public: block it and clear its events so
        // stale data is not served indefinitely.
        nextStatus = error.kind === 'feedNotFound' ? 'unavailable' : 'revoked';
        runStatus = 'revoked';
        await this.prisma.publicCalendarEvent.deleteMany({ where: { calendarId } });
      } else {
        // Temporary transport error: keep the last good events, mark stale.
        nextStatus = hadSuccess ? 'stale' : 'pending';
        runStatus = 'stale';
      }
    } else if (error instanceof IcsParseError) {
      errorCode = error.kind;
      // Corrupt / oversized / recurrence-bomb: never destructive. Keep events.
      nextStatus = hadSuccess ? 'stale' : 'invalid';
      runStatus = 'stale';
    }

    await this.prisma.publicCalendar.update({
      where: { id: calendarId },
      data: { operationalStatus: nextStatus },
    });
    await this.finishRun(runId, { status: runStatus, errorCode, errorMessage: this.redact(error) });
    return { slug, status: runStatus, received: 0, written: 0, removed: 0, errorCode };
  }

  // -------------------------------------------------------------------------

  private async finishRun(
    id: string,
    data: {
      status: string;
      feedBytes?: number;
      eventsReceived?: number;
      eventsExpanded?: number;
      recordsAccepted?: number;
      recordsRejected?: number;
      recordsWritten?: number;
      recordsRemoved?: number;
      errorCode?: string;
      errorMessage?: string;
    },
  ): Promise<void> {
    await this.prisma.publicCalendarSyncRun.update({
      where: { id },
      data: { ...data, finishedAt: new Date() },
    });
  }

  private redact(error: unknown): string {
    if (error instanceof Error) return `${error.name}`.slice(0, 120);
    return 'unknown error';
  }

  async lastSuccessfulCatalogAt(): Promise<Date | null> {
    const run = await this.prisma.publicCalendarSyncRun.findFirst({
      where: { kind: 'catalog', status: 'success', finishedAt: { not: null } },
      orderBy: { finishedAt: 'desc' },
      select: { finishedAt: true },
    });
    return run?.finishedAt ?? null;
  }
}
