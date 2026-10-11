import { ApiError } from '../../common/errors/api-error';
import { StrapiClient, StrapiRequestError } from '../strapi/strapi.client';
import { RoomsService } from './rooms.service';

function makeClient(handler: (query: Record<string, unknown>) => unknown) {
  return {
    get: jest.fn(async (_path: string, query: Record<string, unknown>) => handler(query)),
  } as unknown as StrapiClient;
}

const room = (roomKey: string, over: Record<string, unknown> = {}) => ({
  roomKey,
  catalogActive: true,
  isVisible: true,
  ...over,
});

const groundFloorRoom = 'ratke-gebaeude-ground-floor-101';
const anotherFirstFloorRoom = 'ratke-gebaeude-first-floor-210';
const firstFloorRoom = 'ratke-gebaeude-first-floor-216';
const de = { requestedLocale: 'de', resolvedLocale: 'de' } as const;
const en = { requestedLocale: 'en', resolvedLocale: 'en' } as const;

describe('RoomsService', () => {
  describe('listRooms', () => {
    it('serves German technical labels from the bundled catalogue', async () => {
      const client = makeClient(() => ({ data: [room(firstFloorRoom)] }));
      const result = await new RoomsService(client).listRooms(de, {});

      expect(result.data[0]).toMatchObject({
        roomNumber: '216',
        buildingNumber: '23',
        buildingName: 'Ratke-Gebäude',
        floorName: '1. Obergeschoss',
      });
      expect(result.translationFallback).toBe(false);
    });

    it('serves English technical labels from the bundled catalogue', async () => {
      const client = makeClient(() => ({ data: [room(firstFloorRoom)] }));
      const result = await new RoomsService(client).listRooms(en, {});

      expect(result.data[0]).toMatchObject({
        buildingNumber: '23',
        buildingName: 'Ratke Building',
        floorName: 'First floor',
      });
      expect(result.translationFallback).toBe(false);
    });

    it('falls back to German editorial text and flags it', async () => {
      const client = makeClient(() => ({
        data: [room(firstFloorRoom, { displayNameDe: 'Hörsaal', displayNameEn: null })],
      }));
      const result = await new RoomsService(client).listRooms(en, {});

      expect(result.data[0]!.displayName).toBe('Hörsaal');
      expect(result.translationFallback).toBe(true);
    });

    it('does not flag a fallback when no editorial translation exists', async () => {
      const client = makeClient(() => ({ data: [room(firstFloorRoom)] }));
      const result = await new RoomsService(client).listRooms(en, {});
      expect(result.translationFallback).toBe(false);
    });

    it('requests only active and visible Strapi overlays', async () => {
      const seen: Record<string, unknown>[] = [];
      const client = makeClient((query) => {
        seen.push(query);
        return { data: [] };
      });

      await new RoomsService(client).listRooms(de, {});

      expect(seen[0]!.filters).toMatchObject({
        catalogActive: { $eq: true },
        isVisible: { $eq: true },
      });
      expect(seen[0]!.fields).toEqual([
        'roomKey',
        'displayNameDe',
        'displayNameEn',
        'descriptionDe',
        'descriptionEn',
      ]);
    });

    it('loads every Strapi page instead of stopping at the REST limit', async () => {
      const pages = new Map<number, string[]>([
        [1, [groundFloorRoom]],
        [2, [anotherFirstFloorRoom]],
        [3, [firstFloorRoom]],
      ]);
      const client = makeClient((query) => {
        const pagination = query.pagination as { page?: number; pageSize?: number };
        const page = pagination.page ?? 1;
        return {
          data: (pages.get(page) ?? []).map((roomKey) => room(roomKey)),
          meta: {
            pagination: { page, pageSize: 100, pageCount: 3, total: 3 },
          },
        };
      });

      const result = await new RoomsService(client).listRooms(de, {});

      expect(result.data.map((entry) => entry.roomKey)).toEqual(
        expect.arrayContaining([groundFloorRoom, anotherFirstFloorRoom, firstFloorRoom]),
      );
      expect(result.data).toHaveLength(3);
      const calls = (client.get as jest.Mock).mock.calls;
      expect(calls).toHaveLength(3);
      for (const [, query] of calls) {
        expect(query.pagination.pageSize).toBe(100);
      }
    });

    it('applies building and floor filters against the bundled catalogue', async () => {
      const client = makeClient(() => ({
        data: [room(groundFloorRoom), room(firstFloorRoom)],
      }));
      const service = new RoomsService(client);

      const result = await service.listRooms(de, {
        buildingKey: 'ratke-gebaeude',
        floorKey: 'ratke-gebaeude-first-floor',
      });

      expect(result.data.map((entry) => entry.roomKey)).toEqual([firstFloorRoom]);
    });

    it('caches the unfiltered Strapi overlays per locale', async () => {
      let upstreamCalls = 0;
      const client = makeClient(() => {
        upstreamCalls += 1;
        return { data: [room(groundFloorRoom)] };
      });
      const service = new RoomsService(client);

      for (let i = 0; i < 50; i += 1) {
        await service.listRooms(de, { buildingKey: `unknown-${i}` });
      }
      await service.listRooms(de, {});
      await service.listRooms(en, {});
      await service.listRooms(en, { floorKey: 'ratke-gebaeude-ground-floor' });

      expect(upstreamCalls).toBe(2);
      expect(service.cachedCatalogues).toBeLessThanOrEqual(2);
    });

    it('sorts using the canonical catalogue order', async () => {
      const client = makeClient(() => ({
        data: [room(firstFloorRoom), room(groundFloorRoom)],
      }));

      const result = await new RoomsService(client).listRooms(de, {});
      expect(result.data.map((entry) => entry.roomKey)).toEqual([groundFloorRoom, firstFloorRoom]);
    });

    it('drops unknown or missing room keys', async () => {
      const client = makeClient(() => ({
        data: [room(groundFloorRoom), room('not-in-catalogue'), { displayNameDe: 'X' }],
      }));
      const result = await new RoomsService(client).listRooms(de, {});
      expect(result.data.map((entry) => entry.roomKey)).toEqual([groundFloorRoom]);
    });

    it('leaks no Strapi internals', async () => {
      const client = makeClient(() => ({
        data: [
          {
            ...room(groundFloorRoom),
            documentId: 'strapi-doc-id',
            id: 17,
            createdAt: 'x',
            contactPersons: [{ id: 3, name: 'X' }],
          },
        ],
      }));

      const serialised = JSON.stringify((await new RoomsService(client).listRooms(de, {})).data);
      for (const forbidden of ['documentId', 'createdAt', 'strapi-doc-id']) {
        expect(serialised).not.toContain(forbidden);
      }
    });

    it('treats a 200 answer without a data list as an upstream failure', async () => {
      let attempt = 0;
      const client = makeClient(() => {
        attempt += 1;
        return attempt === 1 ? { meta: {} } : { data: [room(firstFloorRoom)] };
      });
      const service = new RoomsService(client);

      await expect(service.listRooms(de, {})).rejects.toMatchObject({
        code: 'UPSTREAM_UNAVAILABLE',
      });
      // Nothing was cached as an empty catalogue.
      await expect(service.listRooms(de, {})).resolves.toMatchObject({
        data: [expect.objectContaining({ roomKey: firstFloorRoom })],
      });
    });

    it('maps an upstream timeout to UPSTREAM_TIMEOUT', async () => {
      const client = {
        get: jest.fn(async () => {
          throw new StrapiRequestError('timeout', 'timed out');
        }),
      } as unknown as StrapiClient;

      await expect(new RoomsService(client).listRooms(de, {})).rejects.toBeInstanceOf(ApiError);
    });
  });

  describe('getRoom', () => {
    it('returns the requested room', async () => {
      const client = makeClient(() => ({ data: [room(firstFloorRoom)] }));
      const result = await new RoomsService(client).getRoom(de, firstFloorRoom);
      expect(result.data.roomKey).toBe(firstFloorRoom);
    });

    it('rejects an unknown roomKey with ROOM_NOT_FOUND', async () => {
      const client = makeClient(() => ({ data: [] }));
      await expect(new RoomsService(client).getRoom(de, 'nope')).rejects.toMatchObject({
        code: 'ROOM_NOT_FOUND',
      });
    });

    it('never serves an overlay omitted by the visibility query', async () => {
      const seen: Record<string, unknown>[] = [];
      const client = makeClient((query) => {
        seen.push(query);
        return { data: [] };
      });

      await expect(new RoomsService(client).getRoom(de, firstFloorRoom)).rejects.toBeInstanceOf(
        ApiError,
      );
      expect(seen[0]!.filters).toMatchObject({
        catalogActive: { $eq: true },
        isVisible: { $eq: true },
      });
    });
  });
});
