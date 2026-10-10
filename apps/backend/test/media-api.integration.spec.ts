import { INestApplication, VersioningType } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AllExceptionsFilter } from '../src/common/filters/all-exceptions.filter';
import { ENV } from '../src/config/app-config.module';
import { Env } from '../src/config/env.schema';
import { MediaController } from '../src/modules/media/media.controller';
import { MediaService } from '../src/modules/media/media.service';

/**
 * The conditional-request contract over real HTTP.
 *
 * Worth being precise about what changed, because Express already did half of
 * it: `res.send()` performs its own freshness check, so a client sending a
 * matching `If-None-Match` ALWAYS got a 304 with no body. What it did not get
 * was any saving on the other leg — the API fetched and buffered the whole
 * image from the CMS first, every single time, and then threw it away.
 *
 * So these tests assert both halves: the answer the client sees is unchanged,
 * and no bytes are pulled from the CMS to produce it.
 *
 * Only the CMS is stubbed; the controller, the filter and the HTTP layer are
 * real. No database is involved on this route.
 */
describe('/v1/media (integration)', () => {
  let app: INestApplication;
  let fetchMock: jest.SpyInstance;

  const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
  const ETAG = 'W/"1f-18c2b4d1e20"';

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [MediaController],
      providers: [
        MediaService,
        {
          provide: ENV,
          useValue: {
            STRAPI_BASE_URL: 'http://cms.internal:1337',
            STRAPI_TIMEOUT_MS: 1_000,
          } as Partial<Env>,
        },
      ],
    }).compile();

    app = moduleRef.createNestApplication({ logger: false });
    app.enableVersioning({ type: VersioningType.URI, prefix: 'v' });
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  afterEach(() => {
    fetchMock?.mockRestore();
  });

  /**
   * Stands in for the CMS: 304 when the validator matches, bytes otherwise —
   * and it counts what it actually had to send.
   */
  function stubCms(storedEtag: string | null = ETAG): { bytesServed: number } {
    const served = { bytesServed: 0 };
    fetchMock = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation(async (_input, init?: RequestInit) => {
        const headers = (init?.headers ?? {}) as Record<string, string>;
        if (storedEtag !== null && headers['If-None-Match'] === storedEtag) {
          return new Response(null, { status: 304, headers: { etag: storedEtag } });
        }
        served.bytesServed += PNG.byteLength;
        return new Response(new Uint8Array(PNG), {
          status: 200,
          headers: {
            'content-type': 'image/png',
            ...(storedEtag === null ? {} : { etag: storedEtag }),
          },
        });
      });
    return served;
  }

  it('serves the image and publishes a validator', async () => {
    stubCms();

    const res = await request(app.getHttpServer())
      .get('/v1/media/uploads/foto_5a141d3978.png')
      .expect(200);

    expect(res.headers['etag']).toBe(ETAG);
    expect(res.headers['content-type']).toContain('image/png');
    expect(res.headers['cache-control']).toBe('public, max-age=86400');
    expect(Buffer.from(res.body as Buffer)).toEqual(PNG);
  });

  it('answers 304 without pulling the image from the CMS', async () => {
    const served = stubCms();

    const res = await request(app.getHttpServer())
      .get('/v1/media/uploads/foto_5a141d3978.png')
      .set('If-None-Match', ETAG)
      .expect(304);

    expect(res.headers['etag']).toBe(ETAG);
    expect(res.headers['cache-control']).toBe('public, max-age=86400');
    expect(res.body).toEqual({});

    // The part that is actually new. Express already stripped the body on its
    // own freshness check, so the client always saw a 304 — but the image was
    // downloaded and buffered first, every time, and then discarded.
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect((fetchMock.mock.calls[0]![1] as RequestInit).headers).toMatchObject({
      'If-None-Match': ETAG,
    });
    expect(served.bytesServed).toBe(0);
  });

  it('serves the full image again when the validator no longer matches', async () => {
    const served = stubCms();

    const res = await request(app.getHttpServer())
      .get('/v1/media/uploads/foto_5a141d3978.png')
      .set('If-None-Match', 'W/"stale"')
      .expect(200);

    expect(Buffer.from(res.body as Buffer)).toEqual(PNG);
    expect(res.headers['etag']).toBe(ETAG);
    expect(served.bytesServed).toBe(PNG.byteLength);
  });

  it('still downloads when the CMS ignores the validator', async () => {
    // An upstream that answers 200 to a conditional request is answering a
    // question we did not have to ask twice — the client still gets a correct
    // image, and Express still decides the client-facing status.
    const served = stubCms(null);

    await request(app.getHttpServer())
      .get('/v1/media/uploads/foto_5a141d3978.png')
      .set('If-None-Match', ETAG)
      .expect(200);

    expect(served.bytesServed).toBe(PNG.byteLength);
  });

  it('behaves exactly as before for a client that sends no validator', async () => {
    stubCms();

    await request(app.getHttpServer()).get('/v1/media/uploads/foto_5a141d3978.png').expect(200);

    const init = fetchMock.mock.calls[0]![1] as RequestInit;
    expect(init.headers).not.toHaveProperty('If-None-Match');
  });

  it('still refuses a path outside the upload directory', async () => {
    fetchMock = jest.spyOn(globalThis, 'fetch');

    const res = await request(app.getHttpServer())
      .get('/v1/media/uploads/..%2F..%2Fetc%2Fpasswd')
      .expect(404);

    expect(fetchMock).not.toHaveBeenCalled();
    expect(res.headers['cache-control']).toBe('no-store');
  });

  /**
   * Only an image may be cached for a day.
   *
   * The day-long header used to be a handler decorator, which Nest applies
   * BEFORE the handler runs — so a 404 or a 503 left with it too, and the edge
   * cache prefers the upstream header over its own `proxy_cache_valid`. One
   * request during a CMS hiccup kept an image missing for 24 hours.
   */
  describe('error answers are never cacheable', () => {
    it('marks a missing image no-store', async () => {
      fetchMock = jest
        .spyOn(globalThis, 'fetch')
        .mockImplementation(async () => new Response('not found', { status: 404 }));

      const res = await request(app.getHttpServer())
        .get('/v1/media/uploads/foto_5a141d3978.png')
        .expect(404);

      expect(res.headers['cache-control']).toBe('no-store');
    });

    it('marks an unreachable CMS no-store', async () => {
      fetchMock = jest.spyOn(globalThis, 'fetch').mockImplementation(async () => {
        throw new TypeError('fetch failed');
      });

      const res = await request(app.getHttpServer())
        .get('/v1/media/uploads/foto_5a141d3978.png')
        .expect(503);

      expect(res.headers['cache-control']).toBe('no-store');
    });

    it('keeps the security headers on an error answer', async () => {
      fetchMock = jest
        .spyOn(globalThis, 'fetch')
        .mockImplementation(async () => new Response('not found', { status: 404 }));

      const res = await request(app.getHttpServer())
        .get('/v1/media/uploads/foto_5a141d3978.png')
        .expect(404);

      expect(res.headers['x-content-type-options']).toBe('nosniff');
    });
  });
});
