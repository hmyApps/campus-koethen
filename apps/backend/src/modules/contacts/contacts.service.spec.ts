import { StrapiClient, StrapiRequestError } from '../strapi/strapi.client';
import { ContactsService } from './contacts.service';

function makeClient(handler: (query: Record<string, unknown>) => unknown) {
  return {
    get: jest.fn(async (_path: string, query: Record<string, unknown>) => handler(query)),
  } as unknown as StrapiClient;
}

const area = (slug: string, over: Record<string, unknown> = {}) => ({
  slug,
  name: slug,
  shortDescription: 'kurz',
  iconKey: 'service',
  sortOrder: 0,
  isActive: true,
  persons: [],
  ...over,
});

const de = { requestedLocale: 'de', resolvedLocale: 'de' } as const;
const en = { requestedLocale: 'en', resolvedLocale: 'en' } as const;

describe('ContactsService', () => {
  describe('listAreas', () => {
    it('sorts by sortOrder then name', async () => {
      const client = makeClient(() => ({
        data: [
          area('b', { sortOrder: 20, name: 'B' }),
          area('a', { sortOrder: 10, name: 'A' }),
          area('c', { sortOrder: 20, name: 'A-first' }),
        ],
      }));

      const result = await new ContactsService(client).listAreas(de);
      expect(result.data.map((a) => a.slug)).toEqual(['a', 'c', 'b']);
    });

    it('reports an area without persons as fully valid with personCount 0', async () => {
      const client = makeClient(() => ({ data: [area('ssc', { persons: [] })] }));

      const result = await new ContactsService(client).listAreas(de);

      expect(result.data[0]!.personCount).toBe(0);
      expect(result.data[0]!.slug).toBe('ssc');
    });

    it('counts only ACTIVE persons', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            persons: [
              { name: 'A', isActive: true },
              { name: 'B', isActive: false },
              { name: 'C', isActive: true },
            ],
          }),
        ],
      }));

      const result = await new ContactsService(client).listAreas(de);
      expect(result.data[0]!.personCount).toBe(2);
    });

    it('counts exactly the persons the detail endpoint would deliver', async () => {
      // personCount is derived without building the person DTOs. The rule it
      // applies must stay the delivery rule, so this pins it against the
      // endpoint that actually delivers them.
      const persons = [
        { name: 'Aktiv ohne Flag' },
        { name: 'Aktiv mit Flag', isActive: true },
        { name: 'Inaktiv', isActive: false },
        { name: '   ', isActive: true },
        { name: '', isActive: true },
        { role: 'Ohne Namen', isActive: true },
        { name: 42, isActive: true },
        null,
        'kein Objekt',
        ['auch kein Objekt'],
      ];
      const client = makeClient(() => ({ data: [area('x', { persons })] }));
      const service = new ContactsService(client);

      const list = await service.listAreas(de);
      const detail = await service.getArea(de, 'x');

      // The detail endpoint sorts by sortOrder, then by name.
      expect(detail.data.persons.map((person) => person.name)).toEqual([
        'Aktiv mit Flag',
        'Aktiv ohne Flag',
      ]);
      expect(list.data[0]!.personCount).toBe(detail.data.persons.length);
      expect(list.data[0]!.personCount).toBe(2);
    });

    it('counts nothing when the relation is absent or not a list', async () => {
      for (const persons of [undefined, null, 'nope', 7, {}]) {
        const client = makeClient(() => ({ data: [area('x', { persons })] }));
        const result = await new ContactsService(client).listAreas(de);
        expect(result.data[0]!.personCount).toBe(0);
      }
    });

    it('requests only active areas', async () => {
      const seen: Record<string, unknown>[] = [];
      const client = makeClient((query) => {
        seen.push(query);
        return { data: [] };
      });

      await new ContactsService(client).listAreas(de);
      expect(JSON.stringify(seen[0])).toContain('isActive');
    });

    it('keeps German text and flags fallback when English is missing', async () => {
      const client = makeClient((query) =>
        query['locale'] === 'en' ? { data: [] } : { data: [area('x', { name: 'Deutsch' })] },
      );

      const result = await new ContactsService(client).listAreas(en);

      expect(result.data[0]!.name).toBe('Deutsch');
      expect(result.translationFallback).toBe(true);
    });

    it('maps an upstream timeout to a 504', async () => {
      const client = {
        get: jest.fn(async () => {
          throw new StrapiRequestError('timeout', 'nope');
        }),
      } as unknown as StrapiClient;

      await expect(new ContactsService(client).listAreas(de)).rejects.toMatchObject({
        code: 'UPSTREAM_TIMEOUT',
      });
    });
  });

  describe('field hygiene', () => {
    it('drops unusable contact fields instead of forwarding them', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            generalEmail: 'not-an-email',
            website: 'http://insecure.example',
            appointmentBookingUrl: 'ftp://x',
            phone: '   ',
          }),
        ],
      }));

      const result = await new ContactsService(client).listAreas(de);
      const item = result.data[0]!;

      expect(item.generalEmail).toBeNull();
      expect(item.website).toBeNull();
      expect(item.appointmentBookingUrl).toBeNull();
      expect(item.phone).toBeNull();
    });

    it('keeps valid contact fields', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            generalEmail: 'kontakt@example.org',
            website: 'https://example.org',
            phone: '+49 3496 000',
          }),
        ],
      }));

      const item = (await new ContactsService(client).listAreas(de)).data[0]!;

      expect(item.generalEmail).toBe('kontakt@example.org');
      expect(item.website).toBe('https://example.org');
      expect(item.phone).toBe('+49 3496 000');
    });

    it('publishes an area image on this API, never on the CMS', () => {
      // Strapi's local provider hands back a relative path, which is why no
      // image ever reached the app; and the client must not talk to the CMS
      // at all (AGENTS.md §2.1).
      const client = makeClient(() => ({
        data: [area('x', { image: { url: '/uploads/team_5a141d.jpg' } })],
      }));

      return new ContactsService(client).listAreas(de).then((result) => {
        expect(result.data[0]!.image).toBe('/v1/media/uploads/team_5a141d.jpg');
      });
    });

    it('has a null image when the area has none', async () => {
      const client = makeClient(() => ({ data: [area('x')] }));

      const item = (await new ContactsService(client).listAreas(de)).data[0]!;

      expect(item.image).toBeNull();
    });

    it('drops an image that is not an upload of the CMS', async () => {
      const client = makeClient(() => ({
        data: [area('x', { image: { url: 'https://cdn.example/etc/passwd' } })],
      }));

      const item = (await new ContactsService(client).listAreas(de)).data[0]!;

      expect(item.image).toBeNull();
    });

    it('publishes a person photo on this API too', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            persons: [
              {
                name: 'Testperson',
                isActive: true,
                profileImage: { url: '/uploads/face_abc.jpg' },
              },
            ],
          }),
        ],
      }));

      const detail = await new ContactsService(client).getArea(de, 'x');

      expect(detail.data.persons[0]!.profileImage).toBe('/v1/media/uploads/face_abc.jpg');
    });

    it('never leaks Strapi internals', async () => {
      const client = makeClient(() => ({
        data: [area('x', { documentId: 'doc_1', localizations: [{ id: 2 }] })],
      }));

      const result = await new ContactsService(client).listAreas(de);
      const serialized = JSON.stringify(result.data);

      expect(serialized).not.toContain('documentId');
      expect(serialized).not.toContain('localizations');
    });
  });

  describe('getArea', () => {
    it('returns an area with its active persons sorted', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            description: [{ type: 'paragraph', children: [{ type: 'text', text: 'Info' }] }],
            persons: [
              { name: 'Zeta', isActive: true, sortOrder: 20 },
              { name: 'Alpha', isActive: true, sortOrder: 10 },
              { name: 'Hidden', isActive: false, sortOrder: 1 },
            ],
          }),
        ],
      }));

      const result = await new ContactsService(client).getArea(de, 'x');

      expect(result.data.persons.map((p) => p.name)).toEqual(['Alpha', 'Zeta']);
      expect(result.data.description).toHaveLength(1);
    });

    it('works for an area with no persons at all', async () => {
      const client = makeClient(() => ({ data: [area('studentenwerk', { persons: [] })] }));

      const result = await new ContactsService(client).getArea(de, 'studentenwerk');

      expect(result.data.persons).toEqual([]);
      expect(result.data.slug).toBe('studentenwerk');
    });

    it('raises a 404 for an unknown slug', async () => {
      const client = makeClient(() => ({ data: [] }));

      await expect(new ContactsService(client).getArea(de, 'nope')).rejects.toMatchObject({
        code: 'CONTACT_AREA_NOT_FOUND',
      });
    });

    it('drops unknown description block types and reports them', async () => {
      const client = makeClient(() => ({
        data: [area('x', { description: [{ type: 'paragraph' }, { type: 'future-thing' }] })],
      }));

      const result = await new ContactsService(client).getArea(de, 'x');
      expect(result.droppedBlockTypes).toEqual(['future-thing']);
    });

    it('serves repeat requests from the detail cache', async () => {
      let calls = 0;
      const client = makeClient(() => {
        calls += 1;
        return { data: [area('x')] };
      });
      const service = new ContactsService(client);

      await service.getArea(de, 'x');
      await service.getArea(de, 'x');

      expect(calls).toBe(1);
    });
  });

  describe('room references', () => {
    const mapRoom = (over: Record<string, unknown> = {}) => ({
      roomKey: 'ratke-gebaeude-first-floor-216',
      catalogActive: true,
      isVisible: true,
      ...over,
    });

    it('serves an empty room list for an area without rooms', async () => {
      const client = makeClient(() => ({ data: [area('ssc')] }));
      const result = await new ContactsService(client).getArea(de, 'ssc');
      expect(result.data.rooms).toEqual([]);
    });

    it('serves an empty room list for a person without rooms', async () => {
      const client = makeClient(() => ({
        data: [area('x', { persons: [{ name: 'A', isActive: true }] })],
      }));
      const result = await new ContactsService(client).getArea(de, 'x');
      expect(result.data.persons[0]!.rooms).toEqual([]);
    });

    it('maps the rooms of an area', async () => {
      const client = makeClient(() => ({ data: [area('x', { rooms: [mapRoom()] })] }));
      const result = await new ContactsService(client).getArea(de, 'x');

      expect(result.data.rooms).toHaveLength(1);
      expect(result.data.rooms[0]).toMatchObject({
        roomKey: 'ratke-gebaeude-first-floor-216',
        roomNumber: '216',
        buildingNumber: '23',
        buildingName: 'Ratke-Gebäude',
        floorName: '1. Obergeschoss',
      });
    });

    it('maps the rooms of a person', async () => {
      const client = makeClient(() => ({
        data: [area('x', { persons: [{ name: 'A', isActive: true, rooms: [mapRoom()] }] })],
      }));
      const result = await new ContactsService(client).getArea(de, 'x');
      expect(result.data.persons[0]!.rooms[0]!.roomKey).toBe('ratke-gebaeude-first-floor-216');
    });

    it('localises room names for en', async () => {
      const client = makeClient(() => ({ data: [area('x', { rooms: [mapRoom()] })] }));
      const result = await new ContactsService(client).getArea(en, 'x');

      expect(result.data.rooms[0]!.buildingName).toBe('Ratke Building');
      expect(result.data.rooms[0]!.buildingNumber).toBe('23');
      expect(result.data.rooms[0]!.floorName).toBe('First floor');
    });

    it('hides a deactivated or invisible room even through a relation', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            rooms: [
              mapRoom({ roomKey: 'gone', catalogActive: false }),
              mapRoom({ roomKey: 'hidden', isVisible: false }),
              mapRoom(),
            ],
          }),
        ],
      }));

      const result = await new ContactsService(client).getArea(de, 'x');
      expect(result.data.rooms.map((r) => r.roomKey)).toEqual(['ratke-gebaeude-first-floor-216']);
    });

    it('never exposes a Strapi id through a room reference', async () => {
      const client = makeClient(() => ({
        data: [area('x', { rooms: [{ ...mapRoom(), id: 42, documentId: 'doc-42' }] })],
      }));

      const result = await new ContactsService(client).getArea(de, 'x');
      const serialised = JSON.stringify(result.data.rooms);
      expect(serialised).not.toContain('documentId');
      expect(serialised).not.toContain('doc-42');
    });
  });

  describe('searchIndex', () => {
    const mapRoom = (over: Record<string, unknown> = {}) => ({
      roomKey: 'ratke-gebaeude-first-floor-216',
      catalogActive: true,
      isVisible: true,
      ...over,
    });

    const paragraph = (text: string) => ({
      type: 'paragraph',
      children: [{ type: 'text', text }],
    });

    it('answers with ONE request per locale, not one per area', async () => {
      // The whole reason this endpoint exists: a client searching over details
      // would otherwise fetch every area separately, on every keystroke.
      let calls = 0;
      const client = makeClient(() => {
        calls += 1;
        return { data: [area('a'), area('b'), area('c')] };
      });

      const result = await new ContactsService(client).searchIndex(de);

      expect(calls).toBe(1);
      expect(result.data).toHaveLength(3);
    });

    it('serves a repeat request from the cache instead of rebuilding the index', async () => {
      // The heaviest read in this API — every area with every person and every
      // room — over data an editor changes a few times a month.
      let calls = 0;
      const client = makeClient(() => {
        calls += 1;
        return { data: [area('a')] };
      });
      const service = new ContactsService(client);

      await service.searchIndex(de);
      await service.searchIndex(de);

      expect(calls).toBe(1);
    });

    it('caches per locale, so German never answers an English request', async () => {
      const client = makeClient((query) => ({
        data: [area('a', { name: query['locale'] === 'en' ? 'English' : 'Deutsch' })],
      }));
      const service = new ContactsService(client);

      expect((await service.searchIndex(de)).data[0]!.name).toBe('Deutsch');
      expect((await service.searchIndex(en)).data[0]!.name).toBe('English');
    });

    it('does not cache a failure', async () => {
      let attempt = 0;
      const client = {
        get: jest.fn(async () => {
          attempt += 1;
          if (attempt === 1) throw new StrapiRequestError('unavailable', 'Strapi is unreachable');
          return { data: [area('a')] };
        }),
      } as unknown as StrapiClient;
      const service = new ContactsService(client);

      await expect(service.searchIndex(de)).rejects.toThrow();
      await expect(service.searchIndex(de)).resolves.toMatchObject({
        data: [expect.objectContaining({ slug: 'a' })],
      });
    });

    it('carries every visible field the search has to match', async () => {
      const client = makeClient(() => ({
        data: [
          area('ssc', {
            name: 'Studierendenservice',
            shortDescription: 'Beratung',
            generalEmail: 'kontakt@example.org',
            phone: '+49 000 000',
            website: 'https://example.org',
            appointmentBookingUrl: 'https://example.org/termin',
            address: 'Musterweg 1',
            openingHours: 'Mo–Fr',
            description: [paragraph('Wir helfen bei Anträgen.')],
            rooms: [mapRoom()],
            persons: [
              {
                name: 'Demo Person',
                role: 'Beratung',
                description: 'Zuständig für Anträge',
                email: 'person@example.org',
                phone: '+49 111',
                website: 'https://example.org/person',
                isActive: true,
                rooms: [mapRoom({ roomKey: 'ratke-gebaeude-first-floor-218' })],
              },
            ],
          }),
        ],
      }));

      const entry = (await new ContactsService(client).searchIndex(de)).data[0]!;

      expect(entry).toMatchObject({
        slug: 'ssc',
        name: 'Studierendenservice',
        shortDescription: 'Beratung',
        generalEmail: 'kontakt@example.org',
        phone: '+49 000 000',
        website: 'https://example.org',
        appointmentBookingUrl: 'https://example.org/termin',
        address: 'Musterweg 1',
        openingHours: 'Mo–Fr',
        descriptionText: 'Wir helfen bei Anträgen.',
      });
      expect(entry.rooms[0]!.roomNumber).toBe('216');
      expect(entry.persons[0]).toMatchObject({
        name: 'Demo Person',
        role: 'Beratung',
        description: 'Zuständig für Anträge',
        email: 'person@example.org',
      });
      expect(entry.persons[0]!.rooms[0]!.roomNumber).toBe('218');
    });

    it('flattens the description instead of shipping rich text', async () => {
      // A search matches words. Formatting carries none, a link contributes its
      // label rather than its URL, and an image contributes nothing.
      const client = makeClient(() => ({
        data: [
          area('x', {
            description: [
              { type: 'heading', level: 2, children: [{ type: 'text', text: 'Überblick' }] },
              {
                type: 'paragraph',
                children: [
                  { type: 'text', text: 'Mehr auf ' },
                  {
                    type: 'link',
                    url: 'https://example.org/sehr/lang',
                    children: [{ type: 'text', text: 'der Website' }],
                  },
                ],
              },
              { type: 'image', image: { url: 'https://example.org/a.png' } },
            ],
          }),
        ],
      }));

      const entry = (await new ContactsService(client).searchIndex(de)).data[0]!;

      expect(entry.descriptionText).toBe('Überblick\nMehr auf der Website');
      expect(entry.descriptionText).not.toContain('https://');
    });

    it('drops a block type the sanitiser does not know', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            description: [{ type: 'video', url: 'https://example.org/v.mp4' }, paragraph('Text')],
          }),
        ],
      }));

      const entry = (await new ContactsService(client).searchIndex(de)).data[0]!;
      expect(entry.descriptionText).toBe('Text');
    });

    it('includes only ACTIVE persons', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            persons: [
              { name: 'Aktiv', isActive: true },
              { name: 'Inaktiv', isActive: false },
            ],
          }),
        ],
      }));

      const entry = (await new ContactsService(client).searchIndex(de)).data[0]!;
      expect(entry.persons.map((p) => p.name)).toEqual(['Aktiv']);
    });

    it('requests only active areas', async () => {
      const seen: Record<string, unknown>[] = [];
      const client = makeClient((query) => {
        seen.push(query);
        return { data: [] };
      });

      await new ContactsService(client).searchIndex(de);
      expect(JSON.stringify(seen[0])).toContain('isActive');
    });

    it('leaks no Strapi internals', async () => {
      const client = makeClient(() => ({
        data: [
          {
            id: 7,
            documentId: 'doc-7',
            ...area('x', {
              persons: [{ id: 9, documentId: 'doc-9', name: 'Demo Person', isActive: true }],
              rooms: [{ ...mapRoom(), id: 42, documentId: 'doc-42' }],
            }),
          },
        ],
      }));

      const serialised = JSON.stringify((await new ContactsService(client).searchIndex(de)).data);

      expect(serialised).not.toContain('documentId');
      expect(serialised).not.toContain('doc-7');
      expect(serialised).not.toContain('attributes');
    });

    it('carries no profile image — nobody searches for a picture', async () => {
      const client = makeClient(() => ({
        data: [
          area('x', {
            persons: [
              {
                name: 'Demo Person',
                isActive: true,
                profileImage: { url: 'https://example.org/face.jpg' },
              },
            ],
          }),
        ],
      }));

      const serialised = JSON.stringify((await new ContactsService(client).searchIndex(de)).data);
      expect(serialised).not.toContain('face.jpg');
      expect(serialised).not.toContain('profileImage');
    });

    it('keeps German text and flags the fallback when English is missing', async () => {
      const client = makeClient((query) =>
        query['locale'] === 'en' ? { data: [] } : { data: [area('x', { name: 'Deutsch' })] },
      );

      const result = await new ContactsService(client).searchIndex(en);

      expect(result.data[0]!.name).toBe('Deutsch');
      expect(result.translationFallback).toBe(true);
    });

    it('localises room names for en', async () => {
      const client = makeClient(() => ({ data: [area('x', { rooms: [mapRoom()] })] }));
      const result = await new ContactsService(client).searchIndex(en);

      expect(result.data[0]!.rooms[0]!.buildingName).toBe('Ratke Building');
      expect(result.data[0]!.rooms[0]!.buildingNumber).toBe('23');
      expect(result.data[0]!.rooms[0]!.floorName).toBe('First floor');
    });
  });

  /**
   * Strapi 5 localises every relation between localised types: the English
   * contact area carries its OWN person list, which an editor may never have
   * linked. The list counted persons from the German relation while detail and
   * search took the English one, so an English reader could see "2 persons" on
   * the card and then an empty area — without any translation fallback flag.
   *
   * WHICH persons exist therefore comes from the canonical relation everywhere;
   * the translation contributes only `role` and `description`, matched by the
   * person's documentId, which never leaves this service.
   */
  describe('English persons come from the canonical relation', () => {
    const demoA = {
      documentId: 'demo-person-a',
      name: 'Demo Person A',
      role: 'Demo-Studienberatung',
      description: 'Demo: berät zum Studium.',
      isActive: true,
      sortOrder: 10,
    };
    const demoB = {
      documentId: 'demo-person-b',
      name: 'Demo Person B',
      role: 'Demo-Sekretariat',
      isActive: true,
      sortOrder: 20,
    };

    function byLocale(deRow: Record<string, unknown>, enRow: Record<string, unknown> | null) {
      return makeClient((query) =>
        query['locale'] === 'en' ? { data: enRow ? [enRow] : [] } : { data: [deRow] },
      );
    }

    it('keeps the German persons when the English area has none linked', async () => {
      const client = byLocale(
        area('x', { persons: [demoA, demoB] }),
        area('x', { name: 'English', persons: [] }),
      );

      const result = await new ContactsService(client).getArea(en, 'x');

      expect(result.data.persons.map((p) => p.name)).toEqual(['Demo Person A', 'Demo Person B']);
      expect(result.data.persons.map((p) => p.role)).toEqual([
        'Demo-Studienberatung',
        'Demo-Sekretariat',
      ]);
      expect(result.translationFallback).toBe(true);
    });

    it('overlays only role and description, matched by documentId', async () => {
      const client = byLocale(
        area('x', { persons: [demoA, demoB] }),
        area('x', {
          name: 'English',
          persons: [
            // Different order, a different (stale) name and an English-only
            // person: none of that may decide what the reader sees.
            {
              documentId: 'demo-person-b',
              name: 'Stale Name',
              role: 'Demo office',
              isActive: true,
              sortOrder: 99,
            },
            {
              documentId: 'demo-person-a',
              name: 'Demo Person A',
              role: 'Demo student advisory',
              description: 'Demo: advises on studying.',
              isActive: true,
              sortOrder: 10,
            },
            {
              documentId: 'demo-person-x',
              name: 'Demo Person X',
              role: 'Only linked in English',
              isActive: true,
            },
          ],
        }),
      );

      const result = await new ContactsService(client).getArea(en, 'x');

      expect(result.data.persons).toEqual([
        expect.objectContaining({
          name: 'Demo Person A',
          role: 'Demo student advisory',
          description: 'Demo: advises on studying.',
          sortOrder: 10,
        }),
        expect.objectContaining({ name: 'Demo Person B', role: 'Demo office', sortOrder: 20 }),
      ]);
      expect(result.translationFallback).toBe(false);
      const serialised = JSON.stringify(result);
      expect(serialised).not.toContain('documentId');
      expect(serialised).not.toContain('demo-person-a');
    });

    it('keeps the German text of a person whose translation is missing and says so', async () => {
      const client = byLocale(
        area('x', { persons: [demoA, demoB] }),
        area('x', {
          name: 'English',
          persons: [
            {
              documentId: 'demo-person-a',
              name: 'Demo Person A',
              role: 'Demo student advisory',
              description: 'Demo: advises on studying.',
              isActive: true,
            },
            { documentId: 'demo-person-b', name: 'Demo Person B', role: '', isActive: true },
          ],
        }),
      );

      const result = await new ContactsService(client).getArea(en, 'x');

      expect(result.data.persons.map((p) => p.role)).toEqual([
        'Demo student advisory',
        'Demo-Sekretariat',
      ]);
      expect(result.translationFallback).toBe(true);
    });

    it('does not flag a fallback for a person that is never delivered', async () => {
      const client = byLocale(
        area('x', { persons: [demoA, { ...demoB, isActive: false }] }),
        area('x', {
          name: 'English',
          persons: [
            {
              documentId: 'demo-person-a',
              name: 'Demo Person A',
              role: 'Demo student advisory',
              description: 'Demo: advises on studying.',
              isActive: true,
            },
          ],
        }),
      );

      const result = await new ContactsService(client).getArea(en, 'x');

      expect(result.data.persons.map((p) => p.name)).toEqual(['Demo Person A']);
      expect(result.translationFallback).toBe(false);
    });

    it('builds the English search index from the same persons', async () => {
      const client = byLocale(
        area('x', { persons: [demoA, demoB] }),
        area('x', { name: 'English', persons: [] }),
      );

      const result = await new ContactsService(client).searchIndex(en);

      expect(result.data[0]!.persons.map((p) => p.name)).toEqual([
        'Demo Person A',
        'Demo Person B',
      ]);
      expect(result.translationFallback).toBe(true);
    });

    it('counts in the list exactly the persons the English detail delivers', async () => {
      const deRow = area('x', { persons: [demoA, demoB] });
      const enRow = area('x', { name: 'English', persons: [{ ...demoA }] });

      const list = await new ContactsService(byLocale(deRow, enRow)).listAreas(en);
      const detail = await new ContactsService(byLocale(deRow, enRow)).getArea(en, 'x');

      expect(list.data[0]!.personCount).toBe(detail.data.persons.length);
      expect(detail.data.persons).toHaveLength(2);
    });

    it('leaves German reads untouched', async () => {
      const client = byLocale(area('x', { persons: [demoA, demoB] }), null);

      const result = await new ContactsService(client).getArea(de, 'x');

      expect(result.data.persons.map((p) => p.role)).toEqual([
        'Demo-Studienberatung',
        'Demo-Sekretariat',
      ]);
      expect(result.translationFallback).toBe(false);
    });
  });
});
