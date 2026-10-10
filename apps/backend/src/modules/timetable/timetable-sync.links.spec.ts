import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { TimetableSyncService } from './timetable-sync.service';
import { WebUntisClient } from './webuntis.client';
import { EntriesResponse, entriesResponseSchema } from './webuntis.schema';

/**
 * Which group links an entry sync keeps, adds and withdraws.
 *
 * These are statements about the resulting STATE, so they run against a small
 * in-memory stand-in for exactly the Prisma calls the entry sync makes. Any
 * other query shape throws, so a change in how the service talks to the
 * database cannot silently turn these tests into no-ops. The same invariants
 * against PostgreSQL live in test/timetable-sync.integration.spec.ts.
 */

const RANGE = { from: '2026-07-20', to: '2026-07-24' };

const fixture = (name: string): unknown =>
  JSON.parse(readFileSync(join(__dirname, '../../../test/fixtures/webuntis', name), 'utf8'));

interface StoredEntry {
  id: string;
  source: string;
  externalKey: string;
  startsAt: Date;
  endsAt: Date;
  date: Date;
  title: string;
  subjectCode: string | null;
  type: string;
  status: string;
  sourceStatus: string | null;
  teachers: unknown;
  rooms: unknown;
  note: string | null;
  lessonInfo: string | null;
  lastSeenAt: Date;
}

interface StoredLink {
  entryId: string;
  groupId: string;
}

interface StoredGroup {
  id: string;
  source: string;
  externalId: string;
  active: boolean;
}

type Where = Record<string, unknown>;

function unsupported(what: string): never {
  throw new Error(`in-memory timetable store: unsupported ${what}`);
}

function matchesValue(value: unknown, condition: unknown): boolean {
  if (condition instanceof Date) {
    return value instanceof Date && value.getTime() === condition.getTime();
  }
  if (condition === null || typeof condition !== 'object') {
    return value === condition;
  }
  return Object.entries(condition as Record<string, unknown>).every(([operator, operand]) => {
    switch (operator) {
      case 'in':
        return (operand as unknown[]).includes(value);
      case 'notIn':
        return !(operand as unknown[]).includes(value);
      case 'not':
        return !matchesValue(value, operand);
      case 'gte':
        return (value as Date).getTime() >= (operand as Date).getTime();
      case 'lte':
        return (value as Date).getTime() <= (operand as Date).getTime();
      default:
        return unsupported(`operator ${operator}`);
    }
  });
}

function createStore(groups: StoredGroup[]) {
  const entries = new Map<string, StoredEntry>();
  let links: StoredLink[] = [];
  let created = 0;

  const matchesEntry = (entry: StoredEntry, where: Where): boolean =>
    Object.entries(where).every(([key, condition]) => {
      switch (key) {
        case 'id':
        case 'source':
        case 'externalKey':
        case 'date':
          return matchesValue(entry[key], condition);
        case 'groups': {
          const relation = condition as { none?: Where };
          if (relation.none && Object.keys(relation.none).length === 0) {
            return !links.some((link) => link.entryId === entry.id);
          }
          return unsupported('groups relation filter');
        }
        default:
          return unsupported(`entry filter ${key}`);
      }
    });

  const matchesLink = (link: StoredLink, where: Where): boolean =>
    Object.entries(where).every(([key, condition]) => {
      switch (key) {
        case 'entryId':
        case 'groupId':
          return matchesValue(link[key], condition);
        case 'entry':
          return matchesEntry(entries.get(link.entryId)!, condition as Where);
        case 'OR':
          return (condition as Where[]).some((branch) => matchesLink(link, branch));
        default:
          return unsupported(`link filter ${key}`);
      }
    });

  const matchesGroup = (group: StoredGroup, where: Where): boolean =>
    Object.entries(where).every(([key, condition]) => {
      switch (key) {
        case 'source':
        case 'externalId':
        case 'active':
          return matchesValue(group[key], condition);
        default:
          return unsupported(`group filter ${key}`);
      }
    });

  const db = {
    timetableEntry: {
      findMany: jest.fn(async ({ where }: { where: Where }) =>
        [...entries.values()].filter((entry) => matchesEntry(entry, where)).map((e) => ({ ...e })),
      ),
      createManyAndReturn: jest.fn(
        async ({ data }: { data: Array<Omit<StoredEntry, 'id' | 'source' | 'lastSeenAt'>> }) =>
          data.map((row) => {
            created += 1;
            const entry: StoredEntry = {
              ...row,
              id: `created-${created}`,
              source: 'webuntis',
              lastSeenAt: new Date(),
            };
            entries.set(entry.id, entry);
            return { id: entry.id, externalKey: entry.externalKey };
          }),
      ),
      update: jest.fn(
        async ({
          where,
          data,
        }: {
          where: { source_externalKey: { source: string; externalKey: string } };
          data: Partial<StoredEntry>;
        }) => {
          const { source, externalKey } = where.source_externalKey;
          const entry = [...entries.values()].find(
            (row) => row.source === source && row.externalKey === externalKey,
          );
          if (!entry) throw new Error('record to update not found');
          Object.assign(entry, data);
          return { ...entry };
        },
      ),
      updateMany: jest.fn(async ({ where, data }: { where: Where; data: Partial<StoredEntry> }) => {
        const matched = [...entries.values()].filter((entry) => matchesEntry(entry, where));
        for (const entry of matched) Object.assign(entry, data);
        return { count: matched.length };
      }),
      deleteMany: jest.fn(async ({ where }: { where: Where }) => {
        const doomed = [...entries.values()].filter((entry) => matchesEntry(entry, where));
        for (const entry of doomed) entries.delete(entry.id);
        // ON DELETE CASCADE.
        links = links.filter((link) => entries.has(link.entryId));
        return { count: doomed.length };
      }),
    },
    timetableEntryGroup: {
      findMany: jest.fn(async ({ where }: { where: Where }) =>
        links
          .filter((link) => matchesLink(link, where))
          .map((link) => {
            const entry = entries.get(link.entryId)!;
            return { ...link, entry: { externalKey: entry.externalKey, date: entry.date } };
          }),
      ),
      createMany: jest.fn(async ({ data }: { data: StoredLink[]; skipDuplicates?: boolean }) => {
        let count = 0;
        for (const link of data) {
          if (links.some((row) => row.entryId === link.entryId && row.groupId === link.groupId)) {
            continue;
          }
          links.push({ ...link });
          count += 1;
        }
        return { count };
      }),
      deleteMany: jest.fn(async ({ where }: { where: Where }) => {
        const before = links.length;
        links = links.filter((link) => !matchesLink(link, where));
        return { count: before - links.length };
      }),
    },
  };

  const runUpdate = jest.fn();
  const prisma = {
    ...db,
    timetableSyncRun: {
      create: jest.fn().mockResolvedValue({ id: 'run-1' }),
      update: runUpdate,
    },
    timetableContext: {
      findMany: jest.fn().mockResolvedValue([
        {
          id: 'context-49',
          externalId: '49',
          validFrom: new Date('2026-04-07T00:00:00.000Z'),
          validTo: new Date('2026-09-30T00:00:00.000Z'),
        },
      ]),
    },
    timetableGroup: {
      // Catalogue rows carry no public names here, so the derived alias
      // reconciliation after the write phase has nothing to decide.
      findMany: jest.fn(async ({ where }: { where: Where }) =>
        groups.filter((group) => matchesGroup(group, where)).map((group) => ({ ...group })),
      ),
      updateMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    $transaction: jest.fn(async (operation: (transaction: typeof db) => Promise<unknown>) =>
      operation(db),
    ),
  };

  return {
    prisma: prisma as unknown as PrismaService,
    runUpdate,
    seed(externalKey: string, groupIds: string[], overrides: Partial<StoredEntry> = {}) {
      const entry: StoredEntry = {
        id: `stored-${externalKey}`,
        source: 'webuntis',
        externalKey,
        startsAt: new Date(`${RANGE.from}T08:00:00.000Z`),
        endsAt: new Date(`${RANGE.from}T09:30:00.000Z`),
        date: new Date(`${RANGE.from}T00:00:00.000Z`),
        title: `Fach ${externalKey}`,
        subjectCode: `S${externalKey}`,
        type: 'regular_teaching',
        status: 'regular',
        sourceStatus: 'REGULAR',
        teachers: [],
        rooms: [],
        note: null,
        lessonInfo: null,
        lastSeenAt: new Date(0),
        ...overrides,
      };
      entries.set(entry.id, entry);
      for (const groupId of groupIds) links.push({ entryId: entry.id, groupId });
    },
    entry(externalKey: string): StoredEntry | undefined {
      return [...entries.values()].find((entry) => entry.externalKey === externalKey);
    },
    groupsOf(externalKey: string): string[] {
      const entry = [...entries.values()].find((row) => row.externalKey === externalKey);
      if (!entry) return [];
      return links
        .filter((link) => link.entryId === entry.id)
        .map((link) => link.groupId)
        .sort();
    },
  };
}

/** One lesson as the source delivers it, attended by whichever class's day it sits in. */
function lesson(id: number, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    ids: [id],
    duration: { start: `${RANGE.from}T10:00`, end: `${RANGE.from}T11:30` },
    type: 'NORMAL_TEACHING_PERIOD',
    status: 'REGULAR',
    statusDetail: null,
    name: null,
    notesAll: '',
    lessonText: null,
    substitutionText: null,
    position1: null,
    position2: [
      {
        current: {
          type: 'SUBJECT',
          status: 'REGULAR',
          shortName: `S${id}`,
          longName: `Fach ${id}`,
          displayName: null,
        },
        removed: null,
      },
    ],
    position3: null,
    position4: null,
    position5: null,
    position6: null,
    position7: null,
    ...overrides,
  };
}

function day(classId: number, lessons: Array<Record<string, unknown>>): Record<string, unknown> {
  return {
    date: RANGE.from,
    resourceType: 'CLASS',
    resource: {
      id: classId,
      shortName: `DEMO${classId}`,
      longName: `Demo class ${classId}`,
      displayName: '',
    },
    status: lessons.length > 0 ? 'REGULAR' : 'NO_DATA',
    dayEntries: [],
    gridEntries: lessons,
  };
}

/** Parsed exactly like the real client does, so the service sees validated input. */
function response(days: Array<Record<string, unknown>>, errors: unknown[] = []): EntriesResponse {
  return entriesResponseSchema.parse({ format: 2, days, errors });
}

const CLASS_A = 15027;
const CLASS_B = 15028;
const GROUPS: StoredGroup[] = [
  { id: 'group-a', source: 'webuntis', externalId: String(CLASS_A), active: true },
  { id: 'group-b', source: 'webuntis', externalId: String(CLASS_B), active: true },
];

function harness(responses: Record<number, EntriesResponse>) {
  const store = createStore(GROUPS);
  const client = {
    fetchClasses: jest.fn(async () => ({
      resourceType: 'CLASS',
      classes: [CLASS_A, CLASS_B].map((id) => ({
        class: { id, shortName: `DEMO${id}` },
        department: null,
      })),
    })),
    fetchEntries: jest.fn(
      async (_yearId: number, _from: string, _to: string, classId: number) =>
        responses[classId] ?? response([day(classId, [])]),
    ),
  } as unknown as WebUntisClient;
  const service = new TimetableSyncService(store.prisma, client, {
    WEBUNTIS_LOOKBACK_DAYS: 7,
    WEBUNTIS_LOOKAHEAD_DAYS: 28,
  } as Env);
  return { store, service };
}

describe('TimetableSyncService group links', () => {
  describe('a class that leaves a lesson (A-01)', () => {
    it('withdraws only that class while the lesson continues for another class', async () => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001)])]),
        [CLASS_B]: response([day(CLASS_B, [lesson(7002)])]),
      });
      store.seed('7001', ['group-a', 'group-b']);

      const outcome = await service.syncEntries(RANGE.from, RANGE.to);

      expect(outcome.status).toBe('success');
      expect(store.groupsOf('7001')).toEqual(['group-a']);
      expect(store.groupsOf('7002')).toEqual(['group-b']);
      expect(outcome.removed).toBe(1);
    });

    it('still withdraws and removes a lesson that vanished from every class', async () => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001)])]),
        [CLASS_B]: response([day(CLASS_B, [lesson(7002)])]),
      });
      store.seed('7009', ['group-a', 'group-b']);

      await service.syncEntries(RANGE.from, RANGE.to);

      expect(store.entry('7009')).toBeUndefined();
    });

    it('keeps an unchanged plan exactly as it is', async () => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001)])]),
        [CLASS_B]: response([day(CLASS_B, [lesson(7001)])]),
      });
      store.seed('7001', ['group-a', 'group-b']);

      const outcome = await service.syncEntries(RANGE.from, RANGE.to);

      expect(store.groupsOf('7001')).toEqual(['group-a', 'group-b']);
      expect(outcome.removed).toBe(0);
    });
  });

  describe('a class whose response is not a confirmation (A-02)', () => {
    it('keeps the stored plan of a class whose response reports errors', async () => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001)])]),
        [CLASS_B]: entriesResponseSchema.parse(fixture('entries-with-errors.json')),
      });
      store.seed('7001', ['group-a', 'group-b']);
      store.seed('8001', ['group-b']);

      const outcome = await service.syncEntries(RANGE.from, RANGE.to);

      // One class's error must not abort the run for every other class.
      expect(outcome.status).toBe('success');
      expect(store.groupsOf('8001')).toEqual(['group-b']);
      expect(store.groupsOf('7001')).toEqual(['group-a', 'group-b']);
    });

    it('does not import lessons from a response that reports errors', async () => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001)])]),
        [CLASS_B]: response(
          [day(CLASS_B, [lesson(8002)])],
          [{ code: 'SOME_UPSTREAM_ERROR', message: 'synthetic upstream error for tests' }],
        ),
      });

      await service.syncEntries(RANGE.from, RANGE.to);

      expect(store.entry('8002')).toBeUndefined();
      expect(store.groupsOf('7001')).toEqual(['group-a']);
    });

    it('keeps the stored plan of a class whose clean response carried no day for it', async () => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001)])]),
        [CLASS_B]: response([]),
      });
      store.seed('8001', ['group-b']);

      const outcome = await service.syncEntries(RANGE.from, RANGE.to);

      expect(outcome.status).toBe('success');
      expect(store.groupsOf('8001')).toEqual(['group-b']);
    });

    it('records how many classes stayed unconfirmed on an otherwise successful run', async () => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001)])]),
        [CLASS_B]: entriesResponseSchema.parse(fixture('entries-with-errors.json')),
      });

      await service.syncEntries(RANGE.from, RANGE.to);

      expect(store.runUpdate).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            status: 'success',
            // A queryable counter for monitoring, not only free text.
            groupsUnconfirmed: 1,
            errorMessage: expect.stringContaining('1 class'),
          }),
        }),
      );
    });

    it('records zero unconfirmed classes when every class confirmed its plan', async () => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001)])]),
        [CLASS_B]: response([day(CLASS_B, [lesson(8001)])]),
      });

      await service.syncEntries(RANGE.from, RANGE.to);

      expect(store.runUpdate).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'success', groupsUnconfirmed: 0 }),
        }),
      );
    });
  });

  describe('a lesson the current response cannot read (A-03)', () => {
    it.each([
      ['has no usable title', { name: null, position2: null }],
      ['has an unreadable time', { duration: { start: 'not-a-time', end: 'not-a-time' } }],
    ])('keeps its last valid version when it %s', async (_label, broken) => {
      const { store, service } = harness({
        [CLASS_A]: response([day(CLASS_A, [lesson(7001, broken), lesson(7002)])]),
        [CLASS_B]: response([day(CLASS_B, [lesson(7003)])]),
      });
      store.seed('7001', ['group-a', 'group-b']);

      const outcome = await service.syncEntries(RANGE.from, RANGE.to);

      expect(outcome.status).toBe('success');
      expect(outcome.rejected).toBe(1);
      // Class A still lists the lesson, just unreadably: its last valid
      // version and its link stay. Class B's clean response no longer lists
      // it at all, so that link is withdrawn as usual.
      expect(store.entry('7001')?.title).toBe('Fach 7001');
      expect(store.groupsOf('7001')).toEqual(['group-a']);
    });
  });
});
