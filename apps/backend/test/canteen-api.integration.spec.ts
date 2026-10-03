import { INestApplication, VersioningType } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AllExceptionsFilter } from '../src/common/filters/all-exceptions.filter';
import { PrismaClient } from '../src/generated/prisma/client';
import { createTestPrisma, resetDatabase } from './helpers/database';

// Real PostgreSQL setup and cleanup can exceed Jest's 5s default on shared CI.
jest.setTimeout(60_000);

/**
 * API-level tests over real HTTP against a real database.
 *
 * The interesting part here is the semantic classification: the app filters on
 * `traits` and `allergens`, so the mapping from the source's own code namespace
 * has to arrive intact at the edge, not just in a unit test.
 */
describe('/v1/canteens (integration)', () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let canteenId: string;

  const DATE = '2026-07-20';

  beforeAll(async () => {
    prisma = createTestPrisma();
    await prisma.$connect();

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication({ logger: false });
    app.enableVersioning({ type: VersioningType.URI, prefix: 'v' });
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
    await prisma?.$disconnect();
  });

  beforeEach(async () => {
    await resetDatabase(prisma);

    const canteen = await prisma.canteen.create({
      data: {
        slug: 'koethen-fasanerieallee',
        sourceLocationId: 7,
        displayNameDe: 'Mensa Köthen',
        displayNameEn: 'Köthen Canteen',
        campusLabelDe: 'Fasanerieallee',
        campusLabelEn: 'Fasanerieallee',
        sortOrder: 10,
        active: true,
      },
    });
    canteenId = canteen.id;

    // The dictionary exactly as the source publishes it.
    await prisma.ingredientDefinition.createMany({
      data: [
        { code: '52', labelDe: 'vegan', kind: 'ingredient' },
        { code: 'A1', labelDe: 'enthält Weizengluten', kind: 'ingredient' },
        { code: 'G2', labelDe: 'enthält Mandeln', kind: 'ingredient' },
        { code: '2', labelDe: 'Konservierungsstoffe', kind: 'ingredient' },
        { code: '9901', labelDe: 'Klima-Teller', kind: 'marker' },
      ],
    });
  });

  async function createMeal(
    overrides: Partial<{
      sourcePlanId: number;
      name: string;
      isSprint: boolean;
      ingredientCodes: string[];
    }> = {},
  ) {
    return prisma.meal.create({
      data: {
        canteenId,
        sourcePlanId: overrides.sourcePlanId ?? 900001,
        sourceFoodId: 1001,
        date: new Date(`${DATE}T00:00:00.000Z`),
        counterId: 44,
        isSprint: overrides.isSprint ?? false,
        name: overrides.name ?? 'Gemüsepfanne',
        subtitle: 'mit Kichererbsen',
        extras: [],
        ingredientCodes: overrides.ingredientCodes ?? ['52', 'A1', 'G2', '2', '9901'],
        prices: { create: [{ group: 'student', amount: '1.95' }] },
      },
    });
  }

  async function fetchMeals() {
    const response = await request(app.getHttpServer())
      .get(`/v1/canteens/koethen-fasanerieallee/menu?from=${DATE}&to=${DATE}`)
      .expect(200);
    const body = response.body as {
      data: { days: Array<{ date: string; meals: Array<Record<string, unknown>> }> };
    };
    return body.data.days[0]!.meals;
  }

  describe('semantic traits and allergens', () => {
    it('publishes stable keys next to the raw source markers', async () => {
      await createMeal();

      const meal = (await fetchMeals())[0]!;

      expect(meal['traits']).toEqual(['vegan']);
      // The parent facet comes with the subtype: somebody avoiding gluten must
      // not have to know that "A1" means wheat.
      expect(meal['allergens']).toEqual(['gluten', 'gluten_wheat', 'nuts', 'nuts_almond']);
      // Nothing is taken away: every source code is still there to be shown.
      expect((meal['markers'] as Array<{ code: string }>).map((m) => m.code)).toEqual([
        '52',
        'A1',
        'G2',
        '2',
        '9901',
      ]);
    });

    it('gives an unclassifiable marker no invented key', async () => {
      await createMeal({ ingredientCodes: ['2', '9901'] });

      const meal = (await fetchMeals())[0]!;

      expect(meal['traits']).toEqual([]);
      expect(meal['allergens']).toEqual([]);
      expect(meal['markers']).toHaveLength(2);
    });

    it('takes the sprint menu from the plan entry', async () => {
      await createMeal({ isSprint: true, ingredientCodes: [] });

      const meal = (await fetchMeals())[0]!;

      expect(meal['traits']).toEqual(['sprint']);
    });

    it('orders the keys by the published taxonomy, not by the source', async () => {
      // Same dish, codes listed the other way round.
      await createMeal({ ingredientCodes: ['G2', 'A1'] });

      const meal = (await fetchMeals())[0]!;

      expect(meal['allergens']).toEqual(['gluten', 'gluten_wheat', 'nuts', 'nuts_almond']);
    });
  });

  describe('freshness metadata', () => {
    /** One audit row; `hoursAgo` decides how old the run is. */
    async function recordRun(
      status: string,
      hoursAgo: number,
      finished = true,
    ): Promise<Date | null> {
      const at = new Date(Date.now() - hoursAgo * 3_600_000);
      await prisma.syncRun.create({
        data: {
          canteenId,
          status,
          startedAt: at,
          finishedAt: finished ? at : null,
        },
      });
      return finished ? at : null;
    }

    async function freshness() {
      const response = await request(app.getHttpServer()).get('/v1/canteens').expect(200);
      const body = response.body as {
        data: Array<{ slug: string; lastSuccessfulSyncAt: string | null; dataStale: boolean }>;
      };
      return body.data.find((entry) => entry.slug === 'koethen-fasanerieallee')!;
    }

    it('reports the newest successful run out of a long history', async () => {
      // The audit trail grows for as long as the worker runs, so the answer
      // must not depend on how many rows have accumulated — nor on the order
      // they were written in.
      for (let hoursAgo = 200; hoursAgo >= 2; hoursAgo -= 2) {
        await recordRun('success', hoursAgo);
      }
      const newest = await recordRun('success', 1);
      // Written last, but older: insertion order must not win.
      await recordRun('success', 150);

      expect((await freshness()).lastSuccessfulSyncAt).toBe(newest!.toISOString());
    });

    it('ignores runs that failed, came back empty or never finished', async () => {
      const newest = await recordRun('success', 10);
      await recordRun('failed', 1);
      await recordRun('empty', 2);
      await recordRun('running', 3, false);

      const entry = await freshness();
      expect(entry.lastSuccessfulSyncAt).toBe(newest!.toISOString());
      // 10h against the 180min default: honestly reported as stale.
      expect(entry.dataStale).toBe(true);
    });

    it('reports a canteen that never synchronised successfully as stale', async () => {
      await recordRun('failed', 1);

      const entry = await freshness();
      expect(entry.lastSuccessfulSyncAt).toBeNull();
      expect(entry.dataStale).toBe(true);
    });
  });

  it('serves every price group the source provided', async () => {
    await createMeal();

    const meal = (await fetchMeals())[0]!;

    expect(meal['prices']).toEqual([
      { group: 'student', label: 'Studierende', amount: '1.95', currency: 'EUR' },
    ]);
  });

  /**
   * The route promises: "every day in the requested range is present, so the
   * client can tell a genuinely empty day apart from a loading error"
   * (canteen.service.ts). A day the calendar does not have used to slip past
   * validation, shift forward, invert the interval and produce `days: []` —
   * exactly the state that promise rules out, answered with a 200.
   */
  describe('impossible dates', () => {
    it('refuses a day the calendar does not have instead of answering an empty range', async () => {
      await createMeal();

      const response = await request(app.getHttpServer())
        .get('/v1/canteens/koethen-fasanerieallee/menu?from=2026-02-30&to=2026-03-01')
        .expect(400);

      const body = response.body as { error: { code: string; details?: string[] } };
      expect(body.error.code).toBe('VALIDATION_FAILED');
      expect(body.error.details?.join(' ')).toContain('must be a valid date');
    });

    it('still answers a real range with one entry per requested day', async () => {
      await createMeal();

      const response = await request(app.getHttpServer())
        .get(`/v1/canteens/koethen-fasanerieallee/menu?from=${DATE}&to=2026-07-22`)
        .expect(200);

      const body = response.body as {
        data: { days: Array<{ date: string }> };
        meta: { from: string; to: string };
      };
      expect(body.data.days.map((day) => day.date)).toEqual([
        '2026-07-20',
        '2026-07-21',
        '2026-07-22',
      ]);
      expect(body.meta.from).toBe('2026-07-20');
      expect(body.meta.to).toBe('2026-07-22');
    });
  });
});
