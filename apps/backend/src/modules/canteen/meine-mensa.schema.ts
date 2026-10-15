import { z } from 'zod';

/**
 * Explicit schema for the meine-mensa.de response.
 *
 * The upstream is a third party we do not control, so nothing is trusted:
 * every response is parsed before a single row is written. A shape change
 * upstream must surface as a clean validation failure that leaves the existing
 * data untouched — never as a partial or corrupted import.
 *
 * Observed quirks this schema encodes deliberately (see docs/data-sources.md):
 *  - codes in `food.ingredients` are STRINGS and mix the `meta.ingredients` and
 *    `meta.markers` namespaces
 *  - prices arrive as JSON numbers with varying precision (`7` for 7.00)
 *  - a price group can be absent; it must never be defaulted to 0
 *  - unpublished future rows can carry an empty dish name; the sync service
 *    rejects those placeholders without discarding valid meals in the response
 *  - `image_url` is present but is deliberately never persisted
 */

/**
 * Money is read as a number here because that is the wire format, then
 * immediately converted to a fixed-scale decimal STRING. It is never used in
 * float arithmetic.
 */
const price = z
  .number()
  .finite()
  .nonnegative()
  .max(1000)
  .transform((value) => value.toFixed(2));

const optionalPrice = price.nullish().transform((value) => value ?? null);

export const foodSchema = z.object({
  id: z.number().int().nullish(),
  name: z.string(),
  name_2: z.string().nullish(),
  /** Codes are strings, including the purely numeric ones. */
  ingredients: z.array(z.string()).nullish(),
  price_1: optionalPrice,
  price_2: optionalPrice,
  price_3: optionalPrice,
  extra_1: z.string().nullish(),
  extra_2: z.string().nullish(),
  extra_3: z.string().nullish(),
  extra_4: z.string().nullish(),
  /**
   * Accepted so a present value does not fail validation, but it is dropped by
   * the mapper: this project uses no canteen images.
   */
  image_url: z.string().nullish(),
});

export const foodPlanEntrySchema = z.object({
  /** Stable upsert key. */
  id: z.number().int(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'expected YYYY-MM-DD'),
  counter_id: z.number().int().nullish(),
  location_id: z.number().int(),
  is_sprint: z.boolean().nullish(),
  food: foodSchema,
});

export const foodPlanResponseSchema = z.object({
  data: z.array(foodPlanEntrySchema),
  meta: z
    .object({
      ingredients: z.record(z.string(), z.string()).nullish(),
      markers: z.record(z.string(), z.string()).nullish(),
    })
    .nullish(),
});

export type FoodPlanResponse = z.infer<typeof foodPlanResponseSchema>;
export type FoodPlanEntry = z.infer<typeof foodPlanEntrySchema>;

export type PriceGroup = 'student' | 'employee' | 'guest';

/**
 * Maps the source's positional price fields to stable technical keys. The
 * client never learns the source's numbering.
 */
export const PRICE_FIELD_TO_GROUP: Record<string, PriceGroup> = {
  price_1: 'student',
  price_2: 'employee',
  price_3: 'guest',
};

export const PRICE_GROUP_LABELS: Record<PriceGroup, { de: string; en: string }> = {
  student: { de: 'Studierende', en: 'Students' },
  employee: { de: 'Mitarbeiter', en: 'Employees' },
  guest: { de: 'Gäste', en: 'Guests' },
};

export interface NormalizedMeal {
  sourcePlanId: number;
  sourceFoodId: number | null;
  date: string;
  counterId: number | null;
  isSprint: boolean;
  name: string;
  subtitle: string | null;
  extras: string[];
  ingredientCodes: string[];
  /** Only groups the source actually provided. A missing group is absent. */
  prices: Array<{ group: PriceGroup; amount: string }>;
}

/**
 * Converts a validated entry into the internal shape.
 *
 * Note what is NOT carried over: `image_url`.
 */
export function normalizeEntry(entry: FoodPlanEntry): NormalizedMeal {
  const food = entry.food;

  const prices: Array<{ group: PriceGroup; amount: string }> = [];
  for (const [field, group] of Object.entries(PRICE_FIELD_TO_GROUP)) {
    const amount = food[field as 'price_1' | 'price_2' | 'price_3'];
    if (amount !== null && amount !== undefined) {
      prices.push({ group, amount });
    }
  }

  const extras = [food.extra_1, food.extra_2, food.extra_3, food.extra_4]
    .map((value) => (typeof value === 'string' ? value.trim() : ''))
    .filter((value) => value.length > 0);

  const subtitle =
    typeof food.name_2 === 'string' && food.name_2.trim().length > 0 ? food.name_2.trim() : null;

  return {
    sourcePlanId: entry.id,
    sourceFoodId: food.id ?? null,
    date: entry.date,
    counterId: entry.counter_id ?? null,
    isSprint: entry.is_sprint === true,
    name: food.name.trim(),
    subtitle,
    extras,
    ingredientCodes: (food.ingredients ?? []).filter((code) => code.trim().length > 0),
    prices,
  };
}

export interface NormalizedDefinition {
  code: string;
  labelDe: string;
  kind: 'ingredient' | 'marker';
}

/**
 * Flattens both dictionaries into one list, keeping which namespace each code
 * came from — the client needs that distinction because `food.ingredients`
 * mixes them.
 *
 * Only the German label exists upstream. `labelEn` stays unset; nothing is
 * machine-translated.
 */
export function normalizeDefinitions(meta: FoodPlanResponse['meta']): NormalizedDefinition[] {
  const result: NormalizedDefinition[] = [];
  for (const [code, labelDe] of Object.entries(meta?.ingredients ?? {})) {
    result.push({ code, labelDe, kind: 'ingredient' });
  }
  for (const [code, labelDe] of Object.entries(meta?.markers ?? {})) {
    result.push({ code, labelDe, kind: 'marker' });
  }
  return result;
}
