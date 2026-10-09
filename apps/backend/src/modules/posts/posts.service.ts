// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import { Injectable, Logger } from '@nestjs/common';
import { TtlCache } from '../../common/cache/ttl-cache';
import { ApiError } from '../../common/errors/api-error';
import { LocaleResolution } from '../../common/locale/locale';
import { StrapiClient, StrapiListResponse, StrapiRequestError } from '../strapi/strapi.client';
import { mapChannel, mapPostDetail, mapPostListItem, mapTag } from './posts.mapper';
import { ChannelDto, PostDetailDto, PostListItemDto, TagDto } from './posts.types';
import { asString } from '../../common/util/coerce';

const CANONICAL_LOCALE = 'de';

type Raw = Record<string, unknown>;

export interface PostsQuery {
  channels: string[];
  /**
   * Distinguishes "?channels=" (present but empty -> deliberately no channels)
   * from an absent parameter (-> all active channels).
   */
  channelsParamPresent: boolean;
  tags: string[];
  /**
   * Distinguishes "?tags=" (present but empty -> deliberately no tags) from an
   * absent parameter (-> no tag filter at all).
   */
  tagsParamPresent: boolean;
  page: number;
  pageSize: number;
}

export interface EventsQuery {
  from: string;
  to: string;
  channels: string[];
  channelsParamPresent: boolean;
  page: number;
  pageSize: number;
}

export interface PaginationResult {
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
}

const CHANNELS_CACHE_TTL_MS = 60_000;
const TAGS_CACHE_TTL_MS = 60_000;

/**
 * Deliberately shorter than the catalogue TTLs above.
 *
 * A post list is filtered by a validity window (`validFrom`/`validUntil`)
 * evaluated against the moment of the request, so a cached page can hold a post
 * back — or keep it a moment too long — for at most this long. Half a minute is
 * short enough that nobody notices and long enough that a feed being scrolled by
 * many readers at once does not turn every scroll into a Strapi round-trip.
 */
const POSTS_CACHE_TTL_MS = 30_000;

/**
 * Strapi filter fragment: the post's publication window contains `now`.
 *
 * A post under embargo (`validFrom` in the future) or already withdrawn
 * (`validUntil` in the past) does not exist for a reader. This is the ONE
 * definition of that rule; every public read path — feed, event list and
 * detail — spreads it into its `$and`, so the routes cannot drift apart again.
 */
function validityFilter(now: string): Array<Record<string, unknown>> {
  return [
    { $or: [{ validFrom: { $null: true } }, { validFrom: { $lte: now } }] },
    { $or: [{ validUntil: { $null: true } }, { validUntil: { $gte: now } }] },
  ];
}

/** Strapi filter fragment: at least one of the post's channels is switched on. */
const ACTIVE_CHANNEL_FILTER = { isActive: { $eq: true } } as const;

@Injectable()
export class PostsService {
  private readonly logger = new Logger(PostsService.name);

  // Channels change rarely; a short TTL cuts the per-request Strapi round-trip.
  private readonly channelsCache = new TtlCache<{
    data: ChannelDto[];
    translationFallback: boolean;
  }>(CHANNELS_CACHE_TTL_MS);

  // Tags are the same kind of editor-maintained catalogue as channels and get
  // the same treatment; they were simply missed when the cache was introduced.
  private readonly tagsCache = new TtlCache<{
    data: TagDto[];
    translationFallback: boolean;
  }>(TAGS_CACHE_TTL_MS);

  // Article details are cached with a short TTL so repeat reads of the same
  // article do not issue duplicate requests to Strapi.
  private readonly postDetailCache = new TtlCache<{
    data: PostDetailDto;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }>(CHANNELS_CACHE_TTL_MS);

  // The feed is the most-requested route of this API — an endless list that
  // every reader pages through — and it was the only read model here that still
  // went to Strapi on every single request, twice per request in English. The
  // key covers every input that changes the answer; the cache's own capacity
  // bound is what keeps a key derived from the query string from deciding how
  // much memory this process holds.
  private readonly postsListCache = new TtlCache<{
    data: PostListItemDto[];
    pagination: PaginationResult;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }>(POSTS_CACHE_TTL_MS);

  // Same reasoning, for the event list the calendar screen loads per month.
  private readonly eventsCache = new TtlCache<{
    data: PostListItemDto[];
    pagination: PaginationResult;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }>(POSTS_CACHE_TTL_MS);

  constructor(private readonly strapi: StrapiClient) {}

  /**
   * Cache key for a list query.
   *
   * Slugs are sorted because `?channels=a,b` and `?channels=b,a` ask Strapi the
   * same `$in` question and must not occupy two entries. The `present` flag is
   * part of the key on purpose: "no parameter" and "empty parameter" mean
   * opposite things in this API.
   */
  private static listKey(parts: Array<string | number | boolean>, ...slugs: string[][]): string {
    return [...parts, ...slugs.map((list) => [...list].sort().join(','))].join('|');
  }

  private async fetch(path: string, query: Record<string, unknown>): Promise<Raw[]> {
    try {
      const response = await this.strapi.get<StrapiListResponse<Raw>>(path, query);
      return Array.isArray(response?.data) ? response.data : [];
    } catch (error) {
      throw PostsService.toApiError(error);
    }
  }

  private async fetchWithMeta(
    path: string,
    query: Record<string, unknown>,
  ): Promise<StrapiListResponse<Raw>> {
    try {
      const response = await this.strapi.get<StrapiListResponse<Raw>>(path, query);
      return { data: Array.isArray(response?.data) ? response.data : [], meta: response?.meta };
    } catch (error) {
      throw PostsService.toApiError(error);
    }
  }

  private static toApiError(error: unknown): ApiError {
    if (error instanceof StrapiRequestError) {
      return new ApiError(error.kind === 'timeout' ? 'UPSTREAM_TIMEOUT' : 'UPSTREAM_UNAVAILABLE');
    }
    if (error instanceof ApiError) {
      return error;
    }
    return new ApiError('UPSTREAM_UNAVAILABLE');
  }

  /** Indexes documents by their stable, non-localised slug. */
  private static bySlug(entries: Raw[]): Map<string, Raw> {
    const map = new Map<string, Raw>();
    for (const entry of entries) {
      const slug = entry['slug'];
      if (typeof slug === 'string' && slug.length > 0 && !map.has(slug)) {
        map.set(slug, entry);
      }
    }
    return map;
  }

  async getChannels(locale: LocaleResolution): Promise<{
    data: ChannelDto[];
    translationFallback: boolean;
  }> {
    return this.channelsCache.getOrSet(locale.resolvedLocale, () => this.fetchChannels(locale));
  }

  private async fetchChannels(locale: LocaleResolution): Promise<{
    data: ChannelDto[];
    translationFallback: boolean;
  }> {
    const baseQuery = {
      filters: { isActive: { $eq: true } },
      sort: ['sortOrder:asc', 'name:asc'],
      populate: { publicCalendar: { fields: ['slug'] } },
      pagination: { pageSize: 100 },
    };

    const needsTranslation = locale.resolvedLocale !== CANONICAL_LOCALE;
    const [canonical, translatedRaw] = await Promise.all([
      this.fetch('/api/channels', { ...baseQuery, locale: CANONICAL_LOCALE }),
      needsTranslation
        ? this.fetch('/api/channels', { ...baseQuery, locale: locale.resolvedLocale })
        : Promise.resolve<Raw[]>([]),
    ]);

    const translated = needsTranslation
      ? PostsService.bySlug(translatedRaw)
      : new Map<string, Raw>();

    let fallbackUsed = false;
    const data = canonical.map((raw) => {
      const slug = asString(raw['slug']);
      const localised = translated.get(slug);
      // The channel name is a proper name and deliberately shared. Only a
      // missing translated description constitutes a language fallback.
      if (
        locale.resolvedLocale !== CANONICAL_LOCALE &&
        !localised &&
        asString(raw['description']).length > 0
      ) {
        fallbackUsed = true;
      }
      return mapChannel(
        localised
          ? {
              ...raw,
              ...localised,
              slug: raw['slug'],
              name: raw['name'],
              colorHex: raw['colorHex'],
              sortOrder: raw['sortOrder'],
              defaultSubscribed: raw['defaultSubscribed'],
              publicCalendar: raw['publicCalendar'],
            }
          : raw,
      );
    });

    data.sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name));

    return { data, translationFallback: fallbackUsed };
  }

  async getTags(locale: LocaleResolution): Promise<{
    data: TagDto[];
    translationFallback: boolean;
  }> {
    return this.tagsCache.getOrSet(locale.resolvedLocale, () => this.fetchTags(locale));
  }

  private async fetchTags(locale: LocaleResolution): Promise<{
    data: TagDto[];
    translationFallback: boolean;
  }> {
    const baseQuery = {
      filters: { isActive: { $eq: true } },
      sort: ['name:asc', 'slug:asc'],
      pagination: { pageSize: 100 },
    };

    // The translated catalogue does not depend on the canonical one, so waiting
    // for the first before starting the second only doubled the latency —
    // getChannels() right above already does it this way.
    const needsTranslation = locale.resolvedLocale !== CANONICAL_LOCALE;
    const [canonical, translatedRaw] = await Promise.all([
      this.fetch('/api/tags', { ...baseQuery, locale: CANONICAL_LOCALE }),
      needsTranslation
        ? this.fetch('/api/tags', { ...baseQuery, locale: locale.resolvedLocale })
        : Promise.resolve<Raw[]>([]),
    ]);

    const translated = needsTranslation
      ? PostsService.bySlug(translatedRaw)
      : new Map<string, Raw>();

    let fallbackUsed = false;
    const data = canonical.map((raw) => {
      const slug = asString(raw['slug']);
      const localised = translated.get(slug);
      if (locale.resolvedLocale !== CANONICAL_LOCALE && !localised) {
        fallbackUsed = true;
      }
      return mapTag(localised ?? raw);
    });

    data.sort((a, b) => a.name.localeCompare(b.name) || a.slug.localeCompare(b.slug));

    return { data, translationFallback: fallbackUsed };
  }

  async getPosts(
    locale: LocaleResolution,
    query: PostsQuery,
  ): Promise<{
    data: PostListItemDto[];
    pagination: PaginationResult;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }> {
    const key = PostsService.listKey(
      [
        locale.resolvedLocale,
        query.page,
        query.pageSize,
        query.channelsParamPresent,
        query.tagsParamPresent,
      ],
      query.channels,
      query.tags,
    );
    return this.postsListCache.getOrSet(key, () => this.fetchPosts(locale, query));
  }

  private async fetchPosts(
    locale: LocaleResolution,
    query: PostsQuery,
  ): Promise<{
    data: PostListItemDto[];
    pagination: PaginationResult;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }> {
    if (
      (query.channelsParamPresent && query.channels.length === 0) ||
      (query.tagsParamPresent && query.tags.length === 0)
    ) {
      return {
        data: [],
        pagination: { page: query.page, pageSize: query.pageSize, total: 0, totalPages: 0 },
        translationFallback: false,
        droppedBlockTypes: [],
      };
    }

    const filters: Record<string, unknown> = {
      $and: validityFilter(new Date().toISOString()),
    };

    if (query.channels.length > 0) {
      filters['channels'] = { slug: { $in: query.channels } };
    } else {
      filters['channels'] = ACTIVE_CHANNEL_FILTER;
    }

    if (query.tags.length > 0) {
      filters['tag'] = { slug: { $in: query.tags }, isActive: { $eq: true } };
    }

    const baseQuery = {
      filters,
      sort: ['publishedAt:desc', 'slug:asc'],
      populate: {
        tag: { fields: ['slug', 'name'] },
        primaryChannel: { fields: ['slug', 'name', 'colorHex'] },
        channels: { fields: ['slug', 'name', 'colorHex'] },
        heroImage: { fields: ['url', 'alternativeText', 'width', 'height'] },
      },
      pagination: { page: query.page, pageSize: query.pageSize },
    };

    const canonical = await this.fetchWithMeta('/api/posts', {
      ...baseQuery,
      locale: CANONICAL_LOCALE,
    });

    const unique = [...PostsService.bySlug(canonical.data).values()];

    let translated = new Map<string, Raw>();
    if (locale.resolvedLocale !== CANONICAL_LOCALE && unique.length > 0) {
      translated = PostsService.bySlug(
        await this.fetch('/api/posts', {
          filters: { slug: { $in: unique.map((entry) => asString(entry['slug'])) } },
          populate: baseQuery.populate,
          pagination: { pageSize: unique.length },
          locale: locale.resolvedLocale,
        }),
      );
    }

    let fallbackUsed = false;
    const dropped = new Set<string>();
    let invalidCount = 0;

    const data: PostListItemDto[] = [];
    for (const raw of unique) {
      const slug = asString(raw['slug']);
      const localised = translated.get(slug);
      if (locale.resolvedLocale !== CANONICAL_LOCALE) {
        fallbackUsed =
          fallbackUsed ||
          !localised ||
          PostsService.singleRelationTranslationMissing(raw['tag'], localised?.['tag'], 'name');
      }
      const mapped = mapPostListItem(
        localised ? { ...raw, ...localised, ...PostsService.sharedFields(raw, localised) } : raw,
      );
      for (const type of mapped.droppedBlockTypes) {
        dropped.add(type);
      }
      if (mapped.item) {
        data.push(mapped.item);
      } else {
        invalidCount += 1;
      }
    }

    if (invalidCount > 0) {
      this.logger.warn({
        message: `Dropped ${invalidCount} post(s) missing mandatory tag or primaryChannel relation.`,
        invalidCount,
      });
    }

    data.sort(
      (a, b) =>
        (b.publishedAt ?? '').localeCompare(a.publishedAt ?? '') || a.slug.localeCompare(b.slug),
    );

    const upstream = canonical.meta?.pagination;
    const total = upstream?.total ?? data.length;
    const pageSize = upstream?.pageSize ?? query.pageSize;

    return {
      data,
      pagination: {
        page: upstream?.page ?? query.page,
        pageSize,
        total,
        totalPages: upstream?.pageCount ?? Math.ceil(total / Math.max(pageSize, 1)),
      },
      translationFallback: fallbackUsed,
      droppedBlockTypes: [...dropped].sort(),
    };
  }

  async getEvents(
    locale: LocaleResolution,
    query: EventsQuery,
  ): Promise<{
    data: PostListItemDto[];
    pagination: PaginationResult;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }> {
    const key = PostsService.listKey(
      [
        locale.resolvedLocale,
        query.from,
        query.to,
        query.page,
        query.pageSize,
        query.channelsParamPresent,
      ],
      query.channels,
    );
    return this.eventsCache.getOrSet(key, () => this.fetchEvents(locale, query));
  }

  private async fetchEvents(
    locale: LocaleResolution,
    query: EventsQuery,
  ): Promise<{
    data: PostListItemDto[];
    pagination: PaginationResult;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }> {
    if (query.channelsParamPresent && query.channels.length === 0) {
      return {
        data: [],
        pagination: { page: query.page, pageSize: query.pageSize, total: 0, totalPages: 0 },
        translationFallback: false,
        droppedBlockTypes: [],
      };
    }

    const fromDate = `${query.from}T00:00:00.000Z`;
    const toDate = `${query.to}T23:59:59.999Z`;

    const filters: Record<string, unknown> = {
      tag: { slug: { $eq: 'event' }, isActive: { $eq: true } },
      $and: [
        ...validityFilter(new Date().toISOString()),
        { eventStart: { $lte: toDate } },
        {
          $or: [
            { eventEnd: { $gte: fromDate } },
            { $and: [{ eventEnd: { $null: true } }, { eventStart: { $gte: fromDate } }] },
          ],
        },
      ],
    };

    if (query.channels.length > 0) {
      filters['channels'] = { slug: { $in: query.channels } };
    } else {
      filters['channels'] = ACTIVE_CHANNEL_FILTER;
    }

    const baseQuery = {
      filters,
      sort: ['eventStart:asc', 'slug:asc'],
      populate: {
        tag: { fields: ['slug', 'name'] },
        primaryChannel: { fields: ['slug', 'name', 'colorHex'] },
        channels: { fields: ['slug', 'name', 'colorHex'] },
        heroImage: { fields: ['url', 'alternativeText', 'width', 'height'] },
      },
      pagination: { page: query.page, pageSize: query.pageSize },
    };

    const canonical = await this.fetchWithMeta('/api/posts', {
      ...baseQuery,
      locale: CANONICAL_LOCALE,
    });

    const unique = [...PostsService.bySlug(canonical.data).values()];

    let translated = new Map<string, Raw>();
    if (locale.resolvedLocale !== CANONICAL_LOCALE && unique.length > 0) {
      translated = PostsService.bySlug(
        await this.fetch('/api/posts', {
          filters: { slug: { $in: unique.map((entry) => asString(entry['slug'])) } },
          populate: baseQuery.populate,
          pagination: { pageSize: unique.length },
          locale: locale.resolvedLocale,
        }),
      );
    }

    let fallbackUsed = false;
    const dropped = new Set<string>();
    let invalidCount = 0;

    const data: PostListItemDto[] = [];
    for (const raw of unique) {
      const slug = asString(raw['slug']);
      const localised = translated.get(slug);
      if (locale.resolvedLocale !== CANONICAL_LOCALE) {
        fallbackUsed =
          fallbackUsed ||
          !localised ||
          PostsService.singleRelationTranslationMissing(raw['tag'], localised?.['tag'], 'name');
      }
      const mapped = mapPostListItem(
        localised ? { ...raw, ...localised, ...PostsService.sharedFields(raw, localised) } : raw,
      );
      for (const type of mapped.droppedBlockTypes) {
        dropped.add(type);
      }
      if (mapped.item) {
        data.push(mapped.item);
      } else {
        invalidCount += 1;
      }
    }

    if (invalidCount > 0) {
      this.logger.warn({
        message: `Dropped ${invalidCount} event post(s) missing mandatory tag or primaryChannel relation.`,
        invalidCount,
      });
    }

    data.sort(
      (a, b) =>
        (a.eventStart ?? '').localeCompare(b.eventStart ?? '') || a.slug.localeCompare(b.slug),
    );

    const upstream = canonical.meta?.pagination;
    const total = upstream?.total ?? data.length;
    const pageSize = upstream?.pageSize ?? query.pageSize;

    return {
      data,
      pagination: {
        page: upstream?.page ?? query.page,
        pageSize,
        total,
        totalPages: upstream?.pageCount ?? Math.ceil(total / Math.max(pageSize, 1)),
      },
      translationFallback: fallbackUsed,
      droppedBlockTypes: [...dropped].sort(),
    };
  }

  async getPostBySlug(
    locale: LocaleResolution,
    slug: string,
  ): Promise<{
    data: PostDetailDto;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }> {
    const key = `${locale.resolvedLocale}:${slug}`;
    return this.postDetailCache.getOrSet(key, () => this.fetchPostBySlug(locale, slug));
  }

  private async fetchPostBySlug(
    locale: LocaleResolution,
    slug: string,
  ): Promise<{
    data: PostDetailDto;
    translationFallback: boolean;
    droppedBlockTypes: string[];
  }> {
    const populate = {
      tag: { fields: ['slug', 'name'] },
      primaryChannel: { fields: ['slug', 'name', 'colorHex'] },
      channels: { fields: ['slug', 'name', 'colorHex'] },
      heroImage: { fields: ['url', 'alternativeText', 'width', 'height'] },
    };

    // Same visibility rules as the feed: a slug alone must not reach a post
    // under embargo, a withdrawn one, or one whose channels are all switched
    // off. Validity and channels are not localised, so both reads share them.
    const filters = {
      slug: { $eq: slug },
      channels: ACTIVE_CHANNEL_FILTER,
      $and: validityFilter(new Date().toISOString()),
    };

    const needsTranslation = locale.resolvedLocale !== CANONICAL_LOCALE;
    const [canonical, translated] = await Promise.all([
      this.fetch('/api/posts', {
        filters,
        populate,
        pagination: { pageSize: 1 },
        locale: CANONICAL_LOCALE,
      }),
      needsTranslation
        ? this.fetch('/api/posts', {
            filters,
            populate,
            pagination: { pageSize: 1 },
            locale: locale.resolvedLocale,
          })
        : Promise.resolve<Raw[]>([]),
    ]);

    const base = canonical[0];
    if (!base) {
      throw new ApiError('POST_NOT_FOUND', locale.resolvedLocale);
    }

    const localised: Raw | undefined = needsTranslation ? translated[0] : undefined;

    const merged = localised
      ? { ...base, ...localised, ...PostsService.sharedFields(base, localised) }
      : base;

    const { post, droppedBlockTypes } = mapPostDetail(merged);
    if (!post) {
      throw new ApiError('POST_NOT_FOUND', locale.resolvedLocale);
    }

    return {
      data: post,
      translationFallback:
        locale.resolvedLocale !== CANONICAL_LOCALE &&
        (!localised ||
          PostsService.singleRelationTranslationMissing(base['tag'], localised?.['tag'], 'name')),
      droppedBlockTypes,
    };
  }

  private static singleRelationTranslationMissing(
    canonicalValue: unknown,
    localisedValue: unknown,
    field: string,
  ): boolean {
    if (typeof canonicalValue !== 'object' || canonicalValue === null) return false;
    const cRaw = canonicalValue as Raw;
    const lRaw =
      typeof localisedValue === 'object' && localisedValue !== null
        ? (localisedValue as Raw)
        : null;
    return asString(cRaw[field]).length > 0 && asString(lRaw?.[field]).length === 0;
  }

  private static overlaySingleRelation(
    canonicalValue: unknown,
    localisedValue: unknown,
    field: string,
  ): unknown {
    if (typeof canonicalValue !== 'object' || canonicalValue === null) return canonicalValue;
    const cRaw = canonicalValue as Raw;
    const lRaw =
      typeof localisedValue === 'object' && localisedValue !== null
        ? (localisedValue as Raw)
        : null;
    if (!lRaw || !asString(lRaw[field])) return cRaw;
    return { ...cRaw, [field]: lRaw[field] };
  }

  private static sharedFields(canonical: Raw, localised: Raw): Raw {
    return {
      slug: canonical['slug'],
      publishedAt: canonical['publishedAt'],
      heroImage: canonical['heroImage'],
      primaryChannel: canonical['primaryChannel'],
      channels: canonical['channels'],
      tag: PostsService.overlaySingleRelation(canonical['tag'], localised['tag'], 'name'),
      sourceUrl: canonical['sourceUrl'],
      eventStart: canonical['eventStart'],
      eventEnd: canonical['eventEnd'],
      eventAllDay: canonical['eventAllDay'],
    };
  }
}
