import { Prisma } from '../../generated/prisma/client';
import { CanteenService } from './canteen.service';
import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { LocaleResolution } from '../../common/locale/locale';

/**
 * `$queryRaw` answers two different questions in this service — the freshness
 * of a canteen and the prices of a set of dishes — so the fake tells them apart
 * the way PostgreSQL does: by the statement it is handed.
 */
function fakeQueryRaw(answers: { sync?: unknown[]; prices?: unknown[] }) {
  return jest.fn((strings: TemplateStringsArray) =>
    Promise.resolve(
      strings.join('').includes('meal_prices') ? (answers.prices ?? []) : (answers.sync ?? []),
    ),
  );
}

/**
 * Cost contract of the freshness lookup.
 *
 * `sync_runs` is an append-only audit trail that grows for as long as the
 * worker runs, and `/v1/canteens` reads it on every request. Reading the whole
 * history and reducing it in JavaScript therefore got slower every week the
 * service stayed up, which is why the reduction has to happen in the database.
 * The behaviour itself is covered end to end against a real PostgreSQL in
 * test/canteen-api.integration.spec.ts.
 */
describe('CanteenService freshness lookup', () => {
  const de: LocaleResolution = { requestedLocale: 'de', resolvedLocale: 'de' };
  const env = { CANTEEN_STALE_AFTER_MINUTES: 180 } as Env;

  const canteenRow = {
    id: 'canteen-1',
    slug: 'koethen-fasanerieallee',
    displayNameDe: 'Mensa Köthen',
    displayNameEn: 'Köthen Canteen',
    campusLabelDe: 'Fasanerieallee',
    campusLabelEn: 'Fasanerieallee',
  };

  function makePrisma(finishedAt: Date) {
    return {
      canteen: { findMany: jest.fn().mockResolvedValue([canteenRow]) },
      syncRun: { findMany: jest.fn().mockResolvedValue([]) },
      $queryRaw: jest.fn().mockResolvedValue([{ canteenId: 'canteen-1', finishedAt }]),
    };
  }

  it('asks the database for one row per canteen instead of loading the run history', async () => {
    const finishedAt = new Date('2026-08-24T02:00:00.000Z');
    const prisma = makePrisma(finishedAt);
    const service = new CanteenService(prisma as unknown as PrismaService, env);

    const result = await service.listCanteens(de);

    expect(result[0]!.lastSuccessfulSyncAt).toBe(finishedAt.toISOString());
    expect(prisma.canteen.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        select: {
          id: true,
          slug: true,
          displayNameDe: true,
          displayNameEn: true,
          campusLabelDe: true,
          campusLabelEn: true,
        },
      }),
    );
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
    // The whole-history read is what this replaced; it must not come back.
    expect(prisma.syncRun.findMany).not.toHaveBeenCalled();
  });

  it('does not query at all when there is no active canteen', async () => {
    const prisma = makePrisma(new Date());
    prisma.canteen.findMany.mockResolvedValue([]);
    const service = new CanteenService(prisma as unknown as PrismaService, env);

    await expect(service.listCanteens(de)).resolves.toEqual([]);
    expect(prisma.$queryRaw).not.toHaveBeenCalled();
  });

  it('caches ingredient definitions across getMenu calls', async () => {
    const prisma = {
      canteen: { findFirst: jest.fn().mockResolvedValue(canteenRow) },
      meal: { findMany: jest.fn().mockResolvedValue([]) },
      ingredientDefinition: {
        findMany: jest
          .fn()
          .mockResolvedValue([{ code: 'A1', labelDe: 'Gluten', kind: 'allergen' }]),
      },
      $queryRaw: jest.fn().mockResolvedValue([]),
    };
    const service = new CanteenService(prisma as unknown as PrismaService, env);
    const range = { from: '2026-08-24', to: '2026-08-25' };

    await service.getMenu(de, 'koethen-fasanerieallee', range);
    await service.getMenu(de, 'koethen-fasanerieallee', range);

    expect(prisma.ingredientDefinition.findMany).toHaveBeenCalledTimes(1);
    expect(prisma.meal.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        select: {
          id: true,
          sourcePlanId: true,
          date: true,
          counterId: true,
          isSprint: true,
          name: true,
          subtitle: true,
          extras: true,
          ingredientCodes: true,
        },
      }),
    );
  });
});

/**
 * Cache contract of the menu read model.
 *
 * The mapped days are reused for a short while; the freshness figures are not.
 * That split is the whole point: a client must never be told the data is fresher
 * or staler than it is, and the expensive part must not be rebuilt on every
 * request.
 */
describe('CanteenService menu cache', () => {
  const de: LocaleResolution = { requestedLocale: 'de', resolvedLocale: 'de' };
  const en: LocaleResolution = { requestedLocale: 'en', resolvedLocale: 'en' };
  const env = { CANTEEN_STALE_AFTER_MINUTES: 180 } as Env;

  const canteenRow = {
    id: 'canteen-1',
    slug: 'koethen-fasanerieallee',
    displayNameDe: 'Mensa Köthen',
    displayNameEn: 'Köthen Canteen',
    campusLabelDe: 'Fasanerieallee',
    campusLabelEn: 'Fasanerieallee',
  };

  function harness() {
    const mealFindMany = jest.fn().mockResolvedValue([]);
    const queryRaw = jest.fn().mockResolvedValue([]);
    const canteenFindFirst = jest.fn().mockResolvedValue(canteenRow);
    const prisma = {
      canteen: { findFirst: canteenFindFirst },
      meal: { findMany: mealFindMany },
      ingredientDefinition: { findMany: jest.fn().mockResolvedValue([]) },
      $queryRaw: queryRaw,
    };
    const service = new CanteenService(prisma as unknown as PrismaService, env);
    return { service, mealFindMany, queryRaw, canteenFindFirst };
  }

  const range = { from: '2026-08-24', to: '2026-08-25' };

  it('rebuilds the days once and reuses them for the next identical request', async () => {
    const { service, mealFindMany } = harness();

    const first = await service.getMenu(de, 'koethen-fasanerieallee', range);
    const second = await service.getMenu(de, 'koethen-fasanerieallee', range);

    expect(mealFindMany).toHaveBeenCalledTimes(1);
    expect(second.menu).toEqual(first.menu);
  });

  it('still reads the freshness figures on every request', async () => {
    const { service, mealFindMany, queryRaw } = harness();

    queryRaw.mockResolvedValueOnce([]);
    const stale = await service.getMenu(de, 'koethen-fasanerieallee', range);

    // The worker finishes a sync between the two requests.
    const finishedAt = new Date();
    queryRaw.mockResolvedValueOnce([{ canteenId: 'canteen-1', finishedAt }]);
    const fresh = await service.getMenu(de, 'koethen-fasanerieallee', range);

    // The expensive part was reused …
    expect(mealFindMany).toHaveBeenCalledTimes(1);
    // … but the freshness the client is told is the current one, not the cached one.
    expect(queryRaw).toHaveBeenCalledTimes(2);
    expect(stale.lastSuccessfulSyncAt).toBeNull();
    expect(stale.dataStale).toBe(true);
    expect(fresh.lastSuccessfulSyncAt).toBe(finishedAt.toISOString());
    expect(fresh.dataStale).toBe(false);
  });

  it('keeps a separate entry per locale and per date range', async () => {
    const { service, mealFindMany } = harness();

    await service.getMenu(de, 'koethen-fasanerieallee', range);
    await service.getMenu(en, 'koethen-fasanerieallee', range);
    await service.getMenu(de, 'koethen-fasanerieallee', { from: '2026-09-01', to: '2026-09-02' });
    await service.getMenu(de, 'koethen-fasanerieallee', range);

    // Locale decides the price labels and the range decides the days, so
    // neither may share an entry — and the repeat of the first still hits.
    expect(mealFindMany).toHaveBeenCalledTimes(3);
  });

  it('does not serve one canteen\u2019s menu for another', async () => {
    const { service, mealFindMany, canteenFindFirst } = harness();
    canteenFindFirst.mockImplementation(async ({ where }: { where: { slug: string } }) =>
      where.slug === 'koethen-fasanerieallee'
        ? canteenRow
        : { ...canteenRow, id: 'canteen-2', slug: where.slug },
    );

    await service.getMenu(de, 'koethen-fasanerieallee', range);
    await service.getMenu(de, 'koethen-lohmannstrasse', range);

    expect(mealFindMany).toHaveBeenCalledTimes(2);
    expect(mealFindMany.mock.calls[0]![0].where.canteenId).toBe('canteen-1');
    expect(mealFindMany.mock.calls[1]![0].where.canteenId).toBe('canteen-2');
  });
});

/**
 * Per-dish derivation of the menu.
 *
 * Marker lists, semantics and the calendar-day string repeat heavily across a
 * menu and are derived once per distinct input rather than once per row. What
 * must not change: two dishes that differ in ANY input still get their own
 * answer, and the answer is the same one the direct derivation gives.
 */
describe('CanteenService menu derivation', () => {
  const de: LocaleResolution = { requestedLocale: 'de', resolvedLocale: 'de' };
  const env = { CANTEEN_STALE_AFTER_MINUTES: 180 } as Env;

  const canteenRow = {
    id: 'canteen-1',
    slug: 'koethen-fasanerieallee',
    displayNameDe: 'Mensa Köthen',
    displayNameEn: 'Köthen Canteen',
    campusLabelDe: 'Fasanerieallee',
    campusLabelEn: 'Fasanerieallee',
  };

  const definitions = [
    { code: 'A1', labelDe: 'enthaelt Weizengluten', kind: 'ingredient' },
    { code: 'F', labelDe: 'enthaelt Milch', kind: 'ingredient' },
    { code: '52', labelDe: 'vegan', kind: 'marker' },
  ];

  /**
   * A stored dish plus the price rows the separate lookup would answer with.
   * `menuFor` splits the two apart again, because the service reads dishes and
   * prices in two separate queries.
   */
  function mealRow(overrides: {
    sourcePlanId: number;
    date: string;
    name: string;
    ingredientCodes: string[];
    isSprint?: boolean;
    prices?: Array<{ group: string; amount: string }>;
  }) {
    return {
      id: `meal-${overrides.sourcePlanId}`,
      sourcePlanId: overrides.sourcePlanId,
      date: new Date(`${overrides.date}T00:00:00.000Z`),
      counterId: 1,
      isSprint: overrides.isSprint ?? false,
      name: overrides.name,
      subtitle: null,
      extras: [],
      ingredientCodes: overrides.ingredientCodes,
      prices: (overrides.prices ?? [{ group: 'student', amount: '3.5' }]).map((price) => ({
        group: price.group,
        // The column is Decimal(6,2); `toFixed(2)` on it is what the read model
        // publishes, so the fake has to behave like one rather than like a number.
        amount: new Prisma.Decimal(price.amount),
      })),
    };
  }

  async function menuFor(meals: ReturnType<typeof mealRow>[], range: { from: string; to: string }) {
    const priceRows = meals.flatMap((meal) =>
      meal.prices.map((price) => ({ mealId: meal.id, ...price })),
    );
    const storedMeals = meals.map(({ prices: _prices, ...stored }) => stored);
    const prisma = {
      canteen: { findFirst: jest.fn().mockResolvedValue(canteenRow) },
      meal: { findMany: jest.fn().mockResolvedValue(storedMeals) },
      ingredientDefinition: { findMany: jest.fn().mockResolvedValue(definitions) },
      $queryRaw: fakeQueryRaw({ prices: priceRows }),
    };
    const service = new CanteenService(prisma as unknown as PrismaService, env);
    const { menu } = await service.getMenu(de, 'koethen-fasanerieallee', range);
    return menu;
  }

  it('gives dishes that share their codes the same markers, traits and allergens', async () => {
    const menu = await menuFor(
      [
        mealRow({
          sourcePlanId: 1,
          date: '2026-08-24',
          name: 'Erstes',
          ingredientCodes: ['A1', 'F'],
        }),
        mealRow({
          sourcePlanId: 2,
          date: '2026-08-25',
          name: 'Zweites',
          ingredientCodes: ['A1', 'F'],
        }),
      ],
      { from: '2026-08-24', to: '2026-08-25' },
    );

    const [first] = menu.days[0]!.meals;
    const [second] = menu.days[1]!.meals;

    expect(first!.markers).toEqual([
      { code: 'A1', label: 'enthaelt Weizengluten', kind: 'ingredient' },
      { code: 'F', label: 'enthaelt Milch', kind: 'ingredient' },
    ]);
    expect(second!.markers).toEqual(first!.markers);
    expect(first!.allergens).toEqual(['gluten', 'gluten_wheat', 'milk']);
    expect(second!.allergens).toEqual(first!.allergens);
  });

  it('keeps each dish\u2019s own code order in its markers', async () => {
    const menu = await menuFor(
      [
        mealRow({
          sourcePlanId: 1,
          date: '2026-08-24',
          name: 'Erstes',
          ingredientCodes: ['A1', 'F'],
        }),
        mealRow({
          sourcePlanId: 2,
          date: '2026-08-24',
          name: 'Zweites',
          ingredientCodes: ['F', 'A1'],
        }),
      ],
      { from: '2026-08-24', to: '2026-08-24' },
    );

    const [first, second] = menu.days[0]!.meals;
    expect(first!.markers.map((marker) => marker.code)).toEqual(['A1', 'F']);
    expect(second!.markers.map((marker) => marker.code)).toEqual(['F', 'A1']);
  });

  it('separates two dishes that share their codes but not their sprint flag', async () => {
    const menu = await menuFor(
      [
        mealRow({
          sourcePlanId: 1,
          date: '2026-08-24',
          name: 'Normal',
          ingredientCodes: ['52'],
          isSprint: false,
        }),
        mealRow({
          sourcePlanId: 2,
          date: '2026-08-24',
          name: 'Sprint',
          ingredientCodes: ['52'],
          isSprint: true,
        }),
      ],
      { from: '2026-08-24', to: '2026-08-24' },
    );

    const [normal, sprint] = menu.days[0]!.meals;
    expect(normal!.traits).toEqual(['vegan']);
    expect(sprint!.traits).toEqual(['vegan', 'sprint']);
  });

  it('files every dish under its own day', async () => {
    const menu = await menuFor(
      [
        mealRow({ sourcePlanId: 1, date: '2026-08-24', name: 'Montag', ingredientCodes: ['A1'] }),
        mealRow({ sourcePlanId: 2, date: '2026-08-25', name: 'Dienstag', ingredientCodes: ['A1'] }),
        mealRow({
          sourcePlanId: 3,
          date: '2026-08-25',
          name: 'Auch Dienstag',
          ingredientCodes: ['A1'],
        }),
      ],
      { from: '2026-08-24', to: '2026-08-26' },
    );

    expect(menu.days.map((day) => day.date)).toEqual(['2026-08-24', '2026-08-25', '2026-08-26']);
    expect(menu.days.map((day) => day.meals.map((meal) => meal.name))).toEqual([
      ['Montag'],
      ['Dienstag', 'Auch Dienstag'],
      [],
    ]);
  });

  it('publishes prices in the documented order with a fixed scale', async () => {
    const menu = await menuFor(
      [
        mealRow({
          sourcePlanId: 1,
          date: '2026-08-24',
          name: 'Mit Preisen',
          ingredientCodes: [],
          prices: [
            { group: 'guest', amount: '7' },
            { group: 'student', amount: '3.5' },
            { group: 'employee', amount: '5.05' },
          ],
        }),
      ],
      { from: '2026-08-24', to: '2026-08-24' },
    );

    expect(menu.days[0]!.meals[0]!.prices).toEqual([
      { group: 'student', label: 'Studierende', amount: '3.50', currency: 'EUR' },
      { group: 'employee', label: 'Mitarbeiter', amount: '5.05', currency: 'EUR' },
      { group: 'guest', label: 'Gäste', amount: '7.00', currency: 'EUR' },
    ]);
  });

  it('leaves a dish the source never priced without prices, rather than inventing one', async () => {
    const menu = await menuFor(
      [
        mealRow({
          sourcePlanId: 1,
          date: '2026-08-24',
          name: 'Ohne Preis',
          ingredientCodes: [],
          prices: [],
        }),
        mealRow({
          sourcePlanId: 2,
          date: '2026-08-24',
          name: 'Nur Studierende',
          ingredientCodes: [],
          prices: [{ group: 'student', amount: '3.5' }],
        }),
      ],
      { from: '2026-08-24', to: '2026-08-24' },
    );

    const [unpriced, partly] = menu.days[0]!.meals;
    expect(unpriced!.prices).toEqual([]);
    expect(partly!.prices.map((price) => price.group)).toEqual(['student']);
  });
});

/**
 * Cost contract of the price lookup.
 *
 * Prices are the only part of a menu that grows with the requested range, which
 * makes the SHAPE of the query that fetches them the thing that decides how the
 * route grows. Prisma's nested relation read emits one bind parameter per dish
 * — a fortnight of one canteen is already well over a hundred — and PostgreSQL
 * both re-plans a differently sized list every time and answers a list that
 * long with a sequential scan over the whole table.
 *
 * The lookup therefore has to leave as ONE array parameter, so that plan and
 * index stay the same whether the client asked for a day or a month. The
 * covering index that makes it an index-only scan is asserted against a real
 * PostgreSQL in test/read-path-scaling.integration.spec.ts; what is fixed here
 * is the statement the service sends.
 */
describe('CanteenService price lookup', () => {
  const de: LocaleResolution = { requestedLocale: 'de', resolvedLocale: 'de' };
  const env = { CANTEEN_STALE_AFTER_MINUTES: 180 } as Env;

  const canteenRow = {
    id: 'canteen-1',
    slug: 'koethen-fasanerieallee',
    displayNameDe: 'Mensa Köthen',
    displayNameEn: 'Köthen Canteen',
    campusLabelDe: 'Fasanerieallee',
    campusLabelEn: 'Fasanerieallee',
  };

  function harness(mealCount: number) {
    const meals = Array.from({ length: mealCount }, (_, index) => ({
      id: `meal-${index}`,
      sourcePlanId: index,
      date: new Date('2026-08-24T00:00:00.000Z'),
      counterId: 1,
      isSprint: false,
      name: `Gericht ${index}`,
      subtitle: null,
      extras: [],
      ingredientCodes: [],
    }));
    const queryRaw = fakeQueryRaw({ prices: [] });
    const prisma = {
      canteen: { findFirst: jest.fn().mockResolvedValue(canteenRow) },
      meal: { findMany: jest.fn().mockResolvedValue(meals) },
      ingredientDefinition: { findMany: jest.fn().mockResolvedValue([]) },
      $queryRaw: queryRaw,
    };
    return {
      service: new CanteenService(prisma as unknown as PrismaService, env),
      queryRaw,
      mealFindMany: prisma.meal.findMany,
      mealIds: meals.map((meal) => meal.id),
    };
  }

  function priceCall(queryRaw: ReturnType<typeof fakeQueryRaw>) {
    return queryRaw.mock.calls.find((call) => call[0].join('').includes('meal_prices'));
  }

  it('does not let Prisma load the prices as a nested relation', async () => {
    const { service, mealFindMany } = harness(3);

    await service.getMenu(de, 'koethen-fasanerieallee', { from: '2026-08-24', to: '2026-08-24' });

    const select = mealFindMany.mock.calls[0]![0].select as Record<string, unknown>;
    expect(select['prices']).toBeUndefined();
    expect(select['id']).toBe(true);
  });

  it('sends every dish of the range as a single array parameter', async () => {
    const { service, queryRaw, mealIds } = harness(150);

    await service.getMenu(de, 'koethen-fasanerieallee', { from: '2026-08-24', to: '2026-08-24' });

    const call = priceCall(queryRaw);
    expect(call).toBeDefined();
    const [strings, ...values] = call as [TemplateStringsArray, ...unknown[]];
    // One parameter, whatever the range holds — not one per dish.
    expect(values).toEqual([mealIds]);
    expect(strings.join('')).toContain('= ANY(');
    expect(strings.join('')).not.toContain(' IN (');
  });

  it('asks for nothing when the range holds no dish', async () => {
    const { service, queryRaw } = harness(0);

    await service.getMenu(de, 'koethen-fasanerieallee', { from: '2026-08-24', to: '2026-08-24' });

    // The freshness lookup still runs; the price lookup has nothing to ask for.
    expect(priceCall(queryRaw)).toBeUndefined();
  });
});
