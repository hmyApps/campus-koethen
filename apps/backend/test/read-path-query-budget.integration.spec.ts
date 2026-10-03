import { INestApplication, VersioningType } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AllExceptionsFilter } from '../src/common/filters/all-exceptions.filter';
import { PrismaClient } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';
import { ENV } from '../src/config/app-config.module';
import { Env } from '../src/config/env.schema';
import { PrismaPg } from '@prisma/adapter-pg';
import { createTestPrisma, resetDatabase } from './helpers/database';

// Booting Nest against a real database plus two seeded windows exceeds Jest's
// 5s default on a shared runner.
jest.setTimeout(120_000);

/**
 * The query budget of the read paths, asserted on the route the app calls.
 *
 * `docs/performance-baseline.md` §6.1(c) makes the query count per request a
 * fixed contract — "jede Erhöhung gilt als Defekt" — because a count that
 * grows with the size of the answer is the definition of an N+1. Until now
 * nothing enforced it. The only evidence was a one-off run of
 * `scripts/perf/measure-queries.mjs`, which needs a seeded profile, a
 * container and a running API, and therefore cannot be a gate.
 *
 * `read-path-scaling.integration.spec.ts` is the sibling of this file and
 * guards the query *plan*. It cannot guard the query *count* or the query
 * *shape*, because it EXPLAINs SQL constants copied into the test rather than
 * whatever the service actually emits: reverting `CanteenService.pricesByMeal`
 * to a Prisma nested relation leaves it fully green. This file closes exactly
 * that gap by observing the statements a real HTTP request produces.
 *
 * What is asserted is a PROPERTY, not a magic number:
 *
 *   - Doubling the requested range must not change the number of statements.
 *     A number would have to be revised whenever a legitimate query is added;
 *     the property stays true for as long as the design is right, and it is
 *     the thing §7.1 actually established.
 *   - The price lookup must stay a single array parameter. `= ANY($1)` plans
 *     independently of how many dishes are asked for; `IN ($1 … $n)` is a
 *     different statement for every range length and was measured (§13.3) to
 *     fall back to a sequential scan over the whole price table.
 *
 * Instrumentation note: unlike the harness in §11, which observes PostgreSQL's
 * own statement log, this test listens to the client. That is a deliberate
 * trade — it needs no container, no log parsing and no seeded profile, so it
 * can run in CI on every merge request, which is the entire point of a gate.
 */

describe('query budget of the canteen menu read path (integration)', () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let recorded: string[] = [];
  let recording = false;
  /** The overridden client, kept so it can be disconnected with the app. */
  let observed: PrismaClient | undefined;

  const SLUG = 'budget-canteen';
  /** Two windows over the same seeded data. The second asks for twice as much. */
  const FROM = '2026-03-02';
  const TO_WARMUP = '2026-03-03';
  const TO_7D = '2026-03-08';
  const TO_14D = '2026-03-15';

  beforeAll(async () => {
    prisma = createTestPrisma();
    await prisma.$connect();
    await seed();

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useFactory({
        inject: [ENV],
        factory: (env: Env) => {
          const client = new PrismaClient({
            adapter: new PrismaPg({ connectionString: env.DATABASE_URL }),
            log: [{ emit: 'event', level: 'query' }],
          }) as unknown as PrismaService & {
            $on: (event: 'query', cb: (e: { query: string }) => void) => void;
            ping: () => Promise<void>;
          };
          client.$on('query', (event) => {
            if (recording) recorded.push(event.query);
          });
          // The health module calls ping(); the plain client has no such method.
          client.ping = async (): Promise<void> => {
            await (client as unknown as PrismaClient).$queryRaw`SELECT 1`;
          };
          observed = client;
          return client;
        },
      })
      .compile();

    app = moduleRef.createNestApplication({ logger: false });
    app.enableVersioning({ type: VersioningType.URI, prefix: 'v' });
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
    // Nest does not run onModuleDestroy for the overridden provider, so this
    // pool has to be closed here or Jest keeps the process alive.
    await observed?.$disconnect();
    await prisma?.$disconnect();
  });

  /**
   * 12 dishes a day over 14 days with three price groups each — the shape of
   * the `realistic` profile, small enough to seed in a test. Enough dishes
   * that an `IN` list would be long, which is the case that regressed.
   */
  async function seed(): Promise<void> {
    await resetDatabase(prisma);

    const canteen = await prisma.canteen.create({
      data: {
        slug: SLUG,
        sourceLocationId: 4711,
        displayNameDe: 'Budget-Mensa',
        displayNameEn: 'Budget Canteen',
        campusLabelDe: 'Campus',
        campusLabelEn: 'Campus',
        sortOrder: 1,
        active: true,
      },
    });

    await prisma.ingredientDefinition.createMany({
      data: [
        { code: '52', labelDe: 'vegan', kind: 'ingredient' },
        { code: 'A1', labelDe: 'enthält Weizengluten', kind: 'ingredient' },
      ],
    });

    await prisma.syncRun.create({
      data: {
        source: 'budget',
        canteenId: canteen.id,
        startedAt: new Date('2026-03-01T05:00:00Z'),
        finishedAt: new Date('2026-03-01T05:01:00Z'),
        status: 'success',
        recordsReceived: 0,
        recordsUpserted: 0,
        recordsRejected: 0,
      },
    });

    for (let day = 0; day < 14; day += 1) {
      const date = new Date(Date.UTC(2026, 2, 2 + day));
      for (let dish = 0; dish < 12; dish += 1) {
        const meal = await prisma.meal.create({
          data: {
            source: 'budget',
            sourcePlanId: day * 100 + dish,
            canteenId: canteen.id,
            date,
            counterId: 1,
            isSprint: false,
            name: `Gericht ${day}-${dish}`,
            extras: [],
            ingredientCodes: ['52'],
          },
        });
        await prisma.mealPrice.createMany({
          data: [
            { mealId: meal.id, group: 'student', amount: '2.90' },
            { mealId: meal.id, group: 'employee', amount: '4.60' },
            { mealId: meal.id, group: 'guest', amount: '6.10' },
          ],
        });
      }
    }
  }

  async function statementsFor(to: string): Promise<string[]> {
    recorded = [];
    recording = true;
    await request(app.getHttpServer())
      .get(`/v1/canteens/${SLUG}/menu?locale=de&from=${FROM}&to=${to}`)
      .expect(200);
    recording = false;
    return [...recorded];
  }

  let sevenDays: string[];
  let fourteenDays: string[];

  beforeAll(async () => {
    // One discarded request first, over a range neither measurement uses. The
    // ingredient dictionary is loaded once per process and cached, so the very
    // first menu request of a process carries a statement no later one does —
    // precisely the difference that makes §7.1's "canteen-menu-7d: 4 queries"
    // disagree with the 5 a cold run reproducibly shows. Measuring after the
    // warm-up removes that one-off from both sides.
    //
    // The range has to differ, because the menu read model is cached per
    // `canteenId|locale|from|to` for 30 s: measuring the same window twice
    // would compare a cache miss against a cache hit and make the counts
    // trivially unequal. Both measured windows below are misses.
    await statementsFor(TO_WARMUP);
    sevenDays = await statementsFor(TO_7D);
    fourteenDays = await statementsFor(TO_14D);
  });

  it('asks the same number of queries for a fortnight as for a week', () => {
    // The single most important property of this read path, and the one §7.1
    // established by measurement: cost per request does not follow the size of
    // the answer. A count that grows here IS the N+1.
    expect(fourteenDays.length).toBe(sevenDays.length);
    // …and the request really did do the work, rather than being served from a
    // cache that would make any two counts trivially equal.
    expect(sevenDays.length).toBeGreaterThan(0);
  });

  it('returns twice the dishes, so the counts above were compared on real work', async () => {
    const week = await request(app.getHttpServer())
      .get(`/v1/canteens/${SLUG}/menu?locale=de&from=${FROM}&to=${TO_7D}`)
      .expect(200);
    const fortnight = await request(app.getHttpServer())
      .get(`/v1/canteens/${SLUG}/menu?locale=de&from=${FROM}&to=${TO_14D}`)
      .expect(200);
    const days = (body: { data: { days: unknown[] } }): number => body.data.days.length;
    expect(days(fortnight.body)).toBeGreaterThan(days(week.body));
  });

  it('looks the prices up once, with a single array parameter', () => {
    // Matches both the raw statement (`FROM "meal_prices"`) and the shape
    // Prisma emits for a model query (`FROM "public"."meal_prices"`), so a
    // revert to the ORM is caught by the assertion below rather than by this
    // filter silently finding nothing.
    const priceStatements = fourteenDays.filter((sql) =>
      /from\s+"?(public"\.")?meal_prices"?/i.test(sql),
    );
    expect(priceStatements).toHaveLength(1);

    const sql = priceStatements[0]!;
    // `= ANY($1)` plans identically whatever the range length is. An `IN` list
    // with one bind parameter per dish is a different statement for every
    // range and was measured (§13.3) to fall back to a sequential scan over
    // the whole price table.
    expect(sql).toMatch(/=\s*ANY\s*\(\s*\$1/i);
    expect(sql).not.toMatch(/\bIN\s*\(\s*\$1\s*,\s*\$2/i);
  });

  it('reads the dishes of the range in one query', () => {
    const mealStatements = fourteenDays.filter((sql) => /from\s+"?(public"\.")?meals"?/i.test(sql));
    expect(mealStatements).toHaveLength(1);
  });

  it('answers canteen freshness from the lateral lookup, once', () => {
    const freshness = fourteenDays.filter((sql) => /from\s+"?(public"\.")?sync_runs"?/i.test(sql));
    expect(freshness).toHaveLength(1);
    expect(freshness[0]!).toMatch(/lateral/i);
  });
});
