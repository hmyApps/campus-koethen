import { CAMPUS_SITES, CampusSite } from './canteens.config';
import { Inject, Injectable } from '@nestjs/common';
import { TtlCache } from '../../common/cache/ttl-cache';
import { ApiError } from '../../common/errors/api-error';
import { LocaleResolution } from '../../common/locale/locale';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { classifyMeal } from './meal-semantics';
import { PRICE_GROUP_LABELS, PriceGroup } from './meine-mensa.schema';
import {
  CanteenDayDto,
  CanteenListItemDto,
  CanteenMenuDto,
  MealDto,
  MealMarkerDto,
  MealPriceDto,
} from './canteen.types';

/**
 * Read model for /v1/canteens*.
 *
 * Localisation rule for this module, and the reason it differs from news:
 * the upstream source is German-only. Dish names, subtitles, extras and
 * ingredient labels are therefore ALWAYS served as the original German text and
 * marked with `sourceLanguage: "de"`. Nothing here is machine-translated.
 *
 * API-owned strings — canteen names and price group labels — are genuinely
 * bilingual.
 */

const PRICE_GROUP_ORDER: PriceGroup[] = ['student', 'employee', 'guest'];

/**
 * Published order as a lookup, so the price comparator does not scan the list
 * for every comparison of every dish.
 */
const PRICE_GROUP_RANK = new Map<string, number>(
  PRICE_GROUP_ORDER.map((group, index) => [group, index]),
);

/** A group the published order does not name sorts after the ones it does. */
function priceGroupRank(group: string): number {
  return PRICE_GROUP_RANK.get(group) ?? PRICE_GROUP_ORDER.length;
}

/**
 * One stored price row, as the price lookup returns it.
 *
 * `amount` is a Prisma `Decimal`, exactly as it is through the typed client:
 * the driver adapter maps `numeric` to `Decimal` for a raw query too, so no
 * money value passes through a float on this path either.
 */
interface StoredMealPrice {
  mealId: string;
  group: string;
  amount: Prisma.Decimal;
}

/**
 * Joins ingredient codes into a stable lookup key.
 *
 * `\u0000` cannot occur inside a source code, so two different code lists can
 * never collapse onto one key.
 */
function codesKey(codes: readonly string[]): string {
  return codes.join('\u0000');
}

/**
 * How long a mapped menu is reused.
 *
 * The data behind it moves at most every couple of hours — `CANTEEN_SYNC_CRON`
 * runs every second hour by default — so half a minute is roughly 240 times
 * shorter than the interval that can change the answer at all. It matches the TTL the
 * news feed already uses, where the same reasoning is written out.
 *
 * Deliberately NOT covered by this: `lastSuccessfulSyncAt` and `dataStale`.
 * Both are answers about the clock rather than about the menu and are read
 * fresh on every request, so the freshness a client is shown stays exact and
 * this stays a pure performance measure.
 */
const MENU_CACHE_TTL_MS = 30_000;

/** A stored site key as a known site; anything unexpected reads as Köthen. */
function toSite(value: string): CampusSite {
  return (CAMPUS_SITES as readonly string[]).includes(value) ? (value as CampusSite) : 'koethen';
}

@Injectable()
export class CanteenService {
  // Ingredient definitions are a small, rarely-changing dictionary (<100 entries)
  // seeded and updated during sync runs. Caching them avoids redundant DB reads on
  // every menu query.
  private readonly definitionsCache = new TtlCache<{
    definitionByCode: Map<string, { code: string; labelDe: string; kind: string }>;
    labelByCode: Map<string, string>;
  }>(300_000, 1);

  /**
   * The mapped menu, per canteen, locale and date range.
   *
   * This is the most expensive read model in the API and was the only one still
   * rebuilt from the database on every single request — news, events, channels,
   * tags, contact areas, the contact search index and the room catalogue all
   * already have a short TTL. The key is derived from validated, bounded input
   * (`from`/`to` span at most 31 days), and the cache's own capacity bound is
   * what keeps a key that comes from a query string from deciding how much
   * memory this process holds.
   */
  private readonly menuDaysCache = new TtlCache<CanteenDayDto[]>(MENU_CACHE_TTL_MS);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  private async getIngredientDictionaries(): Promise<{
    definitionByCode: Map<string, { code: string; labelDe: string; kind: string }>;
    labelByCode: Map<string, string>;
  }> {
    return this.definitionsCache.getOrSet('all', async () => {
      const rows = await this.prisma.ingredientDefinition.findMany();
      const definitionByCode = new Map(rows.map((d) => [d.code, d]));
      const labelByCode = new Map(rows.map((d) => [d.code, d.labelDe]));
      return { definitionByCode, labelByCode };
    });
  }

  private isStale(lastSuccessfulSyncAt: Date | null): boolean {
    if (!lastSuccessfulSyncAt) {
      return true;
    }
    const ageMinutes = (Date.now() - lastSuccessfulSyncAt.getTime()) / 60_000;
    return ageMinutes > this.env.CANTEEN_STALE_AFTER_MINUTES;
  }

  /**
   * Most recent successful sync per canteen, in one query and one row each.
   *
   * `sync_runs` is an append-only audit trail: the worker adds a row per
   * canteen every couple of hours, so it grows for as long as the service runs.
   * Reading the whole history and picking the newest per canteen in JavaScript
   * therefore made a request on the hot path cost more every week it was live.
   *
   * Raw SQL is deliberate here. Prisma's `distinct` is applied in the query
   * engine, not by the database — the SQL it emits still reads every matching
   * row — and a plain `DISTINCT ON` cannot use the
   * (canteenId, status, finishedAt) index either, because the ordering it needs
   * runs the other way on the last column. The lateral `LIMIT 1` per canteen is
   * what the index answers directly: one backward index-only scan per canteen,
   * independent of how much history exists.
   */
  private async lastSuccessfulByCanteen(canteenIds: string[]): Promise<Map<string, Date>> {
    if (canteenIds.length === 0) {
      return new Map();
    }

    const rows = await this.prisma.$queryRaw<Array<{ canteenId: string; finishedAt: Date }>>`
      SELECT c.id AS "canteenId", run."finishedAt"
      FROM unnest(${canteenIds}::text[]) AS c(id)
      JOIN LATERAL (
        SELECT s."finishedAt"
        FROM "sync_runs" s
        WHERE s."canteenId" = c.id
          AND s."status" = 'success'
          AND s."finishedAt" IS NOT NULL
        ORDER BY s."finishedAt" DESC
        LIMIT 1
      ) run ON TRUE
    `;

    const map = new Map<string, Date>();
    for (const row of rows) {
      if (row.canteenId && row.finishedAt) {
        map.set(row.canteenId, row.finishedAt);
      }
    }
    return map;
  }

  async listCanteens(locale: LocaleResolution): Promise<CanteenListItemDto[]> {
    const canteens = await this.prisma.canteen.findMany({
      where: { active: true },
      orderBy: [{ sortOrder: 'asc' }, { slug: 'asc' }],
      select: {
        id: true,
        slug: true,
        displayNameDe: true,
        displayNameEn: true,
        campusLabelDe: true,
        campusLabelEn: true,
        siteKey: true,
      },
    });

    const lastSync = await this.lastSuccessfulByCanteen(canteens.map((c) => c.id));

    return canteens.map((canteen) => {
      const syncedAt = lastSync.get(canteen.id) ?? null;
      return {
        slug: canteen.slug,
        displayName: locale.resolvedLocale === 'en' ? canteen.displayNameEn : canteen.displayNameDe,
        campusLabel: locale.resolvedLocale === 'en' ? canteen.campusLabelEn : canteen.campusLabelDe,
        site: toSite(canteen.siteKey),
        lastSuccessfulSyncAt: syncedAt ? syncedAt.toISOString() : null,
        dataStale: this.isStale(syncedAt),
      };
    });
  }

  async getMenu(
    locale: LocaleResolution,
    slug: string,
    range: { from: string; to: string },
  ): Promise<{
    menu: CanteenMenuDto;
    lastSuccessfulSyncAt: string | null;
    dataStale: boolean;
  }> {
    const canteen = await this.prisma.canteen.findFirst({
      where: { slug, active: true },
      select: {
        id: true,
        slug: true,
        displayNameDe: true,
        displayNameEn: true,
        campusLabelDe: true,
        campusLabelEn: true,
        siteKey: true,
      },
    });
    if (!canteen) {
      throw new ApiError('CANTEEN_NOT_FOUND', locale.resolvedLocale);
    }

    // The mapped days are cacheable; the freshness figures below are not, so
    // they are read alongside rather than inside.
    const [days, syncByCanteen] = await Promise.all([
      this.menuDaysCache.getOrSet(
        `${canteen.id}|${locale.resolvedLocale}|${range.from}|${range.to}`,
        () => this.buildDays(canteen.id, locale, range),
      ),
      this.lastSuccessfulByCanteen([canteen.id]),
    ]);

    const syncedAt = syncByCanteen.get(canteen.id) ?? null;

    return {
      menu: {
        canteen: {
          slug: canteen.slug,
          displayName:
            locale.resolvedLocale === 'en' ? canteen.displayNameEn : canteen.displayNameDe,
          campusLabel:
            locale.resolvedLocale === 'en' ? canteen.campusLabelEn : canteen.campusLabelDe,
          site: toSite(canteen.siteKey),
        },
        days,
      },
      lastSuccessfulSyncAt: syncedAt ? syncedAt.toISOString() : null,
      dataStale: this.isStale(syncedAt),
    };
  }

  /**
   * The stored prices of a set of dishes, grouped by dish.
   *
   * Raw SQL is deliberate, for the same reason it is in the freshness lookup:
   * the statement Prisma would emit is the wrong shape, not merely a slower
   * one. Reading `prices` as a nested relation produces
   * `WHERE "mealId" IN ($1, …, $n)` with one bind parameter per dish, and a
   * fortnight of one canteen is already 168 of them. That costs twice over.
   * PostgreSQL has to plan a differently sized statement for every distinct
   * range length, and for a list that long it stops considering the index at
   * all: measured on the reference dataset it read all 26 280 rows
   * sequentially, which is why this was the only server-side cost that grew
   * with the size of the answer.
   *
   * `= ANY($1::text[])` is a single parameter whose plan does not depend on how
   * many dishes are in it, and every column read here sits in the
   * (mealId, group, amount) index, so the lookup is answered as an index-only
   * scan. Same rows, same types, one query — the query count of the route is
   * unchanged.
   *
   * A dish the source never priced simply has no row here and keeps no price.
   * Nothing is defaulted, estimated or carried over from another group.
   */
  private async pricesByMeal(mealIds: string[]): Promise<Map<string, StoredMealPrice[]>> {
    const byMeal = new Map<string, StoredMealPrice[]>();
    if (mealIds.length === 0) {
      return byMeal;
    }

    const rows = await this.prisma.$queryRaw<StoredMealPrice[]>`
      SELECT p."mealId", p."group", p."amount"
      FROM "meal_prices" p
      WHERE p."mealId" = ANY(${mealIds}::text[])
    `;

    for (const row of rows) {
      const stored = byMeal.get(row.mealId);
      if (stored) {
        stored.push(row);
      } else {
        byMeal.set(row.mealId, [row]);
      }
    }
    return byMeal;
  }

  /**
   * The dishes of one canteen over one date range, mapped for delivery.
   *
   * Everything in here is a function of stored data alone — no clock, no
   * request — which is what makes it safe to reuse for a short while.
   */
  private async buildDays(
    canteenId: string,
    locale: LocaleResolution,
    range: { from: string; to: string },
  ): Promise<CanteenDayDto[]> {
    const [meals, { definitionByCode, labelByCode }] = await Promise.all([
      this.prisma.meal.findMany({
        where: {
          canteenId,
          date: {
            gte: new Date(`${range.from}T00:00:00.000Z`),
            lte: new Date(`${range.to}T00:00:00.000Z`),
          },
        },
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
        orderBy: [{ date: 'asc' }, { counterId: 'asc' }, { name: 'asc' }],
      }),
      this.getIngredientDictionaries(),
    ]);

    const pricesByMeal = await this.pricesByMeal(meals.map((meal) => meal.id));

    // Every day in the requested range is present, so the client can tell a
    // genuinely empty day apart from a loading error.
    const byDate = new Map<string, MealDto[]>();
    for (
      let cursor = Date.parse(`${range.from}T00:00:00Z`);
      cursor <= Date.parse(`${range.to}T00:00:00Z`);
      cursor += 86_400_000
    ) {
      byDate.set(new Date(cursor).toISOString().slice(0, 10), []);
    }

    /**
     * Per-response memos for the three derivations that repeat across a menu.
     *
     * A month of one canteen is well over a thousand rows, but a canteen's
     * ingredient vocabulary is a few dozen codes and the range covers a few
     * dozen days. Marker lists, semantics and the calendar-day string were
     * being rebuilt for every single row, which is what made this the most
     * expensive route of the API — the database side of it takes about 2 ms.
     *
     * The memos live for one response, so a sync that lands between two
     * requests is picked up as it always was.
     *
     * The marker, trait and allergen arrays are SHARED between the dishes that
     * carry the same codes. That is sound here and nowhere else in this file:
     * these values go straight into `res.json()` and nothing on the request
     * path mutates a DTO after it is built.
     */
    const markersByCodes = new Map<string, MealMarkerDto[]>();
    const semanticsByCodes = new Map<string, ReturnType<typeof classifyMeal>>();
    const dateByTime = new Map<number, string>();

    for (const meal of meals) {
      const time = meal.date.getTime();
      let date = dateByTime.get(time);
      if (date === undefined) {
        date = meal.date.toISOString().slice(0, 10);
        dateByTime.set(time, date);
      }

      const codes = codesKey(meal.ingredientCodes);

      let markers = markersByCodes.get(codes);
      if (markers === undefined) {
        markers = meal.ingredientCodes.map((code) => {
          const definition = definitionByCode.get(code);
          return {
            code,
            // German label from the source; a code with no definition still
            // renders as the raw code instead of being silently dropped.
            label: definition?.labelDe ?? code,
            kind: definition?.kind === 'marker' ? 'marker' : 'ingredient',
          };
        });
        markersByCodes.set(codes, markers);
      }

      const prices: MealPriceDto[] = (pricesByMeal.get(meal.id) ?? [])
        .map((price) => ({
          group: price.group as PriceGroup,
          label:
            PRICE_GROUP_LABELS[price.group as PriceGroup]?.[locale.resolvedLocale] ?? price.group,
          // Fixed scale so the client never has to guess; formatting is the
          // client's job, arithmetic never happens on this string. Formatted by
          // the Decimal itself: the column is Decimal(6,2), so going through
          // `Number()` first only added a conversion.
          amount: price.amount.toFixed(2),
          currency: 'EUR' as const,
        }))
        .sort((a, b) => priceGroupRank(a.group) - priceGroupRank(b.group));

      // `isSprint` is part of the key because it is part of the answer.
      const semanticsKey = `${meal.isSprint ? '1' : '0'}\u0000${codes}`;
      let semantics = semanticsByCodes.get(semanticsKey);
      if (semantics === undefined) {
        semantics = classifyMeal({
          ingredientCodes: meal.ingredientCodes,
          isSprint: meal.isSprint,
          labelByCode,
        });
        semanticsByCodes.set(semanticsKey, semantics);
      }

      byDate.get(date)?.push({
        id: String(meal.sourcePlanId),
        name: meal.name,
        subtitle: meal.subtitle,
        // Honest signal: this text was not translated.
        sourceLanguage: 'de',
        counterId: meal.counterId,
        isSprint: meal.isSprint,
        extras: meal.extras,
        markers,
        traits: semantics.traits,
        allergens: semantics.allergens,
        prices,
      });
    }

    return [...byDate.entries()].map(([date, dayMeals]) => ({ date, meals: dayMeals }));
  }
}
