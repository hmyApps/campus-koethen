import { z } from 'zod';
import { tryExtractCalendarId } from './google-calendar-url';
import { CalendarDefinition } from './public-calendar.types';

/**
 * Validation of the editorial calendar definitions coming from Strapi.
 *
 * This runs at the BACKEND trust boundary: even though Strapi's own validation
 * should already reject a bad share URL, the worker re-validates every field
 * here and re-derives the calendar id from the share link. A single invalid
 * entry is dropped (and counted), never taking the rest of the catalogue down.
 */

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/;

/** Strapi 5 returns flat attributes. Unknown extra keys are ignored. */
const strapiEntrySchema = z
  .object({
    slug: z.string(),
    name: z.string().min(1),
    googleShareUrl: z.string(),
    colorHex: z.string(),
    sortOrder: z.coerce.number().int().default(0),
    isActive: z.boolean().default(true),
    defaultSubscribed: z.boolean().default(false),
    includeEventDescription: z.boolean().default(false),
    includeEventLocation: z.boolean().default(false),
    channel: z
      .object({
        slug: z.string(),
      })
      .nullish(),
  })
  .passthrough();

export type StrapiEntry = z.infer<typeof strapiEntrySchema>;

export interface CatalogValidationResult {
  definitions: CalendarDefinition[];
  received: number;
  rejected: number;
  /**
   * Slugs of the rejected entries that still named one. A rejected entry is
   * a publication that failed validation, not a withdrawal: the calendar it
   * names must not be retired because of it.
   */
  rejectedSlugs: string[];
  /** True if at least one rejected entry did not name a readable slug. */
  rejectedWithoutSlug: boolean;
}

/** The slug a rejected raw entry claims, if it names one at all. */
function claimedSlug(raw: unknown): string | null {
  if (raw === null || typeof raw !== 'object') return null;
  const slug = (raw as Record<string, unknown>)['slug'];
  return typeof slug === 'string' && slug.length > 0 ? slug : null;
}

/**
 * Validates the canonical (German) catalogue, overlaying English translations
 * keyed by the non-localised slug.
 */
export function validateCatalog(
  deEntries: unknown[],
  enEntries: unknown[],
): CatalogValidationResult {
  const enBySlug = new Map<string, StrapiEntry>();
  for (const raw of enEntries) {
    const parsed = strapiEntrySchema.safeParse(raw);
    if (parsed.success && SLUG_PATTERN.test(parsed.data.slug)) {
      enBySlug.set(parsed.data.slug, parsed.data);
    }
  }

  const definitions: CalendarDefinition[] = [];
  let rejected = 0;
  const rejectedSlugs: string[] = [];
  let rejectedWithoutSlug = false;
  const reject = (raw: unknown): void => {
    rejected += 1;
    const slug = claimedSlug(raw);
    if (slug === null) rejectedWithoutSlug = true;
    else rejectedSlugs.push(slug);
  };

  for (const raw of deEntries) {
    const parsed = strapiEntrySchema.safeParse(raw);
    if (!parsed.success) {
      reject(raw);
      continue;
    }
    const entry = parsed.data;

    if (!SLUG_PATTERN.test(entry.slug) || !COLOR_PATTERN.test(entry.colorHex)) {
      reject(raw);
      continue;
    }
    const extracted = tryExtractCalendarId(entry.googleShareUrl);
    if (!extracted.ok) {
      reject(raw);
      continue;
    }

    const en = enBySlug.get(entry.slug);

    const channelSlug =
      entry.channel &&
      typeof entry.channel.slug === 'string' &&
      SLUG_PATTERN.test(entry.channel.slug)
        ? entry.channel.slug
        : null;

    definitions.push({
      slug: entry.slug,
      googleCalendarId: extracted.calendarId,
      channelSlug,
      nameDe: entry.name,
      nameEn: en?.name ?? null,
      colorHex: entry.colorHex.toUpperCase(),
      sortOrder: entry.sortOrder,
      defaultSubscribed: entry.defaultSubscribed,
      includeEventDescription: entry.includeEventDescription,
      includeEventLocation: entry.includeEventLocation,
    });
  }

  return { definitions, received: deEntries.length, rejected, rejectedSlugs, rejectedWithoutSlug };
}
