import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { TimetableSyncService } from './timetable-sync.service';
import { EntriesResponse } from './webuntis.schema';
import { WebUntisClient } from './webuntis.client';

describe('TimetableSyncService school-year catalogue', () => {
  it('stores the upcoming year before it becomes current', async () => {
    const upsert = jest.fn();
    const prisma = {
      timetableSyncRun: {
        create: jest.fn().mockResolvedValue({ id: 'run-1' }),
        update: jest.fn(),
      },
      timetableContext: {
        upsert,
        updateMany: jest.fn(),
      },
    } as unknown as PrismaService;
    const current = {
      id: 49,
      name: '2026/2026',
      dateRange: { start: '2026-04-07', end: '2026-09-30' },
    };
    const upcoming = {
      id: 51,
      name: '2026/2027',
      dateRange: { start: '2026-10-05', end: '2027-03-31' },
    };
    const client = {
      fetchAppData: jest.fn().mockResolvedValue({ currentSchoolYear: current }),
      fetchSchoolYears: jest.fn().mockResolvedValue([current, upcoming]),
    } as unknown as WebUntisClient;

    const outcome = await new TimetableSyncService(prisma, client, {} as Env).syncContext();

    expect(outcome.status).toBe('success');
    expect(upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { source_externalId: { source: 'webuntis', externalId: '51' } },
        create: expect.objectContaining({ active: false }),
      }),
    );
  });
});

describe('TimetableSyncService catalogue duplicate reconciliation', () => {
  it('publishes only the data-backed alias and writes only changed visibility', async () => {
    const updateMany = jest.fn().mockResolvedValue({ count: 1 });
    const groups = [
      {
        id: 'empty',
        shortName: 'MER2',
        longName: '2.Sem.Ernährungstherapie Master',
        department: 'FB1',
        catalogVisible: true,
      },
      {
        id: 'working',
        shortName: 'MER2',
        longName: '2.Sem.Ernährungstherapie Master',
        department: 'FB1',
        catalogVisible: false,
      },
      {
        id: 'other-public-metadata',
        shortName: 'MER2',
        longName: '2.Sem.Ernährungstherapie dual',
        department: 'FB1',
        catalogVisible: true,
      },
    ];
    const prisma = {
      timetableGroup: { findMany: jest.fn().mockResolvedValue(groups), updateMany },
      timetableEntryGroup: {
        findMany: jest.fn().mockResolvedValue([
          { groupId: 'working', entryId: 'lesson-1' },
          { groupId: 'working', entryId: 'lesson-2' },
        ]),
      },
    };
    const service = new TimetableSyncService(
      prisma as unknown as PrismaService,
      {} as WebUntisClient,
      {} as Env,
    );

    await service.reconcileGroupCatalogue(
      new Date('2026-10-01T00:00:00.000Z'),
      new Date('2027-04-01T00:00:00.000Z'),
    );

    expect(prisma.timetableEntryGroup.findMany).toHaveBeenCalledWith({
      where: {
        groupId: { in: ['empty', 'working'] },
        entry: {
          date: {
            gte: new Date('2026-10-01T00:00:00.000Z'),
            lte: new Date('2027-04-01T00:00:00.000Z'),
          },
        },
      },
      select: { groupId: true, entryId: true },
    });
    expect(updateMany).toHaveBeenCalledTimes(2);
    expect(updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['working'] } },
      data: { catalogVisible: true },
    });
    expect(updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['empty'] } },
      data: { catalogVisible: false },
    });
  });
});

/**
 * Cost contract of the entry write phase.
 *
 * The job covers the whole catalogue on each scheduled run — ~800 lessons on real data —
 * and between two runs a handful of them move at most. Writing every lesson
 * back unconditionally is what forced the transaction timeout up from Prisma's
 * 5s default, so the number of writes has to follow the number of CHANGES.
 * What is actually written is proven against a real database in
 * test/timetable-sync.integration.spec.ts.
 */
describe('TimetableSyncService entry write phase', () => {
  const RANGE = { from: '2026-07-20', to: '2026-07-24' };

  /** One lesson per id, all attending the same class. */
  function response(ids: number[], startHour = 10): EntriesResponse {
    return {
      format: 2,
      days: [
        {
          date: RANGE.from,
          resourceType: 'CLASS',
          resource: { id: 15027, shortName: 'AR2Ü1', longName: '2. AR Gr. 1', displayName: '' },
          status: 'REGULAR',
          dayEntries: [],
          gridEntries: ids.map((id) => ({
            ids: [id],
            duration: {
              start: `${RANGE.from}T${String(startHour).padStart(2, '0')}:00`,
              end: `${RANGE.from}T${String(startHour + 1).padStart(2, '0')}:30`,
            },
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
          })),
        },
      ],
      errors: [],
    };
  }

  /** A stored row that matches what `response()` would produce for `id`. */
  function storedRow(id: number, startHour = 10) {
    return {
      id: `row-${id}`,
      externalKey: String(id),
      startsAt: new Date(`${RANGE.from}T${String(startHour - 2).padStart(2, '0')}:00:00.000Z`),
      endsAt: new Date(`${RANGE.from}T${String(startHour - 1).padStart(2, '0')}:30:00.000Z`),
      date: new Date(`${RANGE.from}T00:00:00.000Z`),
      title: `Fach ${id}`,
      subjectCode: `S${id}`,
      type: 'regular_teaching',
      status: 'regular',
      sourceStatus: 'REGULAR',
      teachers: [],
      rooms: [],
      note: null as string | null,
      lessonInfo: null as string | null,
    };
  }

  function harness(
    stored: ReturnType<typeof storedRow>[],
    entries: EntriesResponse,
    groups: Array<{ id: string; externalId: string }> = [{ id: 'group-1', externalId: '15027' }],
  ) {
    const tx = {
      timetableEntry: {
        findMany: jest.fn().mockResolvedValue(stored),
        createManyAndReturn: jest.fn().mockResolvedValue([]),
        update: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      timetableEntryGroup: {
        // No stored links: what gets withdrawn is covered state-based in
        // timetable-sync.links.spec.ts.
        findMany: jest.fn().mockResolvedValue([]),
        createMany: jest.fn().mockResolvedValue({ count: 0 }),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };
    const contextFindMany = jest.fn().mockResolvedValue([
      {
        externalId: '49',
        validFrom: new Date('2026-04-07T00:00:00.000Z'),
        validTo: new Date('2026-09-30T00:00:00.000Z'),
      },
    ]);
    const prisma = {
      timetableSyncRun: {
        create: jest.fn().mockResolvedValue({ id: 'run-1' }),
        update: jest.fn(),
      },
      timetableContext: { findMany: contextFindMany },
      timetableGroup: {
        findMany: jest.fn().mockResolvedValue(groups),
      },
      $transaction: jest.fn(async (operation: (transaction: typeof tx) => Promise<number>) =>
        operation(tx),
      ),
    } as unknown as PrismaService;

    const fetchClasses = jest.fn(async (_yearId: number) => ({
      resourceType: 'CLASS',
      classes: [{ class: { id: 15027, shortName: 'AR2Ü1' }, department: null }],
    }));
    const fetchEntries = jest.fn(
      async (_yearId: number, _from: string, _to: string, _classId: number) => entries,
    );
    const client = {
      fetchClasses,
      fetchEntries,
    } as unknown as WebUntisClient;
    const service = new TimetableSyncService(prisma, client, {
      WEBUNTIS_LOOKBACK_DAYS: 7,
      WEBUNTIS_LOOKAHEAD_DAYS: 21,
    } as Env);

    return { service, tx, contextFindMany, fetchClasses, fetchEntries };
  }

  it('touches nothing but the seen-stamp when the response repeats itself', async () => {
    const ids = Array.from({ length: 100 }, (_, index) => 5000 + index);
    const { service, tx } = harness(
      ids.map((id) => storedRow(id)),
      response(ids),
    );

    const outcome = await service.syncEntries(RANGE.from, RANGE.to);

    expect(outcome.status).toBe('success');
    expect(tx.timetableEntry.findMany).toHaveBeenCalledTimes(1);
    expect(tx.timetableEntry.createManyAndReturn).not.toHaveBeenCalled();
    expect(tx.timetableEntry.update).not.toHaveBeenCalled();
    // One statement stamps all 100 as seen — the same stamp the upsert loop
    // wrote, without 100 round-trips.
    expect(tx.timetableEntry.updateMany).toHaveBeenCalledTimes(1);
    expect(tx.timetableEntry.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ids.map((id) => `row-${id}`) } },
      data: { lastSeenAt: expect.any(Date) },
    });
  });

  it('writes one row per changed lesson and nothing for the rest', async () => {
    const ids = Array.from({ length: 100 }, (_, index) => 5000 + index);
    const stored = ids.map((id) => storedRow(id));
    // One lesson was cancelled upstream since the last run.
    stored[7]!.status = 'cancelled';

    const { service, tx } = harness(stored, response(ids));

    await service.syncEntries(RANGE.from, RANGE.to);

    expect(tx.timetableEntry.update).toHaveBeenCalledTimes(1);
    expect(tx.timetableEntry.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { source_externalKey: { source: 'webuntis', externalKey: String(ids[7]) } },
      }),
    );
    expect(tx.timetableEntry.updateMany).toHaveBeenCalledTimes(1);
  });

  it('persists lesson information separately and updates a changed value', async () => {
    const incoming = response([7001]);
    incoming.days[0]!.gridEntries[0]!.lessonInfo = ' P1 ';
    incoming.days[0]!.gridEntries[0]!.lessonText = 'Separate note';
    const { service, tx } = harness([], incoming);
    await service.syncEntries(RANGE.from, RANGE.to);
    expect(tx.timetableEntry.createManyAndReturn).toHaveBeenCalledWith(
      expect.objectContaining({
        data: [
          expect.objectContaining({
            lessonInfo: ' P1 ',
            note: 'Separate note',
          }),
        ],
      }),
    );

    const stored = { ...storedRow(7001), note: 'Separate note' };
    const changed = harness([stored], incoming);
    await changed.service.syncEntries(RANGE.from, RANGE.to);
    expect(changed.tx.timetableEntry.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ lessonInfo: ' P1 ' }) }),
    );
  });

  it('links a shared lesson to every attending class, exactly once each', async () => {
    // The source delivers the same lesson once per attending class — same
    // `ids`, a different `resource` per day block. The importer has to union
    // those classes onto one entry: last-one-wins would drop a class, and a
    // repeated occurrence must not produce a duplicate link.
    const shared = response([7001]);
    const secondClass = structuredClone(shared.days[0]!);
    secondClass.resource = { ...secondClass.resource, id: 15028, shortName: 'AR2Ü2' };
    secondClass.gridEntries[0]!.lessonInfo = 'Synthetic shared lesson information';
    const thirdOccurrence = structuredClone(shared.days[0]!);
    shared.days.push(secondClass, thirdOccurrence);

    const { service, tx } = harness([], shared, [
      { id: 'group-1', externalId: '15027' },
      { id: 'group-2', externalId: '15028' },
    ]);
    tx.timetableEntry.createManyAndReturn.mockResolvedValue([
      { id: 'row-7001', externalKey: '7001' },
    ]);

    await service.syncEntries(RANGE.from, RANGE.to);

    expect(tx.timetableEntry.createManyAndReturn).toHaveBeenCalledTimes(1);
    expect(tx.timetableEntry.createManyAndReturn).toHaveBeenCalledWith(
      expect.objectContaining({
        data: [
          expect.objectContaining({
            lessonInfo: 'Synthetic shared lesson information',
          }),
        ],
      }),
    );
    expect(tx.timetableEntryGroup.createMany).toHaveBeenCalledTimes(1);
    const links = tx.timetableEntryGroup.createMany.mock.calls[0]![0].data as Array<{
      entryId: string;
      groupId: string;
    }>;
    expect(links).toEqual([
      { entryId: 'row-7001', groupId: 'group-1' },
      { entryId: 'row-7001', groupId: 'group-2' },
    ]);
  });

  it('inserts genuinely new lessons in one statement', async () => {
    const ids = Array.from({ length: 30 }, (_, index) => 6000 + index);
    const { service, tx } = harness([], response(ids));
    tx.timetableEntry.createManyAndReturn.mockResolvedValue(
      ids.map((id) => ({ id: `row-${id}`, externalKey: String(id) })),
    );

    await service.syncEntries(RANGE.from, RANGE.to);

    expect(tx.timetableEntry.createManyAndReturn).toHaveBeenCalledTimes(1);
    expect(tx.timetableEntry.update).not.toHaveBeenCalled();
    expect(tx.timetableEntry.updateMany).not.toHaveBeenCalled();
    // Every new lesson still gets its group link.
    expect(tx.timetableEntryGroup.createMany).toHaveBeenCalledWith({
      data: ids.map((id) => ({ entryId: `row-${id}`, groupId: 'group-1' })),
      skipDuplicates: true,
    });
  });

  it('reads the next semester using its own year, class and clipped dates', async () => {
    const { service, contextFindMany, fetchClasses, fetchEntries } = harness([], response([7001]), [
      { id: 'group-next', externalId: '15120' },
    ]);
    contextFindMany.mockResolvedValue([
      {
        externalId: '49',
        validFrom: new Date('2026-04-07T00:00:00.000Z'),
        validTo: new Date('2026-09-30T00:00:00.000Z'),
      },
      {
        externalId: '51',
        validFrom: new Date('2026-10-05T00:00:00.000Z'),
        validTo: new Date('2027-03-31T00:00:00.000Z'),
      },
    ]);
    fetchClasses.mockImplementation(async (yearId: number) => ({
      resourceType: 'CLASS',
      classes: [
        { class: { id: yearId === 49 ? 15027 : 15120, shortName: 'AR2Ü1' }, department: null },
      ],
    }));
    fetchEntries.mockImplementation(async (yearId: number) => {
      if (yearId === 49) return { days: [] };
      const next = response([7001]);
      next.days[0]!.date = '2026-10-05';
      next.days[0]!.resource.id = 15120;
      next.days[0]!.gridEntries[0]!.duration = {
        start: '2026-10-05T10:00',
        end: '2026-10-05T11:30',
      };
      return next;
    });

    const result = await service.syncEntries('2026-09-23', '2026-10-10');

    expect(result.status).toBe('success');
    expect(fetchClasses.mock.calls.map((call) => call[0])).toEqual([49, 51]);
    expect(fetchEntries).toHaveBeenNthCalledWith(1, 49, '2026-09-23', '2026-09-30', 15027);
    expect(fetchEntries).toHaveBeenNthCalledWith(2, 51, '2026-10-05', '2026-10-10', 15120);
  });

  it('keeps stored entries when one class request fails', async () => {
    const { service, tx, fetchClasses, fetchEntries } = harness([], response([7001]));
    fetchClasses.mockResolvedValue({
      resourceType: 'CLASS',
      classes: [
        { class: { id: 15027, shortName: 'AR2Ü1' }, department: null },
        { class: { id: 15028, shortName: 'AR2Ü2' }, department: null },
      ],
    });
    fetchEntries.mockRejectedValueOnce(new Error('source unavailable'));

    const result = await service.syncEntries(RANGE.from, RANGE.to);

    expect(result.status).toBe('failed');
    expect(tx.timetableEntry.findMany).not.toHaveBeenCalled();
    expect(tx.timetableEntry.deleteMany).not.toHaveBeenCalled();
  });
});

/**
 * Cost contract of the catalogue write phase.
 *
 * A class catalogue changes once a semester. Rewriting all ~270 rows on every
 * run was work spent to record nothing. What ends up stored is proven against
 * a real database in test/timetable-sync.integration.spec.ts.
 */
describe('TimetableSyncService catalogue write phase', () => {
  /** `count` classes as the upstream filter endpoint returns them. */
  function classes(count: number, renamed = new Set<number>()) {
    return {
      resourceType: 'CLASS',
      classes: Array.from({ length: count }, (_, index) => ({
        class: {
          id: 15000 + index,
          shortName: `K${index}`,
          longName: `Klasse ${index}${renamed.has(index) ? ' (neu)' : ''}`,
          displayName: '',
        },
        department: { id: 1, shortName: 'KÖT', longName: 'KÖT', displayName: 'KÖT' },
      })),
    };
  }

  /** The row that class would already be stored as. */
  function storedGroup(index: number, over: Record<string, unknown> = {}) {
    return {
      id: `group-${index}`,
      externalId: String(15000 + index),
      shortName: `K${index}`,
      longName: `Klasse ${index}`,
      department: 'KÖT',
      active: true,
      ...over,
    };
  }

  function harness(stored: ReturnType<typeof storedGroup>[], upstream: ReturnType<typeof classes>) {
    const linkedGroups = upstream.classes.map((item, index) => ({
      id:
        stored.find((row) => row.externalId === String(item.class.id))?.id ??
        `created-group-${index}`,
      externalId: String(item.class.id),
    }));
    const tx = {
      timetableGroup: {
        findMany: jest.fn().mockResolvedValueOnce(stored).mockResolvedValueOnce(linkedGroups),
        createMany: jest.fn().mockResolvedValue({ count: 0 }),
        update: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      timetableContextGroup: {
        createMany: jest.fn().mockResolvedValue({ count: 0 }),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };
    const prisma = {
      timetableSyncRun: {
        create: jest.fn().mockResolvedValue({ id: 'run-1' }),
        update: jest.fn(),
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
      timetableGroup: { updateMany: jest.fn().mockResolvedValue({ count: 0 }) },
      $transaction: jest.fn(async (operation: (transaction: typeof tx) => Promise<void>) =>
        operation(tx),
      ),
    } as unknown as PrismaService;

    const client = { fetchClasses: jest.fn(async () => upstream) } as unknown as WebUntisClient;
    const service = new TimetableSyncService(prisma, client, {
      WEBUNTIS_LOOKBACK_DAYS: 7,
      WEBUNTIS_LOOKAHEAD_DAYS: 28,
    } as Env);
    return { service, tx };
  }

  it('touches nothing but the seen-stamp when the catalogue has not moved', async () => {
    const stored = Array.from({ length: 270 }, (_, index) => storedGroup(index));
    const { service, tx } = harness(stored, classes(270));

    const outcome = await service.syncGroups(new Date('2026-07-20T00:00:00.000Z'));

    expect(outcome.status).toBe('success');
    expect(tx.timetableGroup.createMany).not.toHaveBeenCalled();
    expect(tx.timetableGroup.update).not.toHaveBeenCalled();
    expect(tx.timetableGroup.updateMany).toHaveBeenCalledTimes(1);
    expect(tx.timetableGroup.updateMany).toHaveBeenCalledWith({
      where: { id: { in: stored.map((row) => row.id) } },
      data: { lastSeenAt: expect.any(Date) },
    });
    expect(tx.timetableContextGroup.createMany).toHaveBeenCalledWith({
      data: stored.map((row) => ({ contextId: 'context-49', groupId: row.id })),
      skipDuplicates: true,
    });
    expect(tx.timetableContextGroup.deleteMany).toHaveBeenCalledWith({
      where: {
        contextId: 'context-49',
        groupId: { notIn: stored.map((row) => row.id) },
      },
    });
  });

  it('writes one row per renamed class and nothing for the rest', async () => {
    const stored = Array.from({ length: 270 }, (_, index) => storedGroup(index));
    const { service, tx } = harness(stored, classes(270, new Set([9])));

    await service.syncGroups(new Date('2026-07-20T00:00:00.000Z'));

    expect(tx.timetableGroup.update).toHaveBeenCalledTimes(1);
    expect(tx.timetableGroup.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { source_externalId: { source: 'webuntis', externalId: '15009' } },
        data: expect.objectContaining({ longName: 'Klasse 9 (neu)', active: true }),
      }),
    );
  });

  it('revives a retired class instead of leaving it deactivated', async () => {
    // The update used to set `active: true` unconditionally, so a class that
    // reappears must count as changed even when its names match exactly.
    const stored = [storedGroup(0, { active: false })];
    const { service, tx } = harness(stored, classes(1));

    await service.syncGroups(new Date('2026-07-20T00:00:00.000Z'));

    expect(tx.timetableGroup.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ active: true }) }),
    );
    expect(tx.timetableGroup.updateMany).not.toHaveBeenCalled();
  });

  it('inserts a brand-new catalogue in one statement', async () => {
    const { service, tx } = harness([], classes(270));

    await service.syncGroups(new Date('2026-07-20T00:00:00.000Z'));

    expect(tx.timetableGroup.createMany).toHaveBeenCalledTimes(1);
    expect(tx.timetableGroup.update).not.toHaveBeenCalled();
    expect(tx.timetableGroup.updateMany).not.toHaveBeenCalled();
  });
});
