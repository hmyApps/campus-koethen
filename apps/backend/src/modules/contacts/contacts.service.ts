import { Injectable } from '@nestjs/common';
import { TtlCache } from '../../common/cache/ttl-cache';
import { blocksToPlainText, sanitizeBlocks } from '../../common/content/content-blocks';
import { ApiError } from '../../common/errors/api-error';
import { publicMediaUrl } from '../media/media.path';
import { LocaleResolution } from '../../common/locale/locale';
import { StrapiClient, StrapiListResponse, StrapiRequestError } from '../strapi/strapi.client';
import {
  ContactAreaDetailDto,
  ContactAreaListItemDto,
  ContactPersonDto,
  ContactSearchAreaDto,
  ContactSearchPersonDto,
} from './contacts.types';
import { ROOM_REFERENCE_FIELDS, mapRoomReferences } from '../rooms/rooms.service';
import { Locale } from '../../common/locale/locale';
import { asString } from '../../common/util/coerce';

/**
 * Read model for /v1/contact-areas*.
 *
 * Same locale strategy as news: German is the canonical set, the requested
 * locale is overlaid, and anything untranslated keeps its German text and sets
 * `translationFallback`.
 *
 * A contact area is valid and fully usable WITHOUT any person — several real
 * points of contact are institutional rather than personal.
 */

const CANONICAL_LOCALE = 'de';

type Raw = Record<string, unknown>;

function isRecord(value: unknown): value is Raw {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function str(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null;
}

function httpsUrl(value: unknown): string | null {
  if (typeof value !== 'string' || value.length === 0) {
    return null;
  }
  try {
    return new URL(value).protocol === 'https:' ? value : null;
  } catch {
    return null;
  }
}

/** A syntactically implausible address is dropped rather than shown as a dead link. */
function email(value: unknown): string | null {
  const candidate = str(value);
  if (!candidate) {
    return null;
  }
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(candidate) ? candidate : null;
}

function mapPerson(raw: unknown, locale: Locale): ContactPersonDto | null {
  if (!isRecord(raw) || raw['isActive'] === false) {
    return null;
  }
  const name = str(raw['name']);
  if (!name) {
    return null;
  }
  // Strapi's local provider publishes a RELATIVE url, which httpsUrl() would
  // drop — that is why no photo ever reached the app. The image is served by
  // this API instead, so the client never talks to Strapi (AGENTS.md §2.1).
  const image = isRecord(raw['profileImage']) ? publicMediaUrl(raw['profileImage']['url']) : null;
  return {
    name,
    role: str(raw['role']),
    description: str(raw['description']),
    email: email(raw['email']),
    phone: str(raw['phone']),
    website: httpsUrl(raw['website']),
    profileImage: image,
    sortOrder: typeof raw['sortOrder'] === 'number' ? raw['sortOrder'] : 0,
    // Absent relation -> empty list. A person without a room stays valid.
    rooms: mapRoomReferences(raw['rooms'], locale).rooms,
  };
}

function mapAreaBase(raw: Raw): Omit<ContactAreaListItemDto, 'personCount'> {
  return {
    slug: asString(raw['slug']),
    name: asString(raw['name']),
    shortDescription: asString(raw['shortDescription']),
    iconKey: asString(raw['iconKey'], 'service'),
    // Served by this API, like every other editorial image.
    image: isRecord(raw['image']) ? publicMediaUrl(raw['image']['url']) : null,
    sortOrder: typeof raw['sortOrder'] === 'number' ? raw['sortOrder'] : 0,
    generalEmail: email(raw['generalEmail']),
    phone: str(raw['phone']),
    website: httpsUrl(raw['website']),
    appointmentBookingUrl: httpsUrl(raw['appointmentBookingUrl']),
    address: str(raw['address']),
    openingHours: str(raw['openingHours']),
  };
}

function activePersons(persons: unknown[], locale: Locale): ContactPersonDto[] {
  return persons
    .map((person) => mapPerson(person, locale))
    .filter((person): person is ContactPersonDto => person !== null)
    .sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name));
}

/**
 * Whether {@link mapPerson} would deliver this person: a record, not
 * explicitly inactive, with a usable name. The one definition shared by the
 * count, the fallback check and the mapping itself.
 */
function isDeliverablePerson(person: unknown): person is Raw {
  return isRecord(person) && person['isActive'] !== false && str(person['name']) !== null;
}

/** The only person fields an editor translates; everything else is shared. */
const LOCALISED_PERSON_FIELDS = ['role', 'description'] as const;

/**
 * The persons of an area as a reader of `localised`'s language sees them.
 *
 * Strapi 5 localises every relation between localised types, so the
 * translated area carries its OWN person list — possibly never linked,
 * possibly partial, possibly holding a person the canonical area does not
 * have. Which persons exist therefore always comes from the CANONICAL
 * relation; this is the same source the list counts from. The translation
 * contributes only `role` and `description`, matched by the person's
 * `documentId` (shared by all locales of one document). That id is used here
 * and nowhere else — the DTO is built field by field and never carries it.
 *
 * `fallback` is true when a delivered person has German text in a localised
 * field that the translation does not provide.
 */
function overlayPersons(
  canonical: Raw,
  localised: Raw | undefined,
): { persons: unknown[]; fallback: boolean } {
  const canonicalPersons = Array.isArray(canonical['persons']) ? canonical['persons'] : [];
  const translatedById = new Map<string, Raw>();
  const translatedPersons =
    localised && Array.isArray(localised['persons']) ? localised['persons'] : [];
  for (const person of translatedPersons) {
    const id = isRecord(person) ? str(person['documentId']) : null;
    if (id && isRecord(person) && !translatedById.has(id)) {
      translatedById.set(id, person);
    }
  }

  let fallback = false;
  const persons = canonicalPersons.map((person): unknown => {
    if (!isDeliverablePerson(person)) {
      return person;
    }
    const id = str(person['documentId']);
    const translation = id ? translatedById.get(id) : undefined;
    const merged: Raw = { ...person };
    for (const field of LOCALISED_PERSON_FIELDS) {
      const translated = translation ? str(translation[field]) : null;
      if (translated) {
        merged[field] = translated;
      } else if (str(person[field])) {
        fallback = true;
      }
    }
    return merged;
  });

  return { persons, fallback };
}

/** Canonical persons, overlaid with the translation when one is requested. */
function personsFor(
  canonical: Raw,
  localised: Raw | undefined,
  needsTranslation: boolean,
): { persons: unknown[]; fallback: boolean } {
  if (!needsTranslation) {
    return {
      persons: Array.isArray(canonical['persons']) ? canonical['persons'] : [],
      fallback: false,
    };
  }
  return overlayPersons(canonical, localised);
}

/**
 * How many persons of an area {@link mapPerson} would deliver.
 *
 * The area LIST needs this number and nothing else — it deliberately carries no
 * person data at all, which is why it populates only `name` and `isActive`.
 * Counting through {@link activePersons} meant building a full DTO per person,
 * running the room mapping and sorting the result, only to read `.length` off
 * it and drop everything.
 *
 * The rule has to stay exactly {@link mapPerson}'s: not a record, explicitly
 * inactive, or without a usable name means not delivered, and therefore not
 * counted.
 */
function activePersonCount(raw: Raw): number {
  const persons = raw['persons'];
  if (!Array.isArray(persons)) {
    return 0;
  }
  let count = 0;
  for (const person of persons) {
    if (isDeliverablePerson(person)) count += 1;
  }
  return count;
}

/** Fields shared across locales; the overlay must not overwrite them. */
function sharedFields(canonical: Raw): Raw {
  return {
    slug: canonical['slug'],
    iconKey: canonical['iconKey'],
    image: canonical['image'],
    sortOrder: canonical['sortOrder'],
    isActive: canonical['isActive'],
    generalEmail: canonical['generalEmail'],
    phone: canonical['phone'],
    website: canonical['website'],
    appointmentBookingUrl: canonical['appointmentBookingUrl'],
  };
}

/**
 * Only the fields a reader could actually search for.
 *
 * `profileImage` is deliberately absent: nobody searches for a picture, and an
 * index is the wrong place to hand out more than the question needs.
 */
const SEARCH_POPULATE = {
  persons: {
    fields: ['name', 'role', 'description', 'email', 'phone', 'website', 'sortOrder', 'isActive'],
    populate: { rooms: { fields: [...ROOM_REFERENCE_FIELDS] } },
  },
  rooms: { fields: [...ROOM_REFERENCE_FIELDS] },
} as const;

/** Drops the fields the search has no use for. */
function toSearchPerson(person: ContactPersonDto): ContactSearchPersonDto {
  return {
    name: person.name,
    role: person.role,
    description: person.description,
    email: person.email,
    phone: person.phone,
    website: person.website,
    rooms: person.rooms,
  };
}

const AREAS_CACHE_TTL_MS = 60_000;

@Injectable()
export class ContactsService {
  // Contact areas are redaktionell gepflegt and change rarely; a short TTL
  // cuts the per-request Strapi round-trip without meaningfully staling data.
  private readonly areasCache = new TtlCache<{
    data: ContactAreaListItemDto[];
    translationFallback: boolean;
  }>(AREAS_CACHE_TTL_MS);

  // The search index is the heaviest read in this API — every area with every
  // person and every room — and it is built from exactly the same editorial
  // data as the list above. It gets the same TTL.
  private readonly searchIndexCache = new TtlCache<{
    data: ContactSearchAreaDto[];
    translationFallback: boolean;
  }>(AREAS_CACHE_TTL_MS);

  // Individual contact area details are cached with the same TTL to prevent
  // redundant Strapi roundtrips on repeat reads.
  private readonly areaDetailCache = new TtlCache<{
    data: ContactAreaDetailDto;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }>(AREAS_CACHE_TTL_MS);

  constructor(private readonly strapi: StrapiClient) {}

  private async fetch(query: Record<string, unknown>): Promise<Raw[]> {
    try {
      const response = await this.strapi.get<StrapiListResponse<Raw>>('/api/contact-areas', query);
      return Array.isArray(response?.data) ? response.data : [];
    } catch (error) {
      if (error instanceof StrapiRequestError) {
        throw new ApiError(error.kind === 'timeout' ? 'UPSTREAM_TIMEOUT' : 'UPSTREAM_UNAVAILABLE');
      }
      throw error;
    }
  }

  private static bySlug(entries: Raw[]): Map<string, Raw> {
    const map = new Map<string, Raw>();
    for (const entry of entries) {
      const slug = entry['slug'];
      if (typeof slug === 'string' && slug && !map.has(slug)) {
        map.set(slug, entry);
      }
    }
    return map;
  }

  async listAreas(locale: LocaleResolution): Promise<{
    data: ContactAreaListItemDto[];
    translationFallback: boolean;
  }> {
    return this.areasCache.getOrSet(locale.resolvedLocale, () => this.fetchAreas(locale));
  }

  private async fetchAreas(locale: LocaleResolution): Promise<{
    data: ContactAreaListItemDto[];
    translationFallback: boolean;
  }> {
    const baseQuery = {
      filters: { isActive: { $eq: true } },
      sort: ['sortOrder:asc', 'name:asc'],
      pagination: { pageSize: 100 },
      // Persons are populated only to count the active ones; no personal data
      // beyond that reaches the list response.
      populate: {
        persons: { fields: ['name', 'isActive'] },
        image: { fields: ['url'] },
      },
    };

    const needsTranslation = locale.resolvedLocale !== CANONICAL_LOCALE;
    const [canonical, translatedRaw] = await Promise.all([
      this.fetch({ ...baseQuery, locale: CANONICAL_LOCALE }),
      needsTranslation
        ? this.fetch({ ...baseQuery, locale: locale.resolvedLocale })
        : Promise.resolve<Raw[]>([]),
    ]);
    const translated = needsTranslation
      ? ContactsService.bySlug(translatedRaw)
      : new Map<string, Raw>();

    let fallbackUsed = false;
    const data = canonical.map((raw) => {
      const slug = asString(raw['slug']);
      const localised = translated.get(slug);
      if (needsTranslation && !localised) {
        fallbackUsed = true;
      }
      const merged = localised ? { ...raw, ...localised, ...sharedFields(raw) } : raw;
      return {
        ...mapAreaBase(merged),
        personCount: activePersonCount(raw),
      };
    });

    data.sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name));

    return { data, translationFallback: fallbackUsed };
  }

  /**
   * Everything the contact search can match, in **one** response.
   *
   * The list endpoint deliberately carries no detail, so a client searching
   * over names, descriptions and rooms would otherwise have to fetch every area
   * separately — an N+1 on every keystroke. This endpoint exists so the app can
   * load the index once, cache it, and search locally.
   *
   * Two Strapi requests at most (canonical plus the requested locale), exactly
   * like the detail endpoint.
   */
  async searchIndex(locale: LocaleResolution): Promise<{
    data: ContactSearchAreaDto[];
    translationFallback: boolean;
  }> {
    return this.searchIndexCache.getOrSet(locale.resolvedLocale, () =>
      this.fetchSearchIndex(locale),
    );
  }

  private async fetchSearchIndex(locale: LocaleResolution): Promise<{
    data: ContactSearchAreaDto[];
    translationFallback: boolean;
  }> {
    const query = {
      filters: { isActive: { $eq: true } },
      sort: ['sortOrder:asc', 'name:asc'],
      pagination: { pageSize: 100 },
      populate: SEARCH_POPULATE,
    };

    const needsTranslation = locale.resolvedLocale !== CANONICAL_LOCALE;
    const [canonical, translatedRaw] = await Promise.all([
      this.fetch({ ...query, locale: CANONICAL_LOCALE }),
      needsTranslation
        ? this.fetch({ ...query, locale: locale.resolvedLocale })
        : Promise.resolve<Raw[]>([]),
    ]);
    const translated = needsTranslation
      ? ContactsService.bySlug(translatedRaw)
      : new Map<string, Raw>();

    let fallbackUsed = false;
    const data = canonical.map((raw) => {
      const slug = asString(raw['slug']);
      const localised = translated.get(slug);
      if (locale.resolvedLocale !== CANONICAL_LOCALE && !localised) {
        fallbackUsed = true;
      }
      const merged = localised ? { ...raw, ...localised, ...sharedFields(raw) } : raw;

      const base = mapAreaBase(merged);
      // Rooms are not localised in Strapi, so the canonical entry is the
      // reliable source for them — same rule as the detail endpoint.
      const areaRooms = mapRoomReferences(raw['rooms'], locale.resolvedLocale);
      if (areaRooms.fallback) {
        fallbackUsed = true;
      }

      // Same rule as the detail endpoint: persons from the canonical relation,
      // only their localised text from the translation.
      const persons = personsFor(raw, localised, needsTranslation);
      if (persons.fallback) {
        fallbackUsed = true;
      }

      return {
        slug: base.slug,
        name: base.name,
        shortDescription: base.shortDescription,
        iconKey: base.iconKey,
        descriptionText: blocksToPlainText(sanitizeBlocks(merged['description']).blocks),
        generalEmail: base.generalEmail,
        phone: base.phone,
        website: base.website,
        appointmentBookingUrl: base.appointmentBookingUrl,
        address: base.address,
        openingHours: base.openingHours,
        rooms: areaRooms.rooms,
        persons: activePersons(persons.persons, locale.resolvedLocale).map(toSearchPerson),
      };
    });

    return { data, translationFallback: fallbackUsed };
  }

  async getArea(
    locale: LocaleResolution,
    slug: string,
  ): Promise<{
    data: ContactAreaDetailDto;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }> {
    const key = `${locale.resolvedLocale}:${slug}`;
    return this.areaDetailCache.getOrSet(key, () => this.fetchArea(locale, slug));
  }

  private async fetchArea(
    locale: LocaleResolution,
    slug: string,
  ): Promise<{
    data: ContactAreaDetailDto;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }> {
    const populate = {
      persons: {
        fields: [
          'name',
          'role',
          'description',
          'email',
          'phone',
          'website',
          'sortOrder',
          'isActive',
        ],
        populate: {
          profileImage: { fields: ['url'] },
          rooms: { fields: [...ROOM_REFERENCE_FIELDS] },
        },
      },
      rooms: { fields: [...ROOM_REFERENCE_FIELDS] },
      image: { fields: ['url'] },
    };

    const needsTranslation = locale.resolvedLocale !== CANONICAL_LOCALE;
    const [canonicalRows, translatedRows] = await Promise.all([
      this.fetch({
        filters: { slug: { $eq: slug }, isActive: { $eq: true } },
        populate,
        pagination: { pageSize: 1 },
        locale: CANONICAL_LOCALE,
      }),
      needsTranslation
        ? this.fetch({
            filters: { slug: { $eq: slug }, isActive: { $eq: true } },
            populate,
            pagination: { pageSize: 1 },
            locale: locale.resolvedLocale,
          })
        : Promise.resolve<Raw[]>([]),
    ]);

    const canonical = canonicalRows[0];
    if (!canonical) {
      throw new ApiError('CONTACT_AREA_NOT_FOUND', locale.resolvedLocale);
    }

    const localised: Raw | undefined = needsTranslation ? translatedRows[0] : undefined;

    const merged = localised
      ? { ...canonical, ...localised, ...sharedFields(canonical) }
      : canonical;

    const { blocks, droppedBlockTypes } = sanitizeBlocks(merged['description']);

    // Rooms are shared across locales (the room relation is not localised), so
    // the canonical entry is the reliable source for them.
    const areaRooms = mapRoomReferences(canonical['rooms'], locale.resolvedLocale);

    // Persons carry only non-localised contact data plus localised role and
    // description. Which persons exist comes from the canonical relation — the
    // same source the list counts from — and only their text is translated.
    const persons = personsFor(canonical, localised, needsTranslation);

    return {
      data: {
        ...mapAreaBase(merged),
        description: blocks,
        persons: activePersons(persons.persons, locale.resolvedLocale),
        rooms: areaRooms.rooms,
      },
      translationFallback:
        (locale.resolvedLocale !== CANONICAL_LOCALE && !localised) ||
        areaRooms.fallback ||
        persons.fallback,
      droppedBlockTypes,
    };
  }
}
