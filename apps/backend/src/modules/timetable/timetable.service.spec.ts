import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { TimetableService } from './timetable.service';

describe('TimetableService feature availability', () => {
  it('serves the seeded timetable when user-test data is enabled without WebUntis', () => {
    const service = new TimetableService(
      {} as PrismaService,
      {
        WEBUNTIS_ENABLED: false,
        USER_TEST_DATA_ENABLED: true,
      } as Env,
    );

    expect(service.featureEnabled).toBe(true);
  });
});

describe('TimetableService group catalogue', () => {
  const locale = { requestedLocale: 'de', resolvedLocale: 'de' } as const;
  const env = {
    WEBUNTIS_ENABLED: true,
    USER_TEST_DATA_ENABLED: false,
    WEBUNTIS_STALE_AFTER_MINUTES: 180,
  } as Env;

  it('pages across the complete catalogue without a fixed total cap', async () => {
    const groups = [
      {
        id: '43a7302c-19ce-4fd7-a06e-003599fd75d0',
        shortName: 'ZZZ',
        longName: 'Last group',
        department: 'FB7',
      },
    ];
    const prisma = {
      timetableGroup: {
        count: jest.fn().mockResolvedValue(503),
        findMany: jest.fn().mockResolvedValue(groups),
      },
      timetableSyncRun: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = new TimetableService(prisma as unknown as PrismaService, env);

    const result = await service.listGroups(locale, {
      page: 11,
      pageSize: 50,
      query: 'zzz',
    });

    expect(result.data).toEqual(groups);
    expect(result.pagination).toEqual({
      page: 11,
      pageSize: 50,
      total: 503,
      totalPages: 11,
    });
    const where = {
      active: true,
      catalogVisible: true,
      OR: [
        { shortName: { contains: 'zzz', mode: 'insensitive' } },
        { longName: { contains: 'zzz', mode: 'insensitive' } },
        { department: { contains: 'zzz', mode: 'insensitive' } },
      ],
    };
    expect(prisma.timetableGroup.count).toHaveBeenCalledWith({ where });
    expect(prisma.timetableGroup.findMany).toHaveBeenCalledWith({
      where,
      orderBy: [{ shortName: 'asc' }, { longName: 'asc' }, { department: 'asc' }, { id: 'asc' }],
      select: { id: true, shortName: true, longName: true, department: true },
      skip: 500,
      take: 50,
    });
  });

  it('resolves one saved Campus group without exposing its upstream id', async () => {
    const publicGroup = {
      id: '43a7302c-19ce-4fd7-a06e-003599fd75d0',
      shortName: 'AIN2 - BT',
      longName: 'Angewandte Informatik',
      department: 'FB5',
    };
    const prisma = {
      timetableGroup: {
        findFirst: jest.fn().mockResolvedValue({
          ...publicGroup,
          externalId: 'secret-source-id',
          catalogVisible: true,
          contexts: [{ contextId: 'context-internal' }],
        }),
      },
      timetableSyncRun: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = new TimetableService(prisma as unknown as PrismaService, env);

    const result = await service.getGroup(locale, publicGroup.id);

    expect(result.data).toEqual(publicGroup);
    expect(JSON.stringify(result)).not.toContain('secret-source-id');
    expect(JSON.stringify(result)).not.toContain('context-internal');
    expect(prisma.timetableGroup.findFirst).toHaveBeenCalledTimes(1);
    expect(prisma.timetableGroup.findFirst).toHaveBeenCalledWith({
      where: { id: publicGroup.id },
      select: {
        id: true,
        shortName: true,
        longName: true,
        department: true,
        catalogVisible: true,
        contexts: { select: { contextId: true } },
      },
    });
  });

  const hidden = {
    id: '43a7302c-19ce-4fd7-a06e-003599fd75d0',
    shortName: 'AIN2 - BT',
    longName: 'Angewandte Informatik',
    department: 'FB5',
    catalogVisible: false,
  };
  const visible = {
    ...hidden,
    id: '11111111-1111-4111-8111-111111111111',
    catalogVisible: true,
  };
  const publicSelect = {
    id: true,
    shortName: true,
    longName: true,
    department: true,
    catalogVisible: true,
  };

  it('migrates a saved hidden alias to its visible representative of the same semester', async () => {
    const prisma = {
      timetableGroup: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ ...hidden, contexts: [{ contextId: 'context-ss' }] })
          .mockResolvedValueOnce(visible),
      },
      timetableSyncRun: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = new TimetableService(prisma as unknown as PrismaService, env);

    const result = await service.getGroup(locale, hidden.id);

    expect(result.data).toEqual({
      id: visible.id,
      shortName: visible.shortName,
      longName: visible.longName,
      department: visible.department,
    });
    // Never resolved across semesters: a same-named group of another
    // semester catalogue is a different cohort, not an alias.
    expect(prisma.timetableGroup.findFirst.mock.calls[1]![0]).toEqual({
      where: {
        active: true,
        catalogVisible: true,
        shortName: hidden.shortName,
        longName: hidden.longName,
        department: hidden.department,
        contexts: { some: { contextId: { in: ['context-ss'] } } },
      },
      orderBy: { id: 'asc' },
      select: publicSelect,
    });
  });

  it('resolves a hidden alias without any semester only among groups without one', async () => {
    const prisma = {
      timetableGroup: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ ...hidden, contexts: [] })
          .mockResolvedValueOnce(null),
      },
      timetableSyncRun: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = new TimetableService(prisma as unknown as PrismaService, env);

    const result = await service.getGroup(locale, hidden.id);

    // Nothing matched: the saved group answers for itself.
    expect(result.data.id).toBe(hidden.id);
    expect(prisma.timetableGroup.findFirst.mock.calls[1]![0]).toEqual(
      expect.objectContaining({
        where: expect.objectContaining({ contexts: { none: {} } }),
      }),
    );
  });
});

describe('TimetableService lesson information choices', () => {
  it('returns every distinct source text exactly and includes lessons without information', async () => {
    const groupId = '43a7302c-19ce-4fd7-a06e-003599fd75d0';
    const findMany = jest
      .fn()
      .mockResolvedValue([
        { entry: { lessonInfo: 'P1' } },
        { entry: { lessonInfo: 'Gruppe1' } },
        { entry: { lessonInfo: 'P1' } },
        { entry: { lessonInfo: null } },
      ]);
    const prisma = {
      timetableGroup: { findFirst: jest.fn().mockResolvedValue({ id: groupId }) },
      timetableSyncRun: {
        findFirst: jest.fn().mockResolvedValue({
          rangeFrom: new Date('2026-09-18T00:00:00.000Z'),
          rangeTo: new Date('2027-04-23T00:00:00.000Z'),
        }),
      },
      timetableEntryGroup: { findMany },
    };
    const service = new TimetableService(
      prisma as unknown as PrismaService,
      {
        WEBUNTIS_ENABLED: true,
        USER_TEST_DATA_ENABLED: false,
      } as Env,
    );

    expect(
      await service.listLessonInfo(groupId, { requestedLocale: 'de', resolvedLocale: 'de' }),
    ).toEqual({ values: ['Gruppe1', 'P1'], hasWithoutInfo: true });
    expect(findMany).toHaveBeenCalledWith({
      where: {
        groupId,
        entry: {
          date: {
            gte: new Date('2026-09-18T00:00:00.000Z'),
            lte: new Date('2027-04-23T00:00:00.000Z'),
          },
        },
      },
      select: { entry: { select: { lessonInfo: true } } },
    });
  });
});

describe('TimetableService module catalogue', () => {
  it('deduplicates modules by code and keeps code-less subjects distinct', async () => {
    const groupId = '43a7302c-19ce-4fd7-a06e-003599fd75d0';
    const findMany = jest.fn().mockResolvedValue([
      { subjectCode: ' MATH2 ', title: 'Mathematik II' },
      { subjectCode: 'MATH2', title: 'Mathematik 2' },
      { subjectCode: null, title: 'Wahlpflichtfach Robotik' },
      { subjectCode: '  ', title: 'Wahlpflichtfach Robotik' },
      { subjectCode: null, title: '  ' },
    ]);
    const prisma = {
      timetableGroup: { findFirst: jest.fn().mockResolvedValue({ id: groupId }) },
      timetableEntry: { findMany },
      timetableSyncRun: {
        findFirst: jest.fn().mockResolvedValue({
          finishedAt: new Date('2026-10-07T10:00:00.000Z'),
        }),
      },
    };
    const service = new TimetableService(
      prisma as unknown as PrismaService,
      {
        WEBUNTIS_ENABLED: true,
        USER_TEST_DATA_ENABLED: false,
        WEBUNTIS_STALE_AFTER_MINUTES: 180,
      } as Env,
    );

    const result = await service.listModules(groupId, {
      requestedLocale: 'de',
      resolvedLocale: 'de',
    });

    expect(result.data).toEqual([
      { subjectCode: 'MATH2', title: 'Mathematik II' },
      { subjectCode: null, title: 'Wahlpflichtfach Robotik' },
    ]);
    expect(findMany).toHaveBeenCalledWith({
      where: { groups: { some: { groupId } } },
      orderBy: { startsAt: 'desc' },
      select: { subjectCode: true, title: true },
      take: 2000,
    });
  });
});

describe('TimetableService semester catalogues', () => {
  it('does not expose retained catalogues while the feature is disabled', async () => {
    const timetableContext = { findMany: jest.fn() };
    const prisma = {
      timetableContext,
      timetableSyncRun: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = new TimetableService(
      prisma as unknown as PrismaService,
      {
        WEBUNTIS_ENABLED: false,
        USER_TEST_DATA_ENABLED: false,
        WEBUNTIS_STALE_AFTER_MINUTES: 180,
      } as Env,
    );

    expect(await service.listPeriods()).toEqual({
      data: [],
      lastSyncAt: null,
      stale: true,
    });
    expect(timetableContext.findMany).not.toHaveBeenCalled();
  });

  it('returns Campus ids and groups in chronological order', async () => {
    const timetableContext = {
      findMany: jest.fn().mockResolvedValue([
        {
          id: '20000000-0000-4000-8000-000000000002',
          name: '2026/2027',
          validFrom: new Date('2026-10-05T00:00:00.000Z'),
          validTo: new Date('2027-03-31T00:00:00.000Z'),
          groups: [
            {
              group: {
                id: '30000000-0000-4000-8000-000000000002',
                shortName: 'AIN3',
                longName: 'Angewandte Informatik 3. Semester',
                department: 'FB5',
              },
            },
          ],
        },
        {
          id: '20000000-0000-4000-8000-000000000001',
          name: '2026/2026',
          validFrom: new Date('2026-04-07T00:00:00.000Z'),
          validTo: new Date('2026-09-30T00:00:00.000Z'),
          groups: [],
        },
      ]),
    };
    const prisma = {
      timetableContext,
      timetableSyncRun: {
        findFirst: jest.fn().mockResolvedValue({ finishedAt: new Date() }),
      },
    };
    const service = new TimetableService(
      prisma as unknown as PrismaService,
      {
        WEBUNTIS_ENABLED: true,
        USER_TEST_DATA_ENABLED: false,
        WEBUNTIS_STALE_AFTER_MINUTES: 180,
      } as Env,
    );

    const result = await service.listPeriods();

    expect(result.data.map((period) => period.name)).toEqual(['2026/2026', '2026/2027']);
    expect(result.data[result.data.length - 1]!.groups[0]).toEqual({
      id: '30000000-0000-4000-8000-000000000002',
      shortName: 'AIN3',
      longName: 'Angewandte Informatik 3. Semester',
      department: 'FB5',
    });
    expect(timetableContext.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { groups: { some: {} } },
        take: 8,
      }),
    );
  });
});

/**
 * Cost contract of the sync-run lookups behind /v1/timetable/status.
 *
 * Freshness and the covered window are two fields of the same run row, so
 * asking for them twice is one database roundtrip too many — and neither field
 * needs the counters or the error classification that a `select`-less
 * `findFirst` drags along. `lastSuccessful` is not exclusive to this endpoint
 * either: /v1/timetable/groups and /v1/timetable/week call it on every request
 * too, so the over-fetch was paid three times per page view.
 *
 * The response itself is covered end to end against a real PostgreSQL in
 * test/timetable-api.integration.spec.ts.
 */
describe('TimetableService status lookups', () => {
  const env = {
    WEBUNTIS_ENABLED: true,
    USER_TEST_DATA_ENABLED: false,
    WEBUNTIS_STALE_AFTER_MINUTES: 180,
  } as Env;

  const entryRun = {
    finishedAt: new Date('2026-08-24T02:00:00.000Z'),
    rangeFrom: new Date('2026-08-17T00:00:00.000Z'),
    rangeTo: new Date('2026-08-31T00:00:00.000Z'),
  };
  const groupRun = { finishedAt: new Date('2026-08-24T01:00:00.000Z') };

  function makePrisma() {
    return {
      timetableGroup: { count: jest.fn().mockResolvedValue(270) },
      timetableSyncRun: {
        findFirst: jest.fn(({ where }: { where: { kind: string } }) =>
          Promise.resolve(where.kind === 'entries' ? entryRun : groupRun),
        ),
      },
    };
  }

  it('answers with three queries and reads the entry run only once', async () => {
    const prisma = makePrisma();
    const service = new TimetableService(prisma as unknown as PrismaService, env);

    const status = await service.getStatus();

    expect(status.lastEntrySyncAt).toBe(entryRun.finishedAt.toISOString());
    expect(status.lastGroupSyncAt).toBe(groupRun.finishedAt.toISOString());
    expect(status.coveredFrom).toBe('2026-08-17');
    expect(status.coveredTo).toBe('2026-08-31');

    // One count plus one lookup per kind. The freshness of the entry run and
    // the window it confirmed come out of the same row.
    expect(prisma.timetableGroup.count).toHaveBeenCalledTimes(1);
    expect(prisma.timetableGroup.count).toHaveBeenCalledWith({
      where: { active: true, catalogVisible: true },
    });
    expect(prisma.timetableSyncRun.findFirst).toHaveBeenCalledTimes(2);
    const kinds = prisma.timetableSyncRun.findFirst.mock.calls.map(
      ([args]: [{ where: { kind: string } }]) => args.where.kind,
    );
    expect(kinds.sort()).toEqual(['entries', 'groups']);
  });

  it('selects only the columns the response actually reads', async () => {
    const prisma = makePrisma();
    const service = new TimetableService(prisma as unknown as PrismaService, env);

    await service.getStatus();

    const selects = new Map<string, unknown>(
      prisma.timetableSyncRun.findFirst.mock.calls.map(
        ([args]: [{ where: { kind: string }; select?: unknown }]) => [args.where.kind, args.select],
      ),
    );
    expect(selects.get('groups')).toEqual({ finishedAt: true });
    expect(selects.get('entries')).toEqual({
      finishedAt: true,
      rangeFrom: true,
      rangeTo: true,
    });
  });

  it('projects the freshness lookup on the other read paths too', async () => {
    const prisma = {
      timetableGroup: {
        count: jest.fn(),
        findMany: jest.fn().mockResolvedValue([]),
      },
      timetableSyncRun: { findFirst: jest.fn().mockResolvedValue(groupRun) },
    };
    const service = new TimetableService(prisma as unknown as PrismaService, env);

    await service.listGroups(
      { requestedLocale: 'de', resolvedLocale: 'de' },
      { page: 1, pageSize: 20 },
    );

    expect(prisma.timetableSyncRun.findFirst).toHaveBeenCalledTimes(1);
    expect(prisma.timetableSyncRun.findFirst.mock.calls[0]![0].select).toEqual({
      finishedAt: true,
    });
    expect(prisma.timetableGroup.findMany.mock.calls[0]![0].select).toEqual({
      id: true,
      shortName: true,
      longName: true,
      department: true,
    });
  });

  it('projects only public timetable fields for a week read', async () => {
    const timetableEntryGroup = {
      findMany: jest.fn().mockResolvedValue([
        {
          entry: {
            id: 'synthetic-entry',
            date: new Date('2026-08-24T00:00:00.000Z'),
            startsAt: new Date('2026-08-24T08:00:00.000Z'),
            endsAt: new Date('2026-08-24T09:30:00.000Z'),
            title: 'Synthetic subject',
            subjectCode: 'SYN',
            type: 'regular_teaching',
            status: 'regular',
            teachers: [],
            rooms: [],
            groups: [],
            note: 'Separate note',
            lessonInfo: 'Synthetic lesson information',
          },
        },
      ]),
    };
    const prisma = {
      timetableGroup: {
        findFirst: jest.fn().mockResolvedValue({
          id: '43a7302c-19ce-4fd7-a06e-003599fd75d0',
          shortName: 'BAI23',
          longName: 'Angewandte Informatik 2023',
          department: '6',
        }),
      },
      timetableEntryGroup,
      timetableSyncRun: { findFirst: jest.fn().mockResolvedValue(entryRun) },
    };
    const service = new TimetableService(prisma as unknown as PrismaService, env);

    const week = await service.getWeek(
      { requestedLocale: 'de', resolvedLocale: 'de' },
      '43a7302c-19ce-4fd7-a06e-003599fd75d0',
      { from: '2026-08-24', to: '2026-08-30' },
    );

    expect(week.data.days[0]!.entries[0]).toEqual(
      expect.objectContaining({
        note: 'Separate note',
        lessonInfo: 'Synthetic lesson information',
      }),
    );

    expect(prisma.timetableGroup.findFirst.mock.calls[0]![0].select).toEqual({
      id: true,
      shortName: true,
      longName: true,
      department: true,
    });
    expect(timetableEntryGroup.findMany.mock.calls[0]![0].select).toEqual({
      entry: {
        select: {
          id: true,
          date: true,
          startsAt: true,
          endsAt: true,
          title: true,
          subjectCode: true,
          type: true,
          status: true,
          teachers: true,
          rooms: true,
          note: true,
          lessonInfo: true,
          groups: {
            select: {
              group: {
                select: { id: true, shortName: true, longName: true, department: true },
              },
            },
          },
        },
      },
    });
  });
});
