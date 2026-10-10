import { z } from 'zod';
import { ApiError } from '../errors/api-error';
import { Locale } from '../locale/locale';
import { addCalendarDays, campusToday } from '../time/campus-date';
import { asString } from '../util/coerce';

/**
 * Query parsing helpers.
 *
 * Every list endpoint bounds its inputs. An unbounded `pageSize` or an
 * unbounded date range is an availability problem, not a convenience.
 */

export const MAX_PAGE_SIZE = 50;
export const DEFAULT_PAGE_SIZE = 20;
export const MAX_MENU_RANGE_DAYS = 31;
export const DEFAULT_MENU_RANGE_DAYS = 14;

export function parseWith<T>(schema: z.ZodType<T>, value: unknown, locale: Locale): T {
  const result = schema.safeParse(value);
  if (!result.success) {
    throw new ApiError(
      'VALIDATION_FAILED',
      locale,
      result.error.issues.map((issue) => `${issue.path.join('.') || '(query)'}: ${issue.message}`),
    );
  }
  return result.data;
}

export const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE),
});

/**
 * Bounds on a comma-separated list filter.
 *
 * Each value becomes one `filters[…][$in][n]=…` pair in the Strapi request, so
 * the caller decides the size of an upstream URL. Both endpoints that take such
 * a list serve a catalogue an editor maintains by hand — a request naming more
 * channels or tags than exist is not a real one, and answering it with a clear
 * 400 is cheaper for everyone than forwarding it (AGENTS.md §7).
 */
export const MAX_FILTER_VALUES = 25;
export const MAX_FILTER_VALUE_LENGTH = 100;

/** Splits a CSV filter and enforces {@link MAX_FILTER_VALUES}. */
function parseFilterList(raw: unknown, name: string, locale: Locale): string[] {
  const value = Array.isArray(raw) ? raw.join(',') : asString(raw);
  const entries = value
    .split(',')
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);

  // Counted before de-duplication on purpose: a repeated slug still travels.
  if (entries.length > MAX_FILTER_VALUES) {
    throw new ApiError('VALIDATION_FAILED', locale, [
      `${name}: at most ${MAX_FILTER_VALUES} values are allowed`,
    ]);
  }
  for (const entry of entries) {
    if (entry.length > MAX_FILTER_VALUE_LENGTH) {
      throw new ApiError('VALIDATION_FAILED', locale, [
        `${name}: a value must not exceed ${MAX_FILTER_VALUE_LENGTH} characters`,
      ]);
    }
  }
  return entries;
}

/**
 * Splits the `channels` CSV.
 *
 * The distinction that matters: `undefined` (parameter absent) means "all
 * active channels", while `''` (present but empty) means "deliberately none".
 * Returning both the list and a presence flag keeps that explicit downstream.
 */
export function parseChannels(
  raw: unknown,
  locale: Locale,
): {
  channels: string[];
  channelsParamPresent: boolean;
} {
  if (raw === undefined || raw === null) {
    return { channels: [], channelsParamPresent: false };
  }
  return {
    channels: parseFilterList(raw, 'channels', locale),
    channelsParamPresent: true,
  };
}

/**
 * Splits the `tags` CSV. Same presence/empty distinction as {@link parseChannels}:
 * `undefined` means "no tag filter", `''` means "deliberately no tags" ⇒ empty result.
 */
export function parseTags(
  raw: unknown,
  locale: Locale,
): {
  tags: string[];
  tagsParamPresent: boolean;
} {
  if (raw === undefined || raw === null) {
    return { tags: [], tagsParamPresent: false };
  }
  return {
    tags: parseFilterList(raw, 'tags', locale),
    tagsParamPresent: true,
  };
}

/**
 * Midnight UTC of a `YYYY-MM-DD` day, or `NaN` if that day does not exist.
 *
 * `Date.parse` alone is not a calendar check: V8 rolls a day overflow forward
 * rather than refusing it, so `2026-02-30` parses happily as 2026-03-02 and
 * `2025-02-29` as 2025-03-01. Only the round trip back to the same string
 * proves the input names a real day.
 */
export function parseIsoDayUtc(value: string): number {
  const parsed = Date.parse(`${value}T00:00:00.000Z`);
  if (Number.isNaN(parsed)) {
    return Number.NaN;
  }
  return new Date(parsed).toISOString().slice(0, 10) === value ? parsed : Number.NaN;
}

/**
 * A calendar day the client actually named.
 *
 * Shared by every date-range endpoint on purpose: four private copies of this
 * schema had drifted, and a day that silently shifts does not just answer the
 * wrong window — it can invert the interval and make a route report an empty
 * result where the contract promises one entry per requested day.
 */
export const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'must be a date in YYYY-MM-DD format')
  .refine((value) => !Number.isNaN(parseIsoDayUtc(value)), 'must be a valid date');

/**
 * Orders and bounds a `{ from, to }` pair.
 *
 * Both checks run on the SAME parsed basis. Comparing the strings while
 * measuring the span in timestamps is what let an overflowed `from` pass the
 * ordering check and still arrive inverted downstream.
 *
 * Both also stand down when either day failed {@link isoDate}. A schema that
 * wraps a plain object still runs its refinements after a field-level failure,
 * and `NaN >= NaN` / `NaN <= maxDays` are both false — so a single bad date
 * produced two further complaints, about an ORDER and a SPAN that were never
 * the problem. `must be a valid date` is the honest and sufficient answer.
 */
export function refineDateRange<T extends { from: string; to: string }>(
  schema: z.ZodType<T>,
  maxDays: number,
): z.ZodType<T> {
  const days = (range: { from: string; to: string }): [number, number] => [
    parseIsoDayUtc(range.from),
    parseIsoDayUtc(range.to),
  ];
  const eitherIsNotADay = (from: number, to: number): boolean =>
    Number.isNaN(from) || Number.isNaN(to);

  return schema
    .refine(
      (range) => {
        const [from, to] = days(range);
        return eitherIsNotADay(from, to) || to >= from;
      },
      { message: '`to` must not be earlier than `from`' },
    )
    .refine(
      (range) => {
        const [from, to] = days(range);
        return eitherIsNotADay(from, to) || (to - from) / 86_400_000 <= maxDays;
      },
      { message: `the range must not exceed ${maxDays} days` },
    );
}

export const dateRangeSchema = refineDateRange(
  z.object({ from: isoDate.optional(), to: isoDate.optional() }).transform((input) => {
    // The campus day, not the UTC day: see `campusToday`.
    const from = input.from ?? campusToday();
    const to = input.to ?? addCalendarDays(from, DEFAULT_MENU_RANGE_DAYS);
    return { from, to };
  }),
  MAX_MENU_RANGE_DAYS,
);
