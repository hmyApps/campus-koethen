import { Logger } from '@nestjs/common';
import { createServer, Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { Env } from '../../config/env.schema';
import { StrapiClient, StrapiRequestError } from './strapi.client';

/**
 * What this client will BUFFER from the CMS.
 *
 * The query encoding and the retry policy are exercised through the modules
 * that use them; what is settled here is the one thing that has no upper bound
 * anywhere else — how many bytes of an upstream answer may reach the heap.
 */
const env = {
  STRAPI_BASE_URL: 'http://cms.internal:1337',
  STRAPI_API_TOKEN: 'test-token',
  STRAPI_TIMEOUT_MS: 1_000,
  STRAPI_RETRY_ATTEMPTS: 0,
} as unknown as Env;

describe('StrapiClient', () => {
  let fetchMock: jest.SpyInstance;

  afterEach(() => {
    fetchMock?.mockRestore();
  });

  it('parses a JSON answer', async () => {
    fetchMock = jest.spyOn(globalThis, 'fetch').mockImplementation(
      async () =>
        new Response(JSON.stringify({ data: [{ slug: 'x' }] }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
    );

    await expect(new StrapiClient(env).get('/api/posts')).resolves.toEqual({
      data: [{ slug: 'x' }],
    });
  });

  it('refuses to follow a redirect instead of letting the CMS pick the host', async () => {
    let seen: RequestInit = {};
    fetchMock = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation(async (_input: string | URL | Request, init?: RequestInit) => {
        seen = init ?? {};
        return new Response(JSON.stringify({ data: [] }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      });

    await new StrapiClient(env).get('/api/posts');

    // The bearer token is configuration-scoped: STRAPI_BASE_URL decides which
    // host sees it, not a 302 from the answer.
    expect(seen.redirect).toBe('error');
  });

  it('reports a non-JSON body as malformed rather than throwing a parse error', async () => {
    fetchMock = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation(async () => new Response('<html>nope</html>', { status: 200 }));

    await expect(new StrapiClient(env).get('/api/posts')).rejects.toMatchObject({
      kind: 'malformed',
    });
  });

  it('stops reading instead of buffering an unbounded body', async () => {
    // No content-length, and the stream never ends — exactly the shape a limit
    // checked after `response.json()` cannot defend against.
    let pulled = 0;
    const chunk = new Uint8Array(256 * 1024);
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        pulled += 1;
        controller.enqueue(chunk);
      },
    });
    fetchMock = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation(async () => new Response(stream, { status: 200 }));

    await expect(new StrapiClient(env).get('/api/posts')).rejects.toBeInstanceOf(
      StrapiRequestError,
    );

    // 16 MiB is 64 chunks; the stream queues a few more before the cancel is
    // observed. Finishing at all — against a source that never ends — is what
    // proves the read was cut short rather than drained.
    expect(pulled).toBeLessThan(100);
    expect(pulled * chunk.byteLength).toBeLessThan(StrapiClient.maxResponseBytes * 2);
  });

  it('does not retry an oversized body', async () => {
    const chunk = new Uint8Array(256 * 1024);
    let calls = 0;
    fetchMock = jest.spyOn(globalThis, 'fetch').mockImplementation(async () => {
      calls += 1;
      return new Response(
        new ReadableStream<Uint8Array>({
          pull(controller) {
            controller.enqueue(chunk);
          },
        }),
        { status: 200 },
      );
    });

    const retrying: Env = { ...env, STRAPI_RETRY_ATTEMPTS: 2 };
    await expect(new StrapiClient(retrying).get('/api/posts')).rejects.toMatchObject({
      kind: 'malformed',
    });
    // A body that is too large is a deterministic answer; asking again would
    // only pull the same flood a second and third time.
    expect(calls).toBe(1);
  });

  /**
   * Which failures are worth asking again.
   *
   * Only the upstream saying "not now" — a timeout, a broken connection, a 5xx
   * or a 429 — is transient. A 4xx or a redirect is the same answer on every
   * attempt; retrying it only added ~600 ms of backoff in front of a 503 and
   * reported a client-side rejection as an outage.
   */
  describe('retry policy', () => {
    const retrying: Env = { ...env, STRAPI_RETRY_ATTEMPTS: 2 };
    let warn: jest.SpyInstance;

    beforeEach(() => {
      warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    });

    afterEach(() => {
      warn.mockRestore();
    });

    function answerEveryAttemptWith(status: number): () => number {
      let calls = 0;
      fetchMock = jest.spyOn(globalThis, 'fetch').mockImplementation(async () => {
        calls += 1;
        return new Response(JSON.stringify({ error: { status } }), { status });
      });
      return () => calls;
    }

    it.each([400, 404])('reports a %i as rejected and does not ask again', async (status) => {
      const calls = answerEveryAttemptWith(status);

      await expect(new StrapiClient(retrying).get('/api/posts')).rejects.toMatchObject({
        kind: 'rejected',
        status,
      });
      expect(calls()).toBe(1);
    });

    it.each([500, 503, 429])('retries a transient %i', async (status) => {
      const calls = answerEveryAttemptWith(status);
      const once: Env = { ...env, STRAPI_RETRY_ATTEMPTS: 1 };

      await expect(new StrapiClient(once).get('/api/posts')).rejects.toMatchObject({
        kind: 'unavailable',
        status,
      });
      expect(calls()).toBe(2);
    });

    it('retries a broken connection', async () => {
      let calls = 0;
      fetchMock = jest.spyOn(globalThis, 'fetch').mockImplementation(async () => {
        calls += 1;
        throw new TypeError('fetch failed', {
          cause: Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' }),
        });
      });
      const once: Env = { ...env, STRAPI_RETRY_ATTEMPTS: 1 };

      await expect(new StrapiClient(once).get('/api/posts')).rejects.toMatchObject({
        kind: 'unavailable',
      });
      expect(calls).toBe(2);
    });

    describe('against a real HTTP server', () => {
      // No fetch mock here on purpose: how a refused redirect surfaces is
      // decided by the runtime's fetch implementation, and a stub would only
      // assert what the test author believed it to be.
      let server: Server;
      let hits = 0;

      beforeAll(async () => {
        server = createServer((_request, response) => {
          hits += 1;
          response.writeHead(302, { Location: 'http://elsewhere.invalid/api/posts' });
          response.end();
        });
        await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
      });

      afterAll(async () => {
        await new Promise<void>((resolve) => server.close(() => resolve()));
      });

      it('reports a refused redirect as rejected and does not ask again', async () => {
        hits = 0;
        const { port } = server.address() as AddressInfo;
        const client = new StrapiClient({
          ...retrying,
          STRAPI_BASE_URL: `http://127.0.0.1:${port}`,
        });

        await expect(client.get('/api/posts')).rejects.toMatchObject({ kind: 'rejected' });
        expect(hits).toBe(1);
      });
    });

    it('logs the number of attempts actually made, not the configured maximum', async () => {
      answerEveryAttemptWith(404);

      await expect(new StrapiClient(retrying).get('/api/posts')).rejects.toBeInstanceOf(
        StrapiRequestError,
      );

      const messages = warn.mock.calls.map((call: unknown[]) => String(call[0]));
      expect(messages.some((message) => message.includes('after 1 attempt(s)'))).toBe(true);
      expect(messages.some((message) => message.includes('after 3 attempt(s)'))).toBe(false);
    });
  });
  /**
   * The readiness probe reaches the same upstream and was missed when the read
   * path stopped following redirects.
   *
   * It sends no token, so nothing leaks — but `/health/ready` reports on
   * whatever answers, and with `follow` a 302 from the CMS decides which host
   * that is. "Strapi is ready" would then rest on a 200 from somewhere else.
   */
  describe('probe', () => {
    it('refuses to follow a redirect, like the read path', async () => {
      let seen: RequestInit = {};
      fetchMock = jest
        .spyOn(globalThis, 'fetch')
        .mockImplementation(async (_input: string | URL | Request, init?: RequestInit) => {
          seen = init ?? {};
          return new Response(null, { status: 204 });
        });

      await new StrapiClient(env).probe(1_000);

      expect(seen.redirect).toBe('error');
    });

    it('reports a redirected health endpoint as unavailable rather than ready', async () => {
      // `redirect: 'error'` makes undici reject; the client must classify that
      // instead of letting it escape as an opaque TypeError.
      fetchMock = jest.spyOn(globalThis, 'fetch').mockImplementation(async () => {
        throw new TypeError('unexpected redirect');
      });

      await expect(new StrapiClient(env).probe(1_000)).rejects.toBeInstanceOf(StrapiRequestError);
    });

    it('treats a non-ok status as unavailable', async () => {
      fetchMock = jest
        .spyOn(globalThis, 'fetch')
        .mockImplementation(async () => new Response(null, { status: 503 }));

      await expect(new StrapiClient(env).probe(1_000)).rejects.toMatchObject({
        kind: 'unavailable',
      });
    });
  });
});
