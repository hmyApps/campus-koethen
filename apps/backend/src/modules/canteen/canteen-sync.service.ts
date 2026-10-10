import { Inject, Injectable, Logger } from '@nestjs/common';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { addCalendarDays, campusToday } from '../../common/time/campus-date';
import { CANTEENS, CanteenDefinition } from './canteens.config';
import { CanteenSourceError, MeineMensaClient } from './meine-mensa.client';
import { NormalizedMeal, normalizeDefinitions, normalizeEntry } from './meine-mensa.schema';

/**
 * Canteen synchronisation.
 *
 * THE governing rule of this file: a failed, invalid or unexpectedly empty
 * upstream response must NEVER remove data that is already stored. Stale but
 * real data beats an empty screen, and the user is told the data is stale via
 * `lastSuccessfulSyncAt` / `dataStale`.
 *
 * Concretely:
 *  - transport failure, timeout, malformed body -> record the failure, keep data
 *  - empty `data` array                          -> record `empty`, keep data
 *  - entries for a different location_id         -> reject those entries only
 *  - only a successful, non-empty response may delete anything, and then only
 *    within the date window that was actually confirmed by that response
 */

export type SyncStatus = 'success' | 'empty' | 'failed';

export interface SyncOutcome {
  canteenSlug: string;
  status: SyncStatus;
  recordsReceived: number;
  recordsUpserted: number;
  recordsRejected: number;
  recordsRemoved: number;
  errorMessage?: string;
}

@Injectable()
export class CanteenSyncService {
  private readonly logger = new Logger(CanteenSyncService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly client: MeineMensaClient,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /** Creates or updates the canteen rows from config. Safe to run repeatedly. */
  async seedCanteens(): Promise<number> {
    for (const canteen of CANTEENS) {
      await this.prisma.canteen.upsert({
        where: { slug: canteen.slug },
        create: {
          slug: canteen.slug,
          sourceLocationId: canteen.sourceLocationId,
          displayNameDe: canteen.displayNameDe,
          displayNameEn: canteen.displayNameEn,
          campusLabelDe: canteen.campusLabelDe,
          campusLabelEn: canteen.campusLabelEn,
          sortOrder: canteen.sortOrder,
          active: canteen.active,
        },
        update: {
          sourceLocationId: canteen.sourceLocationId,
          displayNameDe: canteen.displayNameDe,
          displayNameEn: canteen.displayNameEn,
          campusLabelDe: canteen.campusLabelDe,
          campusLabelEn: canteen.campusLabelEn,
          sortOrder: canteen.sortOrder,
          active: canteen.active,
        },
      });
    }
    return CANTEENS.length;
  }

  private static dateWindow(daysAhead: number, now = new Date()): { from: string; to: string } {
    const from = campusToday(now);
    return { from, to: addCalendarDays(from, daysAhead) };
  }

  async syncAll(): Promise<SyncOutcome[]> {
    await this.seedCanteens();
    const outcomes: SyncOutcome[] = [];

    for (const [index, canteen] of CANTEENS.filter((c) => c.active).entries()) {
      if (index > 0 && this.env.CANTEEN_REQUEST_SPACING_MS > 0) {
        // Be a polite client to a third-party service.
        await new Promise((resolve) => setTimeout(resolve, this.env.CANTEEN_REQUEST_SPACING_MS));
      }
      outcomes.push(await this.syncCanteen(canteen));
    }

    return outcomes;
  }

  async syncCanteen(canteen: CanteenDefinition): Promise<SyncOutcome> {
    const record = await this.prisma.canteen.findUnique({ where: { slug: canteen.slug } });
    if (!record) {
      throw new Error(`Canteen ${canteen.slug} is not seeded`);
    }

    const window = CanteenSyncService.dateWindow(this.env.CANTEEN_SYNC_DAYS_AHEAD);
    const run = await this.prisma.syncRun.create({
      data: { canteenId: record.id, status: 'running' },
    });

    const fail = async (message: string): Promise<SyncOutcome> => {
      await this.prisma.syncRun.update({
        where: { id: run.id },
        data: { status: 'failed', finishedAt: new Date(), errorMessage: message },
      });
      // Deliberately no delete: existing data survives the failure.
      this.logger.warn(`Sync failed for ${canteen.slug}: ${message}; existing data kept`);
      return {
        canteenSlug: canteen.slug,
        status: 'failed',
        recordsReceived: 0,
        recordsUpserted: 0,
        recordsRejected: 0,
        recordsRemoved: 0,
        errorMessage: message,
      };
    };

    let response;
    try {
      response = await this.client.fetchFoodPlans({
        locationId: canteen.sourceLocationId,
        from: window.from,
        to: window.to,
      });
    } catch (error) {
      const message =
        error instanceof CanteenSourceError
          ? `${error.kind}: ${error.message}`
          : 'unexpected source failure';
      return fail(message);
    }

    // Entries for another canteen are a genuine upstream anomaly. Drop them
    // rather than filing another canteen's menu under this one.
    const received = response.data.length;
    const placeholders = response.data
      .filter(
        (entry) =>
          entry.location_id === canteen.sourceLocationId && entry.food.name.trim().length === 0,
      )
      .map((entry) => ({ date: entry.date, sourcePlanId: entry.id }));
    const matching = response.data.filter(
      (entry) =>
        entry.location_id === canteen.sourceLocationId && entry.food.name.trim().length > 0,
    );
    const rejected = received - matching.length;
    if (rejected > 0) {
      this.logger.warn(
        `Rejected ${rejected} entr(ies) with another location_id or an empty food name for ${canteen.slug}`,
      );
    }

    if (matching.length === 0) {
      await this.prisma.syncRun.update({
        where: { id: run.id },
        data: {
          status: 'empty',
          finishedAt: new Date(),
          recordsReceived: received,
          recordsRejected: rejected,
          errorMessage: received > 0 ? 'no named entries matched the requested location' : null,
        },
      });
      // An empty answer is NOT a reason to wipe a valid menu.
      this.logger.warn(`Empty result for ${canteen.slug}; existing data kept`);
      return {
        canteenSlug: canteen.slug,
        status: 'empty',
        recordsReceived: received,
        recordsUpserted: 0,
        recordsRejected: rejected,
        recordsRemoved: 0,
      };
    }

    const meals = matching.map(normalizeEntry);
    const definitions = normalizeDefinitions(response.meta);

    let removed = 0;
    try {
      removed = await this.persist(record.id, meals, definitions, placeholders);
    } catch (error) {
      return fail(
        `persistence failed: ${error instanceof Error ? error.message : 'unknown error'}`,
      );
    }

    await this.prisma.syncRun.update({
      where: { id: run.id },
      data: {
        status: 'success',
        finishedAt: new Date(),
        recordsReceived: received,
        recordsUpserted: meals.length,
        recordsRejected: rejected,
      },
    });

    this.logger.log(
      `Synced ${canteen.slug}: ${meals.length} meal(s) upserted, ${rejected} rejected, ${removed} withdrawn`,
    );

    return {
      canteenSlug: canteen.slug,
      status: 'success',
      recordsReceived: received,
      recordsUpserted: meals.length,
      recordsRejected: rejected,
      recordsRemoved: removed,
    };
  }

  /**
   * Last one wins, exactly as the sequential write loop it replaces did.
   *
   * The source can legitimately publish the same key twice — a code that is
   * both an ingredient and a marker, or a repeated plan entry. Writing each
   * occurrence in turn made the last one the stored value; a batched write
   * would instead collide on the unique constraint, so the collapse has to
   * happen here.
   */
  private static lastPerKey<T, K>(items: T[], key: (item: T) => K): T[] {
    const byKey = new Map<K, T>();
    for (const item of items) {
      byKey.set(key(item), item);
    }
    return [...byKey.values()];
  }

  /** The columns one normalised dish maps to. Shared by the insert and the update. */
  private static mealData(canteenId: string, meal: NormalizedMeal) {
    return {
      source: 'meine-mensa',
      canteenId,
      date: new Date(`${meal.date}T00:00:00.000Z`),
      counterId: meal.counterId,
      isSprint: meal.isSprint,
      name: meal.name,
      subtitle: meal.subtitle,
      extras: meal.extras,
      ingredientCodes: meal.ingredientCodes,
      sourceFoodId: meal.sourceFoodId,
    };
  }

  private static listChanged(stored: string[], next: string[]): boolean {
    if (stored.length !== next.length) {
      return true;
    }
    return next.some((value, index) => stored[index] !== value);
  }

  /**
   * True when the response carries anything the stored dish does not already
   * say — including a different owner, because the upsert this replaces would
   * have taken such a row over.
   */
  private static mealChanged(
    stored: {
      source: string;
      canteenId: string;
      date: Date;
      counterId: number | null;
      isSprint: boolean;
      name: string;
      subtitle: string | null;
      extras: string[];
      ingredientCodes: string[];
      sourceFoodId: number | null;
    },
    next: NormalizedMeal,
    canteenId: string,
  ): boolean {
    return (
      stored.source !== 'meine-mensa' ||
      stored.canteenId !== canteenId ||
      stored.date.getTime() !== Date.parse(`${next.date}T00:00:00.000Z`) ||
      stored.counterId !== next.counterId ||
      stored.isSprint !== next.isSprint ||
      stored.name !== next.name ||
      stored.subtitle !== next.subtitle ||
      stored.sourceFoodId !== next.sourceFoodId ||
      CanteenSyncService.listChanged(stored.extras, next.extras) ||
      CanteenSyncService.listChanged(stored.ingredientCodes, next.ingredientCodes)
    );
  }

  /**
   * Compares stored prices against the normalised ones.
   *
   * Compared as Decimal, never as text: the column is Decimal(6,2), so a stored
   * 7.00 reads back as "7" while the source publishes "7.00". Comparing the
   * strings would report a change on every run.
   */
  private static pricesChanged(
    stored: Array<{ group: string; amount: Prisma.Decimal }>,
    next: NormalizedMeal['prices'],
  ): boolean {
    if (stored.length !== next.length) {
      return true;
    }
    const amountByGroup = new Map(stored.map((price) => [price.group, price.amount]));
    return next.some((price) => {
      const amount = amountByGroup.get(price.group);
      return amount === undefined || !amount.equals(price.amount);
    });
  }

  /**
   * Writes a confirmed, non-empty result in a single transaction.
   *
   * Upserts run on the stable `sourcePlanId`, so repeating an import updates
   * instead of duplicating. Removal is limited to the date range the response
   * actually covered: a dish withdrawn upstream disappears, while days outside
   * the confirmed window are left untouched.
   *
   * Everything that does not have to be written row by row is batched. A
   * fortnight of menus across several counters is a few hundred dishes, and
   * every extra round-trip is taken while the transaction holds its locks on
   * `meals` and `meal_prices`. The same per-row pattern is what pushed the
   * timetable import past Prisma's 5s interactive-transaction limit on real
   * data.
   */
  private async persist(
    canteenId: string,
    meals: NormalizedMeal[],
    definitions: Array<{ code: string; labelDe: string; kind: 'ingredient' | 'marker' }>,
    placeholders: Array<{ date: string; sourcePlanId: number }> = [],
  ): Promise<number> {
    const dates = [...new Set(meals.map((meal) => meal.date))].sort();
    const minDate = new Date(`${dates[0]!}T00:00:00.000Z`);
    const maxDate = new Date(`${dates[dates.length - 1]!}T00:00:00.000Z`);
    const deletionWindow: Prisma.DateTimeFilter = { gte: minDate, lte: maxDate };
    // A day with only unnamed placeholders is not confirmed. When a day also
    // has named dishes, preserve only the previous dish for each placeholder's
    // stable plan ID; unrelated dishes withdrawn upstream can then disappear.
    const confirmedDates = new Set(dates);
    const unconfirmedDates = new Set(
      placeholders.filter((entry) => !confirmedDates.has(entry.date)).map((entry) => entry.date),
    );
    if (unconfirmedDates.size > 0) {
      deletionWindow.notIn = [...unconfirmedDates].map((date) => new Date(`${date}T00:00:00.000Z`));
    }
    const keptIds = [
      ...new Set([
        ...meals.map((meal) => meal.sourcePlanId),
        ...placeholders.map((entry) => entry.sourcePlanId),
      ]),
    ];

    const uniqueDefinitions = CanteenSyncService.lastPerKey(
      definitions,
      (definition) => definition.code,
    );
    const uniqueMeals = CanteenSyncService.lastPerKey(meals, (meal) => meal.sourcePlanId);

    return this.prisma.$transaction(async (tx) => {
      // The dictionary is read once and only the rows that actually differ are
      // written. It is nearly static between imports, so the common case is a
      // single SELECT and no write at all instead of one upsert per code.
      const storedDefinitions = await tx.ingredientDefinition.findMany({
        where: { code: { in: uniqueDefinitions.map((definition) => definition.code) } },
        select: { code: true, labelDe: true, kind: true },
      });
      const definitionByCode = new Map(storedDefinitions.map((row) => [row.code, row]));

      const newDefinitions = uniqueDefinitions.filter(
        (definition) => !definitionByCode.has(definition.code),
      );
      const changedDefinitions = uniqueDefinitions.filter((definition) => {
        const stored = definitionByCode.get(definition.code);
        return (
          stored !== undefined &&
          (stored.labelDe !== definition.labelDe || stored.kind !== definition.kind)
        );
      });

      if (newDefinitions.length > 0) {
        // labelEn is never written here — no machine translation.
        await tx.ingredientDefinition.createMany({ data: newDefinitions });
      }
      for (const definition of changedDefinitions) {
        await tx.ingredientDefinition.update({
          where: { code: definition.code },
          data: { labelDe: definition.labelDe, kind: definition.kind },
        });
      }

      // The same read-then-diff the timetable and calendar imports use. The
      // source republishes the whole fortnight every two hours while the menu
      // itself barely moves, so the common case is: nothing to write at all.
      //
      // Deliberately NOT filtered by source or canteen. The upsert this
      // replaces matched on sourcePlanId alone and wrote `source` and
      // `canteenId` along with the rest, so a row belonging to another source
      // was taken over rather than ignored. Narrowing the read here would turn
      // that takeover into a unique-constraint violation.
      const storedMeals = await tx.meal.findMany({
        where: { sourcePlanId: { in: uniqueMeals.map((meal) => meal.sourcePlanId) } },
        select: {
          id: true,
          sourcePlanId: true,
          source: true,
          canteenId: true,
          date: true,
          counterId: true,
          isSprint: true,
          name: true,
          subtitle: true,
          extras: true,
          ingredientCodes: true,
          sourceFoodId: true,
          prices: { select: { group: true, amount: true } },
        },
      });
      const storedByPlanId = new Map(storedMeals.map((row) => [row.sourcePlanId, row]));

      const toCreate: NormalizedMeal[] = [];
      const toUpdate: Array<{ id: string; meal: NormalizedMeal }> = [];
      // Prices are replaced wholesale per meal, so only meals whose price set
      // actually differs need that replacement.
      const priceReplace: Array<{ id: string; meal: NormalizedMeal }> = [];

      for (const meal of uniqueMeals) {
        const row = storedByPlanId.get(meal.sourcePlanId);
        if (!row) {
          toCreate.push(meal);
          continue;
        }
        if (CanteenSyncService.mealChanged(row, meal, canteenId)) {
          toUpdate.push({ id: row.id, meal });
        }
        if (CanteenSyncService.pricesChanged(row.prices, meal.prices)) {
          priceReplace.push({ id: row.id, meal });
        }
      }

      const idBySourcePlanId = new Map<number, string>();
      if (toCreate.length > 0) {
        const created = await tx.meal.createManyAndReturn({
          data: toCreate.map((meal) => ({
            sourcePlanId: meal.sourcePlanId,
            ...CanteenSyncService.mealData(canteenId, meal),
          })),
          select: { id: true, sourcePlanId: true },
        });
        for (const row of created) {
          idBySourcePlanId.set(row.sourcePlanId, row.id);
        }
      }

      for (const { id, meal } of toUpdate) {
        await tx.meal.update({
          where: { id },
          data: CanteenSyncService.mealData(canteenId, meal),
        });
      }

      const priceRows: Array<{ mealId: string; group: string; amount: string }> = [];
      for (const { id, meal } of priceReplace) {
        for (const price of meal.prices) {
          priceRows.push({ mealId: id, group: price.group, amount: price.amount });
        }
      }
      for (const meal of toCreate) {
        const id = idBySourcePlanId.get(meal.sourcePlanId);
        if (id === undefined) {
          continue;
        }
        for (const price of meal.prices) {
          priceRows.push({ mealId: id, group: price.group, amount: price.amount });
        }
      }

      // A group removed upstream still disappears here rather than lingering
      // as a stale figure — but only the meals whose prices moved are touched.
      // A freshly created meal has no prices to clear.
      if (priceReplace.length > 0) {
        await tx.mealPrice.deleteMany({
          where: { mealId: { in: priceReplace.map((entry) => entry.id) } },
        });
      }
      if (priceRows.length > 0) {
        await tx.mealPrice.createMany({ data: priceRows });
      }

      const withdrawn = await tx.meal.deleteMany({
        where: {
          source: 'meine-mensa',
          canteenId,
          date: deletionWindow,
          sourcePlanId: { notIn: keptIds },
        },
      });

      return withdrawn.count;
    });
  }

  /** Most recent successful sync, or null if there has never been one. */
  async lastSuccessfulSyncAt(canteenId: string): Promise<Date | null> {
    const run = await this.prisma.syncRun.findFirst({
      where: { canteenId, status: 'success' },
      orderBy: { startedAt: 'desc' },
      select: { finishedAt: true },
    });
    return run?.finishedAt ?? null;
  }
}
