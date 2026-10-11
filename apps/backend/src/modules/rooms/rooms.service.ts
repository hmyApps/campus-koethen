import { Injectable } from '@nestjs/common';
import { TtlCache } from '../../common/cache/ttl-cache';
import { ApiError } from '../../common/errors/api-error';
import { Locale, LocaleResolution } from '../../common/locale/locale';
import { parseStrapiList, StrapiClient, StrapiRequestError } from '../strapi/strapi.client';
import { catalogRoom, CatalogRoom } from './room-catalog';
import { RoomDto, RoomReferenceDto } from './rooms.types';

/**
 * Read model for /v1/rooms*.
 *
 * Technical identity, map placement and labels come exclusively from the
 * bundled @campus/map catalogue. Strapi is a small editorial overlay keyed by
 * roomKey: display names, descriptions, visibility and contact relations.
 */

const ROOMS_PATH = '/api/rooms';

/** Only editorial overlay fields are read from Strapi. */
const ROOM_FIELDS = [
  'roomKey',
  'displayNameDe',
  'displayNameEn',
  'descriptionDe',
  'descriptionEn',
] as const;

/**
 * A populated contact relation needs only its key, editorial labels and the
 * two visibility flags. Technical labels are resolved from @campus/map.
 */
export const ROOM_REFERENCE_FIELDS = [
  'roomKey',
  'displayNameDe',
  'displayNameEn',
  'catalogActive',
  'isVisible',
] as const;

type Raw = Record<string, unknown>;

interface MappedRoom {
  room: RoomDto;
  fallback: boolean;
}

export interface RoomFilters {
  buildingKey?: string;
  floorKey?: string;
}

function isRecord(value: unknown): value is Raw {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function str(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null;
}

/** Empty values in both languages are absent, not a translation fallback. */
function localisedEditorial(
  raw: Raw,
  base: string,
  locale: Locale,
): { value: string | null; fallback: boolean } {
  const german = str(raw[`${base}De`]);
  if (locale === 'de') return { value: german, fallback: false };
  const english = str(raw[`${base}En`]);
  if (english) return { value: english, fallback: false };
  return { value: german, fallback: german !== null };
}

function localisedCatalogName(
  room: CatalogRoom,
  base: 'buildingName' | 'floorName',
  locale: Locale,
): string {
  return locale === 'en' ? room[`${base}En`] : room[`${base}De`];
}

const ROOMS_CACHE_TTL_MS = 60_000;

@Injectable()
export class RoomsService {
  private readonly roomsCache = new TtlCache<MappedRoom[]>(ROOMS_CACHE_TTL_MS, 2);

  constructor(private readonly strapi: StrapiClient) {}

  private async fetch(query: Record<string, unknown>): Promise<Raw[]> {
    try {
      const rows: Raw[] = [];

      for (let page = 1; ; page += 1) {
        const response = parseStrapiList(
          await this.strapi.get<unknown>(ROOMS_PATH, {
            ...query,
            pagination: { page, pageSize: 100 },
          }),
        );
        rows.push(...response.data);

        const pageCount = response.meta?.pagination?.pageCount;
        if (typeof pageCount !== 'number' || !Number.isInteger(pageCount) || page >= pageCount) {
          break;
        }
      }

      return rows;
    } catch (error) {
      if (error instanceof StrapiRequestError) {
        throw new ApiError(error.kind === 'timeout' ? 'UPSTREAM_TIMEOUT' : 'UPSTREAM_UNAVAILABLE');
      }
      throw error;
    }
  }

  private static map(raw: Raw, locale: Locale): MappedRoom | null {
    const roomKey = str(raw['roomKey']);
    if (!roomKey) return null;
    const technical = catalogRoom(roomKey);
    if (!technical) return null;

    const displayName = localisedEditorial(raw, 'displayName', locale);
    const description = localisedEditorial(raw, 'description', locale);

    return {
      room: {
        roomKey,
        roomNumber: technical.roomNumber,
        buildingKey: technical.buildingKey,
        buildingNumber: technical.buildingNumber,
        buildingName: localisedCatalogName(technical, 'buildingName', locale),
        floorKey: technical.floorKey,
        floorName: localisedCatalogName(technical, 'floorName', locale),
        roomType: technical.roomType,
        displayName: displayName.value,
        description: description.value,
        mapVersion: technical.mapVersion,
        sortOrder: technical.sortOrder,
      },
      fallback: displayName.fallback || description.fallback,
    };
  }

  /** How many locale catalogues are cached right now. */
  get cachedCatalogues(): number {
    return this.roomsCache.size;
  }

  private async loadRooms(locale: Locale): Promise<MappedRoom[]> {
    return this.roomsCache.getOrSet(locale, async () => {
      const rows = await this.fetch({
        filters: { catalogActive: { $eq: true }, isVisible: { $eq: true } },
        fields: [...ROOM_FIELDS],
        sort: ['roomKey:asc'],
      });

      return rows
        .map((raw) => (isRecord(raw) ? RoomsService.map(raw, locale) : null))
        .filter((mapped): mapped is MappedRoom => mapped !== null)
        .sort(
          (a, b) =>
            a.room.sortOrder - b.room.sortOrder ||
            a.room.roomNumber.localeCompare(b.room.roomNumber),
        );
    });
  }

  async listRooms(
    locale: LocaleResolution,
    filters: RoomFilters,
  ): Promise<{ data: RoomDto[]; translationFallback: boolean }> {
    const mapped = (await this.loadRooms(locale.resolvedLocale)).filter(({ room }) => {
      if (filters.buildingKey && room.buildingKey !== filters.buildingKey) return false;
      if (filters.floorKey && room.floorKey !== filters.floorKey) return false;
      return true;
    });

    return {
      data: mapped.map(({ room }) => room),
      translationFallback: mapped.some(({ fallback }) => fallback),
    };
  }

  async getRoom(
    locale: LocaleResolution,
    roomKey: string,
  ): Promise<{ data: RoomDto; translationFallback: boolean }> {
    const mapped = (await this.loadRooms(locale.resolvedLocale)).find(
      ({ room }) => room.roomKey === roomKey,
    );
    if (!mapped) throw new ApiError('ROOM_NOT_FOUND', locale.resolvedLocale);
    return { data: mapped.room, translationFallback: mapped.fallback };
  }
}

/** Maps Strapi room relations to compact, catalogue-enriched references. */
export function mapRoomReferences(
  value: unknown,
  locale: Locale,
): { rooms: RoomReferenceDto[]; fallback: boolean } {
  if (!Array.isArray(value)) return { rooms: [], fallback: false };

  let fallback = false;
  const rooms: RoomReferenceDto[] = [];

  for (const entry of value) {
    if (!isRecord(entry)) continue;
    if (entry['catalogActive'] === false || entry['isVisible'] === false) continue;

    const roomKey = str(entry['roomKey']);
    if (!roomKey) continue;
    const technical = catalogRoom(roomKey);
    if (!technical) continue;

    const displayName = localisedEditorial(entry, 'displayName', locale);
    if (displayName.fallback) fallback = true;

    rooms.push({
      roomKey,
      roomNumber: technical.roomNumber,
      buildingNumber: technical.buildingNumber,
      buildingName: localisedCatalogName(technical, 'buildingName', locale),
      floorName: localisedCatalogName(technical, 'floorName', locale),
      displayName: displayName.value,
    });
  }

  rooms.sort((a, b) => a.roomNumber.localeCompare(b.roomNumber));
  return { rooms, fallback };
}
