import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { CanteenSyncService } from '../src/modules/canteen/canteen-sync.service';
import { CANTEENS } from '../src/modules/canteen/canteens.config';
import { CanteenSourceError, MeineMensaClient } from '../src/modules/canteen/meine-mensa.client';
import { foodPlanResponseSchema } from '../src/modules/canteen/meine-mensa.schema';
import { Env, validateEnv } from '../src/config/env.schema';
import { PrismaService } from '../src/prisma/prisma.service';
import { PrismaClient } from '../src/generated/prisma/client';
import { createTestPrisma, resetDatabase } from './helpers/database';

// These tests exercise a real PostgreSQL service. On a shared CI runner,
// resetting all operational tables can legitimately exceed Jest's 5s default.
jest.setTimeout(60_000);

/**
 * Integration tests for the synchronisation guarantees, run against a REAL
 * database. These assertions are about persisted state, so a mocked repository
 * would not actually demonstrate anything.
 */

const FASANERIEALLEE = CANTEENS[0]!;
const LOHMANNSTRASSE = CANTEENS[1]!;

function fixture(name: string) {
  const raw = JSON.parse(
    readFileSync(join(__dirname, 'fixtures/meine-mensa', name), 'utf8'),
  ) as unknown;
  return foodPlanResponseSchema.parse(raw);
}

/** Stub source whose behaviour each test controls. */
function stubClient(
  respond: () => ReturnType<typeof fixture> | Promise<ReturnType<typeof fixture>>,
): MeineMensaClient {
  return { fetchFoodPlans: jest.fn(async () => respond()) } as unknown as MeineMensaClient;
}

describe('CanteenSyncService (integration)', () => {
  let prisma: PrismaClient;
  let env: Env;

  const makeService = (client: MeineMensaClient) =>
    new CanteenSyncService(prisma as unknown as PrismaService, client, env);

  const mealCount = () => prisma.meal.count();
  const mealNames = async () =>
    (await prisma.meal.findMany({ orderBy: { sourcePlanId: 'asc' } })).map((m) => m.name);

  beforeAll(async () => {
    env = validateEnv(process.env);
    prisma = createTestPrisma();
    await prisma.$connect();
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDatabase(prisma);
  });

  describe('seeding', () => {
    it('is idempotent: running it twice creates no duplicates', async () => {
      const service = makeService(stubClient(() => fixture('success.json')));

      await service.seedCanteens();
      await service.seedCanteens();

      expect(await prisma.canteen.count()).toBe(CANTEENS.length);
    });
  });

  describe('successful synchronisation', () => {
    it('imports meals with all provided price groups and no image field', async () => {
      const service = makeService(stubClient(() => fixture('success.json')));
      await service.seedCanteens();

      const outcome = await service.syncCanteen(FASANERIEALLEE);

      expect(outcome.status).toBe('success');
      expect(outcome.recordsUpserted).toBe(3);
      expect(await mealCount()).toBe(3);

      const meal = await prisma.meal.findUnique({
        where: { sourcePlanId: 900001 },
        include: { prices: { orderBy: { group: 'asc' } } },
      });
      expect(meal!.name).toBe('Gemüsepfanne');
      expect(meal!.isSprint).toBe(true);
      expect(meal!.prices.map((p) => [p.group, p.amount.toString()])).toEqual([
        ['employee', '4.95'],
        ['guest', '7'],
        ['student', '1.95'],
      ]);
      // The schema has no image column at all.
      expect(Object.keys(meal!)).not.toContain('imageUrl');
      expect(JSON.stringify(meal)).not.toContain('mediathek');
    });

    it('stores ingredient and marker definitions with their namespace', async () => {
      const service = makeService(stubClient(() => fixture('success.json')));
      await service.seedCanteens();
      await service.syncCanteen(FASANERIEALLEE);

      const vegan = await prisma.ingredientDefinition.findUnique({ where: { code: '52' } });
      const sprint = await prisma.ingredientDefinition.findUnique({ where: { code: '53' } });

      expect(vegan).toMatchObject({ labelDe: 'vegan', kind: 'ingredient', labelEn: null });
      expect(sprint).toMatchObject({ labelDe: 'Sprint-Menü', kind: 'marker', labelEn: null });
    });

    it('records lastSuccessfulSyncAt', async () => {
      const service = makeService(stubClient(() => fixture('success.json')));
      await service.seedCanteens();
      await service.syncCanteen(FASANERIEALLEE);

      const canteen = await prisma.canteen.findUnique({ where: { slug: FASANERIEALLEE.slug } });
      expect(await service.lastSuccessfulSyncAt(canteen!.id)).toBeInstanceOf(Date);
    });

    it('omits a price group the source did not provide, rather than defaulting it', async () => {
      const service = makeService(stubClient(() => fixture('partial-prices.json')));
      await service.seedCanteens();
      await service.syncCanteen(FASANERIEALLEE);

      const meal = await prisma.meal.findUnique({
        where: { sourcePlanId: 900010 },
        include: { prices: true },
      });
      expect(meal!.prices.map((p) => p.group).sort()).toEqual(['guest', 'student']);
    });
  });

  describe('idempotency and change handling', () => {
    it('repeating the same import creates no duplicates', async () => {
      const service = makeService(stubClient(() => fixture('success.json')));
      await service.seedCanteens();

      await service.syncCanteen(FASANERIEALLEE);
      await service.syncCanteen(FASANERIEALLEE);
      await service.syncCanteen(FASANERIEALLEE);

      expect(await mealCount()).toBe(3);
      expect(await prisma.mealPrice.count()).toBe(9);
    });

    it('updates a changed dish in place and withdraws one removed upstream', async () => {
      await makeService(stubClient(() => fixture('success.json'))).seedCanteens();
      await makeService(stubClient(() => fixture('success.json'))).syncCanteen(FASANERIEALLEE);
      expect(await mealCount()).toBe(3);

      await makeService(stubClient(() => fixture('changed.json'))).syncCanteen(FASANERIEALLEE);

      const changed = await prisma.meal.findUnique({
        where: { sourcePlanId: 900001 },
        include: { prices: true },
      });
      expect(changed!.name).toBe('Gemüsepfanne (neu)');
      expect(changed!.isSprint).toBe(false);
      expect(changed!.prices.find((p) => p.group === 'student')!.amount.toString()).toBe('2.15');

      // 900003 was on a date outside the confirmed window and must survive;
      // the withdrawn dish inside the window must be gone.
      expect(await prisma.meal.findUnique({ where: { sourcePlanId: 900002 } })).not.toBeNull();
      expect(await mealNames()).toContain('Linseneintopf');
    });

    it('protects blank placeholders without retaining unrelated withdrawn dishes', async () => {
      const initial = structuredClone(fixture('success.json'));
      initial.data.push({
        ...structuredClone(initial.data[0]!),
        id: 900004,
        date: '2026-07-22',
      });
      initial.data.push({
        ...structuredClone(initial.data[1]!),
        id: 900005,
        food: { ...structuredClone(initial.data[1]!.food), name: 'Withdrawn dish' },
      });

      const service = makeService(stubClient(() => initial));
      await service.seedCanteens();
      await service.syncCanteen(FASANERIEALLEE);
      expect(await mealCount()).toBe(5);

      const updated = structuredClone(initial);
      updated.data = updated.data.filter((entry) => entry.id !== 900005);
      updated.data.find((entry) => entry.id === 900002)!.food.name = '';
      updated.data.find((entry) => entry.id === 900003)!.food.name = '';

      const outcome = await makeService(stubClient(() => updated)).syncCanteen(FASANERIEALLEE);

      expect(outcome).toMatchObject({
        status: 'success',
        recordsRejected: 2,
        recordsRemoved: 1,
      });
      expect(await prisma.meal.findMany({ orderBy: { sourcePlanId: 'asc' } })).toEqual([
        expect.objectContaining({ sourcePlanId: 900001 }),
        expect.objectContaining({ sourcePlanId: 900002, name: 'Nudelauflauf' }),
        expect.objectContaining({ sourcePlanId: 900003, name: 'Linseneintopf' }),
        expect.objectContaining({ sourcePlanId: 900004 }),
      ]);
    });
  });

  describe('batched writes', () => {
    type Response = ReturnType<typeof fixture>;

    /** A copy of the fixture, so a mutation cannot leak into the next test. */
    const copy = (name: string): Response => structuredClone(fixture(name));

    it('drops a price group the source stopped publishing', async () => {
      await makeService(stubClient(() => fixture('success.json'))).seedCanteens();
      await makeService(stubClient(() => fixture('success.json'))).syncCanteen(FASANERIEALLEE);
      expect(
        (await prisma.meal.findUnique({
          where: { sourcePlanId: 900001 },
          include: { prices: true },
        }))!.prices,
      ).toHaveLength(3);

      // Prices are replaced wholesale rather than merged, so a group the
      // source withdraws must not linger as a stale figure. Batching the
      // delete across the whole import must not weaken that.
      const withoutEmployeePrice = copy('success.json');
      for (const entry of withoutEmployeePrice.data) {
        entry.food.price_2 = null;
      }

      await makeService(stubClient(() => withoutEmployeePrice)).syncCanteen(FASANERIEALLEE);

      const meal = await prisma.meal.findUnique({
        where: { sourcePlanId: 900001 },
        include: { prices: true },
      });
      expect(meal!.prices.map((price) => price.group).sort()).toEqual(['guest', 'student']);
    });

    it('writes a relabelled ingredient without ever filling labelEn', async () => {
      await makeService(stubClient(() => fixture('success.json'))).seedCanteens();
      await makeService(stubClient(() => fixture('success.json'))).syncCanteen(FASANERIEALLEE);

      const relabelled = copy('success.json');
      relabelled.meta!.ingredients!['52'] = 'vegan (neu)';

      await makeService(stubClient(() => relabelled)).syncCanteen(FASANERIEALLEE);

      expect(await prisma.ingredientDefinition.findUnique({ where: { code: '52' } })).toMatchObject(
        { labelDe: 'vegan (neu)', kind: 'ingredient', labelEn: null },
      );
    });

    it('leaves every row untouched when the source republishes the same plan', async () => {
      await makeService(stubClient(() => fixture('success.json'))).seedCanteens();
      await makeService(stubClient(() => fixture('success.json'))).syncCanteen(FASANERIEALLEE);

      const before = await prisma.meal.findMany({
        orderBy: { sourcePlanId: 'asc' },
        include: { prices: { orderBy: { group: 'asc' } } },
      });
      expect(before).toHaveLength(3);

      // The plan is fetched every two hours and normally has not moved. Nothing
      // should be rewritten — `updatedAt` is the observable proof of that.
      const outcome = await makeService(stubClient(() => fixture('success.json'))).syncCanteen(
        FASANERIEALLEE,
      );
      expect(outcome.status).toBe('success');

      const after = await prisma.meal.findMany({
        orderBy: { sourcePlanId: 'asc' },
        include: { prices: { orderBy: { group: 'asc' } } },
      });
      expect(after).toEqual(before);
    });

    it('rewrites the changed dish and its prices, and nothing else', async () => {
      await makeService(stubClient(() => fixture('success.json'))).seedCanteens();
      await makeService(stubClient(() => fixture('success.json'))).syncCanteen(FASANERIEALLEE);

      const before = await prisma.meal.findMany({
        orderBy: { sourcePlanId: 'asc' },
        include: { prices: true },
      });

      const changed = copy('success.json');
      const target = changed.data[0]!;
      target.food.name = 'Gemüsepfanne (neu)';
      // The fixture is already parsed, so prices are the normalised strings.
      target.food.price_1 = '2.15';

      await makeService(stubClient(() => changed)).syncCanteen(FASANERIEALLEE);

      const after = await prisma.meal.findMany({
        orderBy: { sourcePlanId: 'asc' },
        include: { prices: true },
      });
      // Nothing was recreated.
      expect(after.map((row) => row.id)).toEqual(before.map((row) => row.id));

      const moved = after.find((row) => row.sourcePlanId === target.id)!;
      expect(moved.name).toBe('Gemüsepfanne (neu)');
      expect(moved.prices.find((price) => price.group === 'student')!.amount.toString()).toBe(
        '2.15',
      );

      for (const previous of before.filter((row) => row.sourcePlanId !== target.id)) {
        expect(after.find((row) => row.id === previous.id)).toEqual(previous);
      }
    });

    it('takes over a row of another source that carries the same plan id', async () => {
      // The write matches on sourcePlanId alone and sets `source` with the rest,
      // so a row seeded by the user-test data is adopted, not duplicated.
      await makeService(stubClient(() => fixture('success.json'))).seedCanteens();
      const canteen = await prisma.canteen.findUnique({ where: { slug: FASANERIEALLEE.slug } });
      const foreign = await prisma.meal.create({
        data: {
          source: 'user-test-data',
          sourcePlanId: 900001,
          canteenId: canteen!.id,
          date: new Date('2026-07-20T00:00:00.000Z'),
          name: 'Aus dem Testdatensatz',
          extras: [],
          ingredientCodes: [],
        },
      });

      const outcome = await makeService(stubClient(() => fixture('success.json'))).syncCanteen(
        FASANERIEALLEE,
      );

      expect(outcome.status).toBe('success');
      const adopted = await prisma.meal.findUnique({ where: { sourcePlanId: 900001 } });
      expect(adopted!.id).toBe(foreign.id);
      expect(adopted!.source).toBe('meine-mensa');
      expect(adopted!.name).toBe('Gemüsepfanne');
    });

    it('keeps the last entry when the source publishes a code in both dictionaries', async () => {
      // The dictionaries are written in one batch now, so a code listed as
      // both an ingredient and a marker would collide on the primary key
      // unless the collapse happens before the write — and it has to collapse
      // the same way the sequential loop did: last one wins.
      const both = copy('success.json');
      both.meta!.markers!['52'] = 'vegan (Marker)';

      await makeService(stubClient(() => both)).seedCanteens();
      const outcome = await makeService(stubClient(() => both)).syncCanteen(FASANERIEALLEE);

      expect(outcome.status).toBe('success');
      expect(await prisma.ingredientDefinition.findUnique({ where: { code: '52' } })).toMatchObject(
        { labelDe: 'vegan (Marker)', kind: 'marker' },
      );
    });

    it('keeps the last entry when the source repeats a plan id', async () => {
      const duplicated = copy('success.json');
      const first = duplicated.data[0]!;
      duplicated.data.push(
        structuredClone({ ...first, food: { ...first.food, name: 'Zweite Fassung' } }),
      );

      await makeService(stubClient(() => duplicated)).seedCanteens();
      const outcome = await makeService(stubClient(() => duplicated)).syncCanteen(FASANERIEALLEE);

      expect(outcome.status).toBe('success');
      const meal = await prisma.meal.findUnique({
        where: { sourcePlanId: first.id },
        include: { prices: true },
      });
      expect(meal!.name).toBe('Zweite Fassung');
      // One row per price group, not two.
      expect(meal!.prices).toHaveLength(3);
    });
  });

  describe('resilience — stored data must survive a bad response', () => {
    const seedGoodData = async () => {
      const service = makeService(stubClient(() => fixture('success.json')));
      await service.seedCanteens();
      await service.syncCanteen(FASANERIEALLEE);
      expect(await mealCount()).toBe(3);
    };

    it('keeps existing data when the source returns an EMPTY list', async () => {
      await seedGoodData();

      const outcome = await makeService(stubClient(() => fixture('empty.json'))).syncCanteen(
        FASANERIEALLEE,
      );

      expect(outcome.status).toBe('empty');
      expect(outcome.recordsRemoved).toBe(0);
      expect(await mealCount()).toBe(3);
    });

    it('keeps existing data when the request TIMES OUT', async () => {
      await seedGoodData();

      const failing = {
        fetchFoodPlans: jest.fn(async () => {
          throw new CanteenSourceError('timeout', 'source request timed out');
        }),
      } as unknown as MeineMensaClient;

      const outcome = await makeService(failing).syncCanteen(FASANERIEALLEE);

      expect(outcome.status).toBe('failed');
      expect(outcome.errorMessage).toContain('timeout');
      expect(await mealCount()).toBe(3);
    });

    it('keeps existing data when the response is MALFORMED', async () => {
      await seedGoodData();

      const failing = {
        fetchFoodPlans: jest.fn(async () => {
          throw new CanteenSourceError('malformed', 'response failed validation');
        }),
      } as unknown as MeineMensaClient;

      const outcome = await makeService(failing).syncCanteen(FASANERIEALLEE);

      expect(outcome.status).toBe('failed');
      expect(await mealCount()).toBe(3);
    });

    it('keeps existing data when the source returns an HTTP error', async () => {
      await seedGoodData();

      const failing = {
        fetchFoodPlans: jest.fn(async () => {
          throw new CanteenSourceError('http', 'source responded with status 503', 503);
        }),
      } as unknown as MeineMensaClient;

      expect((await makeService(failing).syncCanteen(FASANERIEALLEE)).status).toBe('failed');
      expect(await mealCount()).toBe(3);
    });

    it('records the failure in sync_runs without touching lastSuccessfulSyncAt', async () => {
      await seedGoodData();
      const canteen = await prisma.canteen.findUnique({ where: { slug: FASANERIEALLEE.slug } });
      const before = await makeService(
        stubClient(() => fixture('success.json')),
      ).lastSuccessfulSyncAt(canteen!.id);

      const failing = {
        fetchFoodPlans: jest.fn(async () => {
          throw new CanteenSourceError('network', 'unreachable');
        }),
      } as unknown as MeineMensaClient;
      const service = makeService(failing);
      await service.syncCanteen(FASANERIEALLEE);

      expect(await service.lastSuccessfulSyncAt(canteen!.id)).toEqual(before);
      expect(await prisma.syncRun.count({ where: { status: 'failed' } })).toBe(1);
    });
  });

  describe('location_id mismatch', () => {
    it('rejects entries belonging to another canteen and imports only the matching ones', async () => {
      const service = makeService(stubClient(() => fixture('location-mismatch.json')));
      await service.seedCanteens();

      const outcome = await service.syncCanteen(FASANERIEALLEE);

      expect(outcome.recordsReceived).toBe(2);
      expect(outcome.recordsUpserted).toBe(1);
      expect(outcome.recordsRejected).toBe(1);

      expect(await mealNames()).toEqual(['Richtiges Gericht']);
      expect(await prisma.meal.findUnique({ where: { sourcePlanId: 900020 } })).toBeNull();
    });

    it('treats a response with ONLY foreign entries as empty and keeps stored data', async () => {
      const service = makeService(stubClient(() => fixture('success.json')));
      await service.seedCanteens();
      await service.syncCanteen(FASANERIEALLEE);

      // Fasanerieallee asking, but every entry belongs to Lohmannstraße.
      const outcome = await makeService(
        stubClient(() => fixture('lohmannstrasse.json')),
      ).syncCanteen(FASANERIEALLEE);

      expect(outcome.status).toBe('empty');
      expect(outcome.recordsRejected).toBe(1);
      expect(await mealCount()).toBe(3);
    });
  });

  describe('canteen isolation', () => {
    it("keeps each canteen's meals separate", async () => {
      const service = makeService(stubClient(() => fixture('success.json')));
      await service.seedCanteens();
      await service.syncCanteen(FASANERIEALLEE);

      await makeService(stubClient(() => fixture('lohmannstrasse.json'))).syncCanteen(
        LOHMANNSTRASSE,
      );

      const fasanerieallee = await prisma.canteen.findUnique({
        where: { slug: FASANERIEALLEE.slug },
      });
      const lohmannstrasse = await prisma.canteen.findUnique({
        where: { slug: LOHMANNSTRASSE.slug },
      });

      expect(await prisma.meal.count({ where: { canteenId: fasanerieallee!.id } })).toBe(3);
      expect(await prisma.meal.count({ where: { canteenId: lohmannstrasse!.id } })).toBe(1);
    });
  });
});
