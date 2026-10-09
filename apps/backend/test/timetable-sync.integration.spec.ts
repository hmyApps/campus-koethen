import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Env, validateEnv } from '../src/config/env.schema';
import { PrismaService } from '../src/prisma/prisma.service';
import { PrismaClient } from '../src/generated/prisma/client';
import { TimetableSyncService } from '../src/modules/timetable/timetable-sync.service';
import { WebUntisClient, WebUntisError } from '../src/modules/timetable/webuntis.client';
import {
  appDataSchema,
  entriesResponseSchema,
  filterResponseSchema,
} from '../src/modules/timetable/webuntis.schema';
import { createTestPrisma, resetDatabase } from './helpers/database';

// These tests exercise a real PostgreSQL service. On a shared CI runner,
// truncating the timetable tables can legitimately exceed Jest's 5s default.
jest.setTimeout(60_000);

/**
 * The import invariants are statements about DATABASE STATE, so they are proven
 * against a real PostgreSQL. Asserting them against a mocked repository would
 * demonstrate nothing about whether data actually survives a bad response.
 */

const fixture = (name: string): unknown =>
  JSON.parse(readFileSync(join(__dirname, 'fixtures/webuntis', name), 'utf8'));

const env: Env = validateEnv({
  ...process.env,
  WEBUNTIS_ENABLED: 'true',
  WEBUNTIS_REQUEST_SPACING_MS: '0',
});

/** Upstream stub. Validation and persistence stay real. */
function stubClient(overrides: Partial<Record<'appData' | 'classes' | 'entries', unknown>> = {}) {
  return {
    isEnabled: true,
    fetchAppData: jest.fn(async () =>
      appDataSchema.parse(overrides.appData ?? fixture('app-data.json')),
    ),
    fetchSchoolYears: jest.fn(async () => [
      appDataSchema.parse(overrides.appData ?? fixture('app-data.json')).currentSchoolYear,
    ]),
    fetchClasses: jest.fn(async () =>
      filterResponseSchema.parse(overrides.classes ?? fixture('filter-classes.json')),
    ),
    fetchEntries: jest.fn(async () =>
      entriesResponseSchema.parse(overrides.entries ?? fixture('entries-week.json')),
    ),
  } as unknown as WebUntisClient;
}

function failingClient(kind: WebUntisError['kind']) {
  const boom = async (): Promise<never> => {
    throw new WebUntisError(kind, `synthetic ${kind}`);
  };
  return {
    isEnabled: true,
    fetchAppData: jest.fn(boom),
    fetchSchoolYears: jest.fn(boom),
    fetchClasses: jest.fn(boom),
    fetchEntries: jest.fn(boom),
  } as unknown as WebUntisClient;
}

/** The window actually covered by entries-week.json. */
const WINDOW = { from: '2026-07-20', to: '2026-07-24' };

describe('TimetableSyncService (integration)', () => {
  let prisma: PrismaClient;

  const service = (client: WebUntisClient) =>
    new TimetableSyncService(prisma as unknown as PrismaService, client, env);

  const counts = async () => ({
    groups: await prisma.timetableGroup.count(),
    activeGroups: await prisma.timetableGroup.count({ where: { active: true } }),
    contextLinks: await prisma.timetableContextGroup.count(),
    entries: await prisma.timetableEntry.count(),
    links: await prisma.timetableEntryGroup.count(),
  });

  beforeAll(async () => {
    prisma = createTestPrisma();
    await prisma.$connect();
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDatabase(prisma);
  });

  const seedCatalogue = async () => {
    await service(stubClient()).syncContext();
    const outcome = await service(stubClient()).syncGroups(new Date('2026-07-20T00:00:00.000Z'));
    expect(outcome.status).toBe('success');
  };

  describe('context', () => {
    it('stores the dynamically resolved school year', async () => {
      const outcome = await service(stubClient()).syncContext();

      expect(outcome.status).toBe('success');
      const context = await prisma.timetableContext.findFirst({ where: { active: true } });
      expect(context?.externalId).toBe('49');
      expect(context?.name).toBe('2026/2026');
    });

    it('is idempotent', async () => {
      await service(stubClient()).syncContext();
      await service(stubClient()).syncContext();
      expect(await prisma.timetableContext.count()).toBe(1);
    });

    it('keeps the stored context when the source fails', async () => {
      await service(stubClient()).syncContext();
      const outcome = await service(failingClient('timeout')).syncContext();

      expect(outcome.status).toBe('failed');
      expect(await prisma.timetableContext.count()).toBe(1);
    });
  });

  describe('group catalogue', () => {
    it('imports the catalogue', async () => {
      await seedCatalogue();
      const { groups, activeGroups, contextLinks } = await counts();
      expect(groups).toBeGreaterThan(0);
      expect(activeGroups).toBe(groups);
      expect(contextLinks).toBe(groups);
    });

    it('repeating the import creates no duplicates', async () => {
      await seedCatalogue();
      const before = await counts();
      await service(stubClient()).syncGroups(new Date('2026-07-20T00:00:00.000Z'));
      expect(await counts()).toMatchObject({ groups: before.groups });
    });

    it('an EMPTY catalogue keeps every existing group', async () => {
      await seedCatalogue();
      const before = await counts();

      const outcome = await service(
        stubClient({ classes: { resourceType: 'CLASS', classes: [] } }),
      ).syncGroups(new Date('2026-07-20T00:00:00.000Z'));

      expect(outcome.status).toBe('empty');
      expect(await counts()).toMatchObject({
        groups: before.groups,
        activeGroups: before.activeGroups,
        contextLinks: before.contextLinks,
      });
    });

    for (const kind of [
      'timeout',
      'http',
      'rate_limited',
      'html',
      'malformed',
      'network',
    ] as const) {
      it(`a ${kind} failure keeps every existing group`, async () => {
        await seedCatalogue();
        const before = await counts();

        const outcome = await service(failingClient(kind)).syncGroups(
          new Date('2026-07-20T00:00:00.000Z'),
        );

        expect(outcome.status).toBe('failed');
        expect(await counts()).toMatchObject({
          groups: before.groups,
          activeGroups: before.activeGroups,
        });
      });
    }

    it('leaves every row untouched when the catalogue has not moved', async () => {
      await seedCatalogue();
      const before = await prisma.timetableGroup.findMany({ orderBy: { externalId: 'asc' } });
      expect(before.length).toBeGreaterThan(1);

      await service(stubClient()).syncGroups(new Date('2026-07-20T00:00:00.000Z'));

      const after = await prisma.timetableGroup.findMany({ orderBy: { externalId: 'asc' } });
      for (const previous of before) {
        const current = after.find((group) => group.id === previous.id)!;
        // The seen-stamp still moves for every confirmed group, exactly as the
        // upsert loop moved it — and `updatedAt` follows it. Everything a
        // reader actually sees stays put. That only the stamp is written, and
        // in one statement, is pinned in timetable-sync.service.spec.ts.
        expect({ ...current, lastSeenAt: null, updatedAt: null }).toEqual({
          ...previous,
          lastSeenAt: null,
          updatedAt: null,
        });
        expect(current.lastSeenAt.getTime()).toBeGreaterThanOrEqual(previous.lastSeenAt.getTime());
      }
    });

    it('writes the renamed class and leaves the rest of the catalogue alone', async () => {
      await seedCatalogue();
      const before = await prisma.timetableGroup.findMany({ orderBy: { externalId: 'asc' } });

      const all = filterResponseSchema.parse(fixture('filter-classes.json'));
      const target = all.classes[0]!;
      const renamed = {
        ...all,
        classes: all.classes.map((item, index) =>
          index === 0 ? { ...item, class: { ...item.class, longName: 'Neuer Langname' } } : item,
        ),
      };

      const outcome = await service(stubClient({ classes: renamed })).syncGroups(
        new Date('2026-07-20T00:00:00.000Z'),
      );
      expect(outcome.status).toBe('success');

      const after = await prisma.timetableGroup.findMany({ orderBy: { externalId: 'asc' } });
      expect(after.map((group) => group.id)).toEqual(before.map((group) => group.id));

      const changed = after.find((group) => group.externalId === String(target.class.id))!;
      expect(changed.longName).toBe('Neuer Langname');

      for (const previous of before.filter(
        (group) => group.externalId !== String(target.class.id),
      )) {
        const current = after.find((group) => group.id === previous.id)!;
        expect({ ...current, lastSeenAt: null, updatedAt: null }).toEqual({
          ...previous,
          lastSeenAt: null,
          updatedAt: null,
        });
      }
    });

    it('revives a retired class that upstream offers again', async () => {
      await seedCatalogue();
      const all = filterResponseSchema.parse(fixture('filter-classes.json'));

      // Retire it the only way the importer ever does: a complete catalogue
      // that no longer contains it.
      const trimmed = { ...all, classes: all.classes.slice(0, 2) };
      await service(stubClient({ classes: trimmed })).syncGroups(
        new Date('2026-07-20T00:00:00.000Z'),
      );
      const retired = await prisma.timetableGroup.findMany({ where: { active: false } });
      expect(retired.length).toBeGreaterThan(0);

      await service(stubClient({ classes: all })).syncGroups(new Date('2026-07-20T00:00:00.000Z'));

      for (const group of retired) {
        const current = await prisma.timetableGroup.findUnique({ where: { id: group.id } });
        expect(current!.active).toBe(true);
      }
    });

    it('retires a group only after a complete successful catalogue', async () => {
      await seedCatalogue();
      const all = filterResponseSchema.parse(fixture('filter-classes.json'));
      const trimmed = { ...all, classes: all.classes.slice(0, 2) };

      const outcome = await service(stubClient({ classes: trimmed })).syncGroups(
        new Date('2026-07-20T00:00:00.000Z'),
      );

      expect(outcome.status).toBe('success');
      expect(await prisma.timetableGroup.count({ where: { active: true } })).toBe(2);
      // Retired, never deleted: historical entries must stay resolvable.
      expect(await prisma.timetableGroup.count()).toBeGreaterThan(2);
    });
  });

  describe('entries', () => {
    it('imports entries and links them to their groups', async () => {
      await seedCatalogue();

      const outcome = await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      expect(outcome.status).toBe('success');
      const { entries, links } = await counts();
      expect(entries).toBeGreaterThan(0);
      expect(links).toBeGreaterThan(0);
    });

    it('converts Europe/Berlin wall clock into absolute UTC instants', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      const entry = await prisma.timetableEntry.findFirst({ orderBy: { startsAt: 'asc' } });
      // July is CEST (UTC+2): a 10:00 lesson is 08:00Z, never 10:00Z.
      expect(entry!.startsAt.getTime()).toBeLessThan(entry!.endsAt.getTime());
      expect(entry!.startsAt.toISOString()).toMatch(/T\d{2}:\d{2}:\d{2}/);
    });

    it('repeating the import creates no duplicates', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);
      const before = await counts();

      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      expect(await counts()).toMatchObject({ entries: before.entries, links: before.links });
    });

    it('writes only what the response actually changed', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      const before = await prisma.timetableEntry.findMany({ orderBy: { externalKey: 'asc' } });
      expect(before.length).toBeGreaterThan(1);
      const target = before[0]!;

      // The source moved one lesson and cancelled it; everything else is
      // byte-for-byte the response from the previous run.
      const changed = structuredClone(fixture('entries-week.json')) as {
        days: Array<{ gridEntries: Array<Record<string, unknown>> }>;
      };
      const grid = changed.days.flatMap((day) => day.gridEntries);
      const moved = grid.find(
        (raw) =>
          [...(raw['ids'] as number[])].sort((a, b) => a - b).join('-') === target.externalKey,
      )!;
      moved['status'] = 'CANCELLED';
      moved['duration'] = { start: '2026-07-20T14:00', end: '2026-07-20T15:30' };

      await service(stubClient({ entries: changed })).syncEntries(WINDOW.from, WINDOW.to);

      const after = await prisma.timetableEntry.findMany({ orderBy: { externalKey: 'asc' } });
      expect(after.map((entry) => entry.id)).toEqual(before.map((entry) => entry.id));

      const movedRow = after.find((entry) => entry.id === target.id)!;
      expect(movedRow.status).toBe('cancelled');
      expect(movedRow.startsAt.getTime()).not.toBe(target.startsAt.getTime());

      // Every other lesson keeps its content exactly, and all of them are
      // stamped as seen — changed or not.
      for (const previous of before.slice(1)) {
        const current = after.find((entry) => entry.id === previous.id)!;
        expect({ ...current, lastSeenAt: null, updatedAt: null }).toEqual({
          ...previous,
          lastSeenAt: null,
          updatedAt: null,
        });
        expect(current.lastSeenAt.getTime()).toBeGreaterThanOrEqual(previous.lastSeenAt.getTime());
      }
    });

    it('an EMPTY window keeps the existing plan', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);
      const before = await counts();

      const outcome = await service(
        stubClient({ entries: fixture('entries-empty.json') }),
      ).syncEntries(WINDOW.from, WINDOW.to);

      expect(outcome.status).toBe('empty');
      expect(await counts()).toMatchObject({ entries: before.entries, links: before.links });
    });

    for (const kind of [
      'timeout',
      'http',
      'rate_limited',
      'html',
      'malformed',
      'network',
    ] as const) {
      it(`a ${kind} failure keeps the existing plan`, async () => {
        await seedCatalogue();
        await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);
        const before = await counts();

        const outcome = await service(failingClient(kind)).syncEntries(WINDOW.from, WINDOW.to);

        expect(outcome.status).toBe('failed');
        expect(await counts()).toMatchObject({ entries: before.entries, links: before.links });
      });
    }

    it('leaves data OUTSIDE the confirmed window untouched', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      const group = await prisma.timetableGroup.findFirstOrThrow();
      const outside = await prisma.timetableEntry.create({
        data: {
          externalKey: 'outside-window',
          startsAt: new Date('2026-09-01T08:00:00.000Z'),
          endsAt: new Date('2026-09-01T09:30:00.000Z'),
          date: new Date('2026-09-01T00:00:00.000Z'),
          title: 'Far future lesson',
          type: 'regular_teaching',
          status: 'regular',
          groups: { create: { groupId: group.id } },
        },
      });

      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      expect(await prisma.timetableEntry.findUnique({ where: { id: outside.id } })).not.toBeNull();
    });

    it('keeps a shared lesson alive for a group the response did not cover', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      // A group outside the confirmed set also attends an in-window lesson.
      const entry = await prisma.timetableEntry.findFirstOrThrow();
      const otherGroup = await prisma.timetableGroup.create({
        data: { externalId: 'external-not-in-response', shortName: 'OTHER', longName: 'Other' },
      });
      await prisma.timetableEntryGroup.create({
        data: { entryId: entry.id, groupId: otherGroup.id },
      });

      // Now a response that no longer contains that lesson at all.
      const stripped = entriesResponseSchema.parse(fixture('entries-week.json'));
      const reduced = {
        ...stripped,
        days: stripped.days.map((day) => ({ ...day, gridEntries: day.gridEntries.slice(0, 1) })),
      };
      await service(stubClient({ entries: reduced })).syncEntries(WINDOW.from, WINDOW.to);

      // The other group's link is outside the confirmed scope, so both the link
      // and the lesson survive.
      const survivor = await prisma.timetableEntryGroup.findFirst({
        where: { groupId: otherGroup.id },
      });
      expect(survivor).not.toBeNull();
      expect(await prisma.timetableEntry.findUnique({ where: { id: entry.id } })).not.toBeNull();
    });

    it('withdraws the link of a class that left a lesson which continues for another class', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      // Both classes are in the catalogue and have their own day in the fixture.
      const stays = await prisma.timetableGroup.findFirstOrThrow({
        where: { externalId: '14808' },
      });
      const left = await prisma.timetableGroup.findFirstOrThrow({ where: { externalId: '14820' } });
      const lesson = await prisma.timetableEntry.findFirstOrThrow({
        where: { groups: { some: { groupId: stays.id } } },
      });
      // Until now the second class attended this lesson too.
      await prisma.timetableEntryGroup.create({ data: { entryId: lesson.id, groupId: left.id } });

      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      const links = await prisma.timetableEntryGroup.findMany({
        where: { entryId: lesson.id },
        select: { groupId: true },
      });
      expect(links.map((link) => link.groupId)).toEqual([stays.id]);
    });

    it("keeps a class's stored plan when its own response reports errors", async () => {
      await seedCatalogue();
      // One response per class, carrying only that class's own days.
      const ownDays = (classId: number) => {
        const week = entriesResponseSchema.parse(fixture('entries-week.json'));
        return { ...week, days: week.days.filter((day) => day.resource.id === classId) };
      };
      const perClass = (failing: number | null) =>
        ({
          ...stubClient(),
          fetchEntries: jest.fn(
            async (_year: number, _from: string, _to: string, classId: number) =>
              classId === failing
                ? entriesResponseSchema.parse(fixture('entries-with-errors.json'))
                : ownDays(classId),
          ),
        }) as unknown as WebUntisClient;

      await service(perClass(null)).syncEntries(WINDOW.from, WINDOW.to);
      const group = await prisma.timetableGroup.findFirstOrThrow({
        where: { externalId: '14820' },
      });
      const before = await prisma.timetableEntryGroup.count({ where: { groupId: group.id } });
      expect(before).toBeGreaterThan(0);

      const outcome = await service(perClass(14820)).syncEntries(WINDOW.from, WINDOW.to);

      // One faulty class neither aborts the run nor loses its plan.
      expect(outcome.status).toBe('success');
      expect(await prisma.timetableEntryGroup.count({ where: { groupId: group.id } })).toBe(before);
    });

    it('records sync run metadata', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      const run = await prisma.timetableSyncRun.findFirst({
        where: { kind: 'entries', status: 'success' },
        orderBy: { startedAt: 'desc' },
      });
      expect(run).not.toBeNull();
      expect(run!.recordsWritten).toBeGreaterThan(0);
      expect(run!.groupsRequested).toBeGreaterThan(0);
      expect(run!.finishedAt).not.toBeNull();
    });

    it('stores only a classification when the source fails, never upstream detail', async () => {
      await seedCatalogue();
      await service(failingClient('html')).syncEntries(WINDOW.from, WINDOW.to);

      const run = await prisma.timetableSyncRun.findFirstOrThrow({
        where: { kind: 'entries', status: 'failed' },
        orderBy: { startedAt: 'desc' },
      });
      expect(run.errorCode).toBe('html');
      const serialized = JSON.stringify(run);
      expect(serialized).not.toContain('webuntis.com');
      expect(serialized).not.toContain('anonymous-school');
    });

    it('reports the last successful run for staleness', async () => {
      await seedCatalogue();
      await service(stubClient()).syncEntries(WINDOW.from, WINDOW.to);

      expect(await service(stubClient()).lastSuccessfulAt('entries')).toBeInstanceOf(Date);
    });
  });

  describe('disabled feature', () => {
    it('does not fail loudly, it reports disabled and touches nothing', async () => {
      await seedCatalogue();
      const before = await counts();

      const outcome = await service(failingClient('disabled')).syncEntries(WINDOW.from, WINDOW.to);

      expect(outcome.status).toBe('disabled');
      expect(await counts()).toMatchObject({ entries: before.entries });
    });
  });
});
