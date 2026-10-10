import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { CanteenSyncService } from '../canteen/canteen-sync.service';
import { CANTEENS } from '../canteen/canteens.config';
import { UserTestDataSeedService } from './user-test-data.seed.service';

describe('UserTestDataSeedService safety boundary', () => {
  it('refuses to write unless the deployment explicitly opts in', async () => {
    const service = new UserTestDataSeedService(
      {} as PrismaService,
      {} as CanteenSyncService,
      { USER_TEST_DATA_ENABLED: false } as Env,
    );

    await expect(service.seed()).rejects.toThrow(/USER_TEST_DATA_ENABLED/);
  });

  it('marks every seeded public calendar as user-test owned', async () => {
    // The catalogue sync retires every Strapi row Strapi no longer publishes,
    // and the event sync downloads every active row. Only the `source` column
    // keeps both away from the synthetic calendars.
    const upserts: Array<{ create: Record<string, unknown>; update: Record<string, unknown> }> = [];
    const transaction = new Proxy(
      {},
      {
        get: (_target, modelName) =>
          new Proxy(
            {},
            {
              get: (_model, method) =>
                jest.fn(
                  (args: { create: Record<string, unknown>; update: Record<string, unknown> }) => {
                    if (modelName === 'publicCalendar' && method === 'upsert') upserts.push(args);
                    return Promise.resolve({ id: `${String(modelName)}-id`, count: 0 });
                  },
                ),
            },
          ),
      },
    );
    const activeCanteens = CANTEENS.filter((item) => item.active);
    const prisma = {
      canteen: {
        findMany: jest.fn(() =>
          Promise.resolve(
            activeCanteens.map((item) => ({ id: `${item.slug}-id`, slug: item.slug })),
          ),
        ),
      },
      $transaction: jest.fn((operation: (tx: unknown) => Promise<unknown>) =>
        operation(transaction),
      ),
    } as unknown as PrismaService;
    const service = new UserTestDataSeedService(
      prisma,
      { seedCanteens: jest.fn(() => Promise.resolve()) } as unknown as CanteenSyncService,
      { USER_TEST_DATA_ENABLED: true, WORKER_TIME_ZONE: 'Europe/Berlin' } as Env,
    );

    const summary = await service.seed(new Date('2026-10-05T10:00:00.000Z'));

    expect(upserts).toHaveLength(summary.calendars);
    expect(upserts.length).toBeGreaterThan(0);
    for (const { create, update } of upserts) {
      expect(create).toMatchObject({ source: 'user-test' });
      expect(update).toMatchObject({ source: 'user-test' });
      expect(String(create['googleCalendarId'])).toMatch(/\.invalid$/);
    }
  });

  it('removes only rows owned by the user-test source', async () => {
    const deleted: Array<{ model: string; where: unknown }> = [];
    const model = (name: string) => ({
      deleteMany: jest.fn(async ({ where }: { where: unknown }) => {
        deleted.push({ model: name, where });
        return { count: 1 };
      }),
    });
    const transaction = {
      syncRun: model('syncRun'),
      meal: model('meal'),
      timetableSyncRun: model('timetableSyncRun'),
      timetableEntry: model('timetableEntry'),
      timetableGroup: model('timetableGroup'),
      timetableContext: model('timetableContext'),
      publicCalendarEvent: model('publicCalendarEvent'),
      publicCalendarSyncRun: model('publicCalendarSyncRun'),
      publicCalendar: model('publicCalendar'),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (tx: typeof transaction) => Promise<unknown>) =>
        operation(transaction),
      ),
    } as unknown as PrismaService;
    const service = new UserTestDataSeedService(
      prisma,
      {} as CanteenSyncService,
      { USER_TEST_DATA_ENABLED: false } as Env,
    );

    await service.remove();

    expect(deleted).toHaveLength(9);
    expect(deleted.every((operation) => operation.where)).toBe(true);
    expect(deleted).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ model: 'meal', where: { source: 'user-test' } }),
        expect.objectContaining({ model: 'timetableEntry', where: { source: 'user-test' } }),
      ]),
    );

    // Removal of the public calendars (and their runs, which have no `source`) is
    // scoped by the reserved slug prefix. An unscoped delete here would wipe an editor's
    // real calendars along with the synthetic ones.
    const calendarDeletes = deleted.filter((operation) =>
      operation.model.startsWith('publicCalendar'),
    );
    expect(calendarDeletes).toHaveLength(3);
    expect(JSON.stringify(calendarDeletes)).toContain('user-test-');
    expect(
      calendarDeletes.every((operation) => JSON.stringify(operation.where).includes('startsWith')),
    ).toBe(true);
  });
});
