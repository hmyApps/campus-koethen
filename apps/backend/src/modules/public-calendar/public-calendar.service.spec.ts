// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import { Logger } from '@nestjs/common';
import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import {
  computeEventKey,
  eventKeyCacheSize,
  PublicCalendarService,
} from './public-calendar.service';

const en = { requestedLocale: 'en', resolvedLocale: 'en' } as const;

/**
 * The event query mock is handed back as a standalone `jest.fn`, not read off
 * the stub object at assertion time: `expect(prisma.x.findMany)` would detach
 * a method from its receiver, which `@typescript-eslint/unbound-method`
 * rightly flags.
 */
function serviceWith(
  row: Record<string, unknown>,
  events: Record<string, unknown>[] = [],
  envOverrides: Partial<Env> = {},
): {
  service: PublicCalendarService;
  eventFindMany: jest.Mock;
  calendarFindMany: jest.Mock;
  calendarFindFirst: jest.Mock;
} {
  const eventFindMany = jest.fn(async () => events);
  const calendarFindMany = jest.fn(async () => [row]);
  const calendarFindFirst = jest.fn(async () => row);
  const prisma = {
    publicCalendar: {
      findMany: calendarFindMany,
      findFirst: calendarFindFirst,
    },
    publicCalendarEvent: {
      findMany: eventFindMany,
    },
  } as unknown as PrismaService;
  const env = {
    PUBLIC_CALENDAR_STALE_AFTER_MINUTES: 720,
    PUBLIC_CALENDAR_LOOKAHEAD_DAYS: 400,
    PUBLIC_CALENDAR_API_MAX_RANGE_DAYS: 400,
    PUBLIC_CALENDAR_API_MAX_EVENTS: 2000,
    ...envOverrides,
  } as Env;
  return {
    service: new PublicCalendarService(prisma, env),
    eventFindMany,
    calendarFindMany,
    calendarFindFirst,
  };
}

/**
 * The service's own private logger, reached through one narrow cast instead of
 * `any` — AGENTS.md keeps `no-explicit-any` at error, and a spy on
 * `Logger.prototype` would leak across instances.
 */
function loggerOf(service: PublicCalendarService): Logger {
  return (service as unknown as { readonly logger: Logger }).logger;
}

const row = {
  id: 'calendar-id',
  slug: 'events',
  channelSlug: 'campus-events',
  googleCalendarId: 'calendar@example.test',
  nameDe: 'Veranstaltungen',
  nameEn: 'Events',
  colorHex: '#C2185B',
  sortOrder: 10,
  defaultSubscribed: true,
  operationalStatus: 'ready',
  lastSuccessfulSyncAt: new Date(),
};

describe('PublicCalendarService', () => {
  describe('localisation and channelSlug', () => {
    it('serves the English catalogue without a fallback when it is complete', async () => {
      const { service, calendarFindMany } = serviceWith(row);
      const result = await service.listCalendars(en);

      expect(result.data[0]?.name).toBe('Events');
      expect(result.data[0]?.channelSlug).toBe('campus-events');
      expect(result.translationFallback).toBe(false);
      expect(calendarFindMany.mock.calls[0]![0].select).toEqual({
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
      });
    });

    it('flags a fallback when the English name is missing', async () => {
      const { service } = serviceWith({ ...row, nameEn: null });
      const result = await service.listCalendars(en);

      expect(result.data[0]?.name).toBe('Veranstaltungen');
      expect(result.translationFallback).toBe(true);
    });
  });

  describe('eventKey derivation and event queries', () => {
    it('computes a stable 22-char base64url eventKey without padding', () => {
      const key1 = computeEventKey('events', 'uid123_slot0');
      const key2 = computeEventKey('events', 'uid123_slot0');
      const key3 = computeEventKey('other-cal', 'uid123_slot0');

      expect(key1).toHaveLength(22);
      expect(key1).toBe(key2);
      expect(key1).not.toBe(key3);
      expect(key1).not.toContain('+');
      expect(key1).not.toContain('/');
      expect(key1).not.toContain('=');
    });

    it('derives exactly the published key for a known input', () => {
      // These ids are handed to clients and are the only handle a client has on
      // an occurrence. The derivation is SHA-256 over `slug \0 occurrenceKey`,
      // base64url, first 22 characters — pinned to literals so a change to how
      // the key is cached can never quietly change the key itself.
      expect(computeEventKey('events', 'uid123_slot0')).toBe('G7noAtchTkQ9iNAUTINfwX');
      expect(computeEventKey('cal-a', 'occ-1')).toBe('Cq23Y13q76cCn83barUyYa');
      expect(computeEventKey('cal-b', 'occ-1')).toBe('R5d1MXfJsgncnzPdj3SawE');
      expect(computeEventKey('', 'occ-1')).toBe('vAD613qArjmSCEZs6Gp0lc');
    });

    it('keeps the derived-key cache bounded and correct after eviction', () => {
      // Slugs and occurrence keys come from stored data, so the cache must not
      // be able to grow with them.
      for (let index = 0; index < 12_000; index += 1) {
        computeEventKey(`bounded-cal-${index % 40}`, `bounded-occ-${index}`);
      }

      expect(eventKeyCacheSize()).toBeLessThanOrEqual(10_000);
      expect(eventKeyCacheSize()).toBeGreaterThan(0);
      // Still the published key after the cache has churned.
      expect(computeEventKey('cal-a', 'occ-1')).toBe('Cq23Y13q76cCn83barUyYa');
    });

    it('uses interval overlap query for single calendar events and delivers eventKey as id', async () => {
      const eventRow = {
        id: 'db-uuid-1',
        calendarId: 'calendar-id',
        occurrenceKey: 'occ-key-1',
        title: 'Meeting',
        description: 'Desc',
        location: 'Room 1',
        startsAt: new Date('2026-09-01T10:00:00.000Z'),
        endsAt: new Date('2026-09-01T12:00:00.000Z'),
        allDay: false,
        status: 'confirmed',
      };

      const { service, eventFindMany } = serviceWith(row, [eventRow]);
      const from = new Date('2026-09-01T00:00:00.000Z');
      const to = new Date('2026-09-01T23:59:59.999Z');

      const result = await service.getCalendarEvents('events', from, to);

      expect(eventFindMany).toHaveBeenCalledWith({
        where: {
          calendarId: 'calendar-id',
          startsAt: { lte: to },
          endsAt: { gte: from },
        },
        select: {
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
        },
        orderBy: [{ startsAt: 'asc' }, { id: 'asc' }],
        take: 2001,
      });

      expect(result?.events).toHaveLength(1);
      const expectedKey = computeEventKey('events', 'occ-key-1');
      expect(result?.events[0]?.id).toBe(expectedKey);
      expect(result?.events[0]?.id).not.toBe('db-uuid-1');
    });

    it('uses interval overlap query for aggregated events', async () => {
      const eventRow = {
        id: 'db-uuid-1',
        calendarId: 'calendar-id',
        occurrenceKey: 'occ-key-1',
        title: 'Meeting',
        description: 'Desc',
        location: 'Room 1',
        startsAt: new Date('2026-08-31T20:00:00.000Z'),
        endsAt: new Date('2026-09-01T02:00:00.000Z'), // starts before from, ends in window
        allDay: false,
        status: 'confirmed',
      };

      const { service, eventFindMany } = serviceWith(row, [eventRow]);
      const from = new Date('2026-09-01T00:00:00.000Z');
      const to = new Date('2026-09-01T23:59:59.999Z');

      const { events, truncated } = await service.getAggregatedEvents(['events'], from, to);

      expect(eventFindMany).toHaveBeenCalledWith({
        where: {
          calendarId: { in: ['calendar-id'] },
          startsAt: { lte: to },
          endsAt: { gte: from },
        },
        select: {
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
        },
        orderBy: [{ startsAt: 'asc' }, { calendarId: 'asc' }, { id: 'asc' }],
        take: 2001,
      });

      expect(events).toHaveLength(1);
      expect(events[0]?.id).toBe(computeEventKey('events', 'occ-key-1'));
      expect(truncated).toBe(false);
    });

    it('keys every calendar of an aggregated page against its own slug', async () => {
      // The key is derived from the calendar slug AND the occurrence key, so two
      // calendars sharing an occurrence key must still produce different ids.
      // The per-response index must therefore follow the row's calendar, not
      // the first one on the page.
      const calendars = [
        { id: 'calendar-a', slug: 'cal-a' },
        { id: 'calendar-b', slug: 'cal-b' },
      ];
      const eventRows = calendars.map((calendar, index) => ({
        id: `db-uuid-${index}`,
        calendarId: calendar.id,
        occurrenceKey: 'occ-1',
        title: `Termin ${index}`,
        description: null,
        location: null,
        startsAt: new Date('2026-09-01T10:00:00.000Z'),
        endsAt: new Date('2026-09-01T12:00:00.000Z'),
        allDay: false,
        status: 'confirmed',
      }));

      const { service, calendarFindMany } = serviceWith(row, eventRows);
      calendarFindMany.mockResolvedValue(calendars);

      const { events } = await service.getAggregatedEvents(
        ['cal-a', 'cal-b'],
        new Date('2026-09-01T00:00:00.000Z'),
        new Date('2026-09-01T23:59:59.999Z'),
      );

      expect(events.map((event) => event.calendarSlug)).toEqual(['cal-a', 'cal-b']);
      expect(events.map((event) => event.id)).toEqual([
        'Cq23Y13q76cCn83barUyYa',
        'R5d1MXfJsgncnzPdj3SawE',
      ]);
    });

    it('caps the aggregated result and reports the cut instead of hiding it', async () => {
      const eventRows = Array.from({ length: 4 }, (_, i) => ({
        id: `db-uuid-${i}`,
        calendarId: 'calendar-id',
        occurrenceKey: `occ-key-${i}`,
        title: `Event ${i}`,
        description: null,
        location: null,
        startsAt: new Date(`2026-09-0${i + 1}T10:00:00.000Z`),
        endsAt: new Date(`2026-09-0${i + 1}T11:00:00.000Z`),
        allDay: false,
        status: 'confirmed',
      }));

      const { service, eventFindMany } = serviceWith(row, eventRows, {
        PUBLIC_CALENDAR_API_MAX_EVENTS: 3,
      });

      const { events, truncated } = await service.getAggregatedEvents(
        ['events'],
        new Date('2026-09-01T00:00:00.000Z'),
        new Date('2026-09-30T23:59:59.999Z'),
      );

      // One row over the ceiling is fetched purely to detect the overflow.
      expect(eventFindMany).toHaveBeenCalledWith(expect.objectContaining({ take: 4 }));
      expect(events).toHaveLength(3);
      expect(truncated).toBe(true);
    });

    it('reports truncation for a single calendar as well', async () => {
      const eventRows = Array.from({ length: 3 }, (_, i) => ({
        id: `db-uuid-${i}`,
        calendarId: 'calendar-id',
        occurrenceKey: `occ-key-${i}`,
        title: `Event ${i}`,
        description: null,
        location: null,
        startsAt: new Date(`2026-09-0${i + 1}T10:00:00.000Z`),
        endsAt: new Date(`2026-09-0${i + 1}T11:00:00.000Z`),
        allDay: false,
        status: 'confirmed',
      }));

      const { service } = serviceWith(row, eventRows, {
        PUBLIC_CALENDAR_API_MAX_EVENTS: 2,
      });

      const result = await service.getCalendarEvents(
        'events',
        new Date('2026-09-01T00:00:00.000Z'),
        new Date('2026-09-30T23:59:59.999Z'),
      );

      expect(result?.events).toHaveLength(2);
      expect(result?.truncated).toBe(true);
    });
  });

  describe('description and location flags', () => {
    // The stored rows only lose a description/location on the next FULL sync,
    // and that may be a long way off when the feed itself does not change. The
    // editor's flag is what decides publication, so the read path enforces it
    // on its own.
    const storedWithText = {
      id: 'db-uuid-1',
      calendarId: 'calendar-id',
      occurrenceKey: 'occ-key-1',
      title: 'Sitzung',
      description: 'Interne Beschreibung',
      location: 'Raum 1',
      startsAt: new Date('2026-09-01T10:00:00.000Z'),
      endsAt: new Date('2026-09-01T12:00:00.000Z'),
      allDay: false,
      status: 'confirmed',
    };
    const from = new Date('2026-09-01T00:00:00.000Z');
    const to = new Date('2026-09-01T23:59:59.999Z');

    it('withholds stored text a single calendar no longer publishes', async () => {
      const { service, calendarFindFirst } = serviceWith(
        { ...row, includeEventDescription: false, includeEventLocation: false },
        [storedWithText],
      );

      const result = await service.getCalendarEvents('events', from, to);

      expect(result?.events[0]).toMatchObject({ description: null, location: null });
      expect(calendarFindFirst.mock.calls[0]![0].select).toMatchObject({
        includeEventDescription: true,
        includeEventLocation: true,
      });
    });

    it('withholds each field on its own flag', async () => {
      const { service } = serviceWith(
        { ...row, includeEventDescription: true, includeEventLocation: false },
        [storedWithText],
      );

      const result = await service.getCalendarEvents('events', from, to);

      expect(result?.events[0]).toMatchObject({
        description: 'Interne Beschreibung',
        location: null,
      });
    });

    it('withholds stored text per calendar on an aggregated page', async () => {
      const calendars = [
        {
          id: 'calendar-a',
          slug: 'cal-a',
          includeEventDescription: true,
          includeEventLocation: true,
        },
        {
          id: 'calendar-b',
          slug: 'cal-b',
          includeEventDescription: false,
          includeEventLocation: false,
        },
      ];
      const { service, calendarFindMany } = serviceWith(row, [
        { ...storedWithText, id: 'db-uuid-a', calendarId: 'calendar-a' },
        { ...storedWithText, id: 'db-uuid-b', calendarId: 'calendar-b' },
      ]);
      calendarFindMany.mockResolvedValue(calendars);

      const { events } = await service.getAggregatedEvents(['cal-a', 'cal-b'], from, to);

      expect(
        events.map((event) => [event.calendarSlug, event.description, event.location]),
      ).toEqual([
        ['cal-a', 'Interne Beschreibung', 'Raum 1'],
        ['cal-b', null, null],
      ]);
    });
  });

  describe('startup configuration warning', () => {
    it('warns when PUBLIC_CALENDAR_LOOKAHEAD_DAYS < PUBLIC_CALENDAR_API_MAX_RANGE_DAYS', () => {
      const { service } = serviceWith(row, [], {
        PUBLIC_CALENDAR_LOOKAHEAD_DAYS: 100,
        PUBLIC_CALENDAR_API_MAX_RANGE_DAYS: 400,
      });

      const warnSpy = jest.spyOn(loggerOf(service), 'warn');
      service.onModuleInit();

      expect(warnSpy).toHaveBeenCalledTimes(1);
      expect(warnSpy.mock.calls[0]![0]).toMatchObject({
        lookaheadDays: 100,
        apiMaxRangeDays: 400,
      });
    });

    it('does not warn when LOOKAHEAD_DAYS >= API_MAX_RANGE_DAYS', () => {
      const { service } = serviceWith(row, [], {
        PUBLIC_CALENDAR_LOOKAHEAD_DAYS: 400,
        PUBLIC_CALENDAR_API_MAX_RANGE_DAYS: 400,
      });

      const warnSpy = jest.spyOn(loggerOf(service), 'warn');
      service.onModuleInit();

      expect(warnSpy).not.toHaveBeenCalled();
    });
  });
});
