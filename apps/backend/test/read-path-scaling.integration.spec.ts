import { PrismaClient } from '../src/generated/prisma/client';
import { createTestPrisma, resetDatabase } from './helpers/database';

// Two data sizes plus their EXPLAIN runs exceed Jest's 5s default.
jest.setTimeout(120_000);

/**
 * Cost contract of the read paths that sit on top of a table which grows for
 * as long as the service runs.
 *
 * `docs/performance-baseline.md` §7.2 established by measurement that these
 * paths do NOT get more expensive as history accumulates — the freshness
 * lookup held at three times the `sync_runs` history, and the menu's price
 * lookup was rewritten (LEVIORA-184) so that it stops scanning the whole
 * `meal_prices` table. Both are properties of the QUERY PLAN, and a plan is
 * exactly the kind of thing that flips back silently: drop an index, widen a
 * selected column, let an ORM inline a parameter list again, and the same code
 * starts reading the whole table without a single test going red.
 *
 * So this file asserts the cost, not the answer. Each path is measured twice
 * against a real PostgreSQL — once at a base size, once with the stored history
 * multiplied — and has to satisfy two things:
 *
 *   1. PostgreSQL answers it from an index, never with a sequential scan over
 *      the grown table.
 *   2. The buffers it touches stay flat. Growing the data several times over
 *      may cost a little more (a deeper index), but nothing close to the
 *      proportional growth a sequential scan would show.
 *
 * The statements below are the ones the services own as raw SQL, copied
 * verbatim, so there is no ORM in between that could emit something else.
 * `MAX_BUFFER_GROWTH` is deliberately far below the growth factor of the data:
 * a plan that regressed to a scan fails by a wide margin rather than by a
 * rounding error, which keeps this test a signal instead of a flake.
 */

/**
 * How much more the plan may read when the data multiplies.
 *
 * An index scan does get slightly more expensive as a table grows — the tree
 * gains a level — so the bound is not 1. It is far below `ROW_GROWTH`, which is
 * what a sequential scan would cost, so a plan that regressed to a scan fails by
 * a wide margin rather than by a rounding error.
 */
const MAX_BUFFER_GROWTH = 2;

/**
 * Base sizes, and how far the fixture grows them.
 *
 * The base is deliberately not tiny. On a table of a few thousand rows a
 * sequential scan really is the cheapest plan, and PostgreSQL is right to pick
 * one — measuring there would assert a preference the planner does not share
 * and would fail for the wrong reason. These sizes are the order of magnitude
 * of the `realistic` profile in `docs/performance-baseline.md` §3, where the
 * index is unambiguously the better answer.
 */
const BASE_MEALS = 8_000;
const BASE_RUNS = 300;
const BASE_EVENTS_PER_CALENDAR = 300;
const ROW_GROWTH = 4;
const RUN_GROWTH = 8;

/**
 * Days the stored events are spread over — lookback plus lookahead of the ICS
 * sync, as in the `realistic` profile. Growing the fixture makes those days
 * denser rather than longer, so the requested window keeps selecting a slice of
 * the table instead of all of it.
 */
const STORED_DAYS = 210;

/** `PUBLIC_CALENDAR_API_MAX_EVENTS` — the ceiling the aggregated route is capped at. */
const EVENT_CEILING = 2_000;

interface PlanNode {
  'Node Type': string;
  'Relation Name'?: string;
  'Index Name'?: string;
  'Actual Rows': number;
  'Actual Loops': number;
  'Shared Hit Blocks': number;
  'Shared Read Blocks': number;
  Plans?: PlanNode[];
}

function walk(node: PlanNode): PlanNode[] {
  return [node, ...(node.Plans ?? []).flatMap(walk)];
}

/** Blocks the whole plan touched. The root node's figure already includes its children. */
function blocksTouched(root: PlanNode): number {
  return root['Shared Hit Blocks'] + root['Shared Read Blocks'];
}

function sequentiallyScanned(root: PlanNode, relation: string): boolean {
  return walk(root).some(
    (node) => node['Node Type'] === 'Seq Scan' && node['Relation Name'] === relation,
  );
}

/**
 * Index names the plan used to reach one relation.
 *
 * The relation has to be inherited while descending rather than read off the
 * node itself: PostgreSQL names the table on a `Bitmap Heap Scan` but not on
 * the `Bitmap Index Scan` underneath it, which is the node that names the
 * index. Matching only on nodes that carry both would report "no index used"
 * for a plan that is entirely index-driven.
 */
function indexesUsed(root: PlanNode, relation: string): string[] {
  const found: string[] = [];
  const visit = (node: PlanNode, inherited: string | undefined): void => {
    const current = node['Relation Name'] ?? inherited;
    if (current === relation && node['Index Name']) {
      found.push(node['Index Name']);
    }
    for (const child of node.Plans ?? []) {
      visit(child, current);
    }
  };
  visit(root, undefined);
  return found;
}

describe('read paths that must not grow with stored history (integration)', () => {
  let prisma: PrismaClient;

  const CANTEEN_IDS = ['scaling-canteen-1', 'scaling-canteen-2'];
  const CALENDAR_COUNT = 12;
  /** Dishes the menu lookup asks for — a fortnight of one canteen, as measured. */
  const LOOKED_UP_MEALS = 168;

  async function explain(sql: string, params: unknown[]): Promise<PlanNode> {
    const rows = await prisma.$queryRawUnsafe<Array<{ 'QUERY PLAN': Array<{ Plan: PlanNode }> }>>(
      `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${sql}`,
      ...params,
    );
    return rows[0]!['QUERY PLAN'][0]!.Plan;
  }

  beforeAll(async () => {
    prisma = createTestPrisma();
    await prisma.$connect();
  });

  afterAll(async () => {
    await prisma?.$disconnect();
  });

  /**
   * Rows are inserted with `generate_series` rather than through the client:
   * this fixture is about table sizes, and tens of thousands of round trips
   * would dominate the runtime of the suite without changing a single plan.
   */
  async function seedBase(): Promise<void> {
    await resetDatabase(prisma);

    for (const [index, id] of CANTEEN_IDS.entries()) {
      await prisma.$executeRawUnsafe(
        `INSERT INTO canteens (id, slug, "sourceLocationId", "displayNameDe", "displayNameEn",
           "campusLabelDe", "campusLabelEn", "createdAt", "updatedAt")
         VALUES ($1, $2, $3, 'Mensa', 'Canteen', 'Campus', 'Campus', now(), now())`,
        id,
        `scaling-canteen-${index + 1}`,
        9000 + index,
      );
    }

    for (let index = 0; index < CALENDAR_COUNT; index += 1) {
      await prisma.$executeRawUnsafe(
        `INSERT INTO public_calendars (id, slug, "googleCalendarId", "nameDe", "colorHex",
           "sortOrder", "isActive", "operationalStatus", "createdAt", "updatedAt")
         VALUES ($1, $1, 'not-a-real-calendar', 'Kalender', '#123456', $2, true, 'ready', now(), now())`,
        `scaling-calendar-${index}`,
        index,
      );
    }

    await addMeals(1, BASE_MEALS);
    await addSyncRuns(1, BASE_RUNS);
    await addEvents(1, BASE_EVENTS_PER_CALENDAR);
    await analyse();
  }

  async function addMeals(from: number, to: number): Promise<void> {
    await prisma.$executeRawUnsafe(
      `INSERT INTO meals (id, source, "sourcePlanId", "canteenId", date, "counterId", "isSprint",
         name, extras, "ingredientCodes", "importedAt", "updatedAt")
       SELECT 'scaling-meal-' || g, 'scaling', g, $3, DATE '2026-03-02' + (g % 300), 1, false,
              'Gericht ' || g, '{}', '{}', now(), now()
       FROM generate_series($1::int, $2::int) g`,
      from,
      to,
      CANTEEN_IDS[0],
    );
    await prisma.$executeRawUnsafe(
      `INSERT INTO meal_prices (id, "mealId", "group", amount)
       SELECT 'scaling-price-' || g || '-' || grp, 'scaling-meal-' || g, grp, 3.50
       FROM generate_series($1::int, $2::int) g, unnest(ARRAY['student','employee','guest']) grp`,
      from,
      to,
    );
  }

  async function addSyncRuns(from: number, to: number): Promise<void> {
    for (const canteenId of CANTEEN_IDS) {
      await prisma.$executeRawUnsafe(
        `INSERT INTO sync_runs (id, source, "canteenId", "startedAt", "finishedAt", status,
           "recordsReceived", "recordsUpserted", "recordsRejected")
         SELECT 'scaling-run-' || $3 || '-' || g, 'scaling', $3,
                TIMESTAMPTZ '2020-01-01 00:00:00Z' + (g * INTERVAL '1 hour'),
                TIMESTAMPTZ '2020-01-01 00:05:00Z' + (g * INTERVAL '1 hour'),
                'success', 0, 0, 0
         FROM generate_series($1::int, $2::int) g`,
        from,
        to,
        canteenId,
      );
    }
  }

  async function addEvents(from: number, to: number): Promise<void> {
    for (let calendar = 0; calendar < CALENDAR_COUNT; calendar += 1) {
      await prisma.$executeRawUnsafe(
        `INSERT INTO public_calendar_events (id, "calendarId", "occurrenceKey", uid, title,
           "startsAt", "endsAt", "allDay", status, "importedAt", "lastSeenAt", "updatedAt")
         SELECT 'scaling-event-' || $3 || '-' || g, $4, 'occ-' || g, 'uid-' || g, 'Termin ' || g,
                TIMESTAMPTZ '2026-03-02 08:00:00Z' + ((g % ${STORED_DAYS}) * INTERVAL '1 day'),
                TIMESTAMPTZ '2026-03-02 09:00:00Z' + ((g % ${STORED_DAYS}) * INTERVAL '1 day'),
                false, 'confirmed', now(), now(), now()
         FROM generate_series($1::int, $2::int) g`,
        from,
        to,
        calendar,
        `scaling-calendar-${calendar}`,
      );
    }
  }

  /**
   * Statistics AND the visibility map, not statistics alone.
   *
   * Without fresh statistics the second measurement would be planned against
   * the first size, which is precisely the comparison this test is making. And
   * without a vacuum an index-only scan is not available at all — PostgreSQL
   * cannot skip the heap for rows it does not know to be visible to everyone,
   * so a freshly bulk-loaded table would be judged on a plan no running system
   * ever uses. Autovacuum does this continuously in operation; here it has to
   * be asked for, because the fixture is seconds old.
   */
  async function analyse(): Promise<void> {
    await prisma.$executeRawUnsafe(
      'VACUUM (ANALYZE) meals, meal_prices, sync_runs, public_calendar_events, public_calendars, canteens',
    );
  }

  /** Copied verbatim from CanteenService.lastSuccessfulByCanteen. */
  const FRESHNESS_SQL = `
    SELECT c.id AS "canteenId", run."finishedAt"
    FROM unnest($1::text[]) AS c(id)
    JOIN LATERAL (
      SELECT s."finishedAt"
      FROM "sync_runs" s
      WHERE s."canteenId" = c.id
        AND s."status" = 'success'
        AND s."finishedAt" IS NOT NULL
      ORDER BY s."finishedAt" DESC
      LIMIT 1
    ) run ON TRUE`;

  /** Copied verbatim from CanteenService.pricesByMeal. */
  const PRICES_SQL = `
    SELECT p."mealId", p."group", p."amount"
    FROM "meal_prices" p
    WHERE p."mealId" = ANY($1::text[])`;

  /**
   * The aggregated-events read of PublicCalendarService, in the shape Prisma
   * emits for it: the selected calendars, the range on both ends, the
   * deterministic ordering and the `PUBLIC_CALENDAR_API_MAX_EVENTS` ceiling as
   * a LIMIT. §8.3 of the baseline puts no work on this route; what has to stay
   * true is that neither an index change nor a raised limit turns it into a
   * scan of the whole event table.
   */
  const AGGREGATED_EVENTS_SQL = `
    SELECT e."id", e."calendarId", e."title", e."startsAt", e."endsAt", e."allDay", e."status"
    FROM "public_calendar_events" e
    WHERE e."calendarId" = ANY($1::text[])
      AND e."startsAt" <= $2
      AND e."endsAt" >= $3
    ORDER BY e."startsAt" ASC, e."calendarId" ASC, e."id" ASC
    LIMIT $4`;

  const mealIds = Array.from({ length: LOOKED_UP_MEALS }, (_, i) => `scaling-meal-${i + 1}`);
  const calendarIds = Array.from({ length: CALENDAR_COUNT }, (_, i) => `scaling-calendar-${i}`);
  const rangeFrom = new Date('2026-03-02T00:00:00.000Z');
  const rangeTo = new Date('2026-04-01T00:00:00.000Z');

  interface Measurement {
    base: PlanNode;
    grown: PlanNode;
  }

  let freshness: Measurement;
  let prices: Measurement;
  let events: Measurement;

  beforeAll(async () => {
    await seedBase();

    const baseFreshness = await explain(FRESHNESS_SQL, [CANTEEN_IDS]);
    const basePrices = await explain(PRICES_SQL, [mealIds]);
    const baseEvents = await explain(AGGREGATED_EVENTS_SQL, [
      calendarIds,
      rangeTo,
      rangeFrom,
      EVENT_CEILING,
    ]);

    // Eight times the run history, four times the dishes and their prices, four
    // times the stored events — the same questions, asked of much more data.
    await addSyncRuns(BASE_RUNS + 1, BASE_RUNS * RUN_GROWTH);
    await addMeals(BASE_MEALS + 1, BASE_MEALS * ROW_GROWTH);
    await addEvents(BASE_EVENTS_PER_CALENDAR + 1, BASE_EVENTS_PER_CALENDAR * ROW_GROWTH);
    await analyse();

    freshness = { base: baseFreshness, grown: await explain(FRESHNESS_SQL, [CANTEEN_IDS]) };
    prices = { base: basePrices, grown: await explain(PRICES_SQL, [mealIds]) };
    events = {
      base: baseEvents,
      grown: await explain(AGGREGATED_EVENTS_SQL, [calendarIds, rangeTo, rangeFrom, EVENT_CEILING]),
    };
  });

  describe('freshness of a canteen (sync_runs, append-only)', () => {
    it('reads one row per canteen however long the history is', () => {
      for (const plan of [freshness.base, freshness.grown]) {
        const lateral = walk(plan).filter(
          (node) => node['Relation Name'] === 'sync_runs' && node['Actual Loops'] > 0,
        );
        expect(lateral.length).toBeGreaterThan(0);
        for (const node of lateral) {
          // One row per canteen — the LIMIT 1 is answered by the index, not by
          // reading a history and discarding it.
          expect(node['Actual Rows'] / node['Actual Loops']).toBeLessThanOrEqual(1);
        }
      }
    });

    it('never scans the run history', () => {
      expect(sequentiallyScanned(freshness.base, 'sync_runs')).toBe(false);
      expect(sequentiallyScanned(freshness.grown, 'sync_runs')).toBe(false);
      expect(indexesUsed(freshness.grown, 'sync_runs').length).toBeGreaterThan(0);
    });

    it('does not read more as the history grows', () => {
      expect(blocksTouched(freshness.grown)).toBeLessThanOrEqual(
        blocksTouched(freshness.base) * MAX_BUFFER_GROWTH,
      );
    });
  });

  describe('prices of a menu range (meal_prices)', () => {
    it('answers the lookup from the covering index instead of scanning the table', () => {
      expect(sequentiallyScanned(prices.base, 'meal_prices')).toBe(false);
      expect(sequentiallyScanned(prices.grown, 'meal_prices')).toBe(false);
      expect(indexesUsed(prices.grown, 'meal_prices')).toContain(
        'meal_prices_mealId_group_amount_idx',
      );
    });

    it('does not read more as the table grows', () => {
      expect(blocksTouched(prices.grown)).toBeLessThanOrEqual(
        blocksTouched(prices.base) * MAX_BUFFER_GROWTH,
      );
    });
  });

  describe('aggregated calendar events (public_calendar_events)', () => {
    it('answers the range from an index instead of scanning the event table', () => {
      expect(sequentiallyScanned(events.base, 'public_calendar_events')).toBe(false);
      expect(sequentiallyScanned(events.grown, 'public_calendar_events')).toBe(false);
      expect(indexesUsed(events.grown, 'public_calendar_events').length).toBeGreaterThan(0);
    });

    it('stays bounded by the ceiling rather than by the stored volume', () => {
      // This route is the one that legitimately grows with its payload —
      // §7.2 of the baseline records exactly that — so what is asserted here is
      // the ceiling, not flat cost: however many events are stored, the answer
      // stops at PUBLIC_CALENDAR_API_MAX_EVENTS and the cut stays visible as
      // `meta.truncated` (covered in public-calendar-sync.integration.spec.ts).
      expect(events.base['Actual Rows']).toBeLessThanOrEqual(EVENT_CEILING);
      expect(events.grown['Actual Rows']).toBeLessThanOrEqual(EVENT_CEILING);
      // …and the growth really was exercised: a ceiling nothing ever reaches
      // would make this test pass for no reason.
      expect(events.grown['Actual Rows']).toBeGreaterThan(events.base['Actual Rows']);
    });
  });
});
