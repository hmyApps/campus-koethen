import {
  FetchLike,
  GooglePublicIcsClient,
  IcsClientConfig,
  IcsClientError,
} from './google-public-ics.client';

const SYNTHETIC_ID = 'beispielkalender-a@group.calendar.google.com';

function firstCall<T>(items: T[]): T {
  const x = items[0];
  if (!x) throw new Error('expected at least one call');
  return x;
}

const CONFIG: IcsClientConfig = {
  timeoutMs: 1000,
  retryAttempts: 2,
  requestSpacingMs: 0,
  maxBytes: 1024,
  userAgent: 'CampusKoethen/test',
};

const VALID_ICS = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n';

function calendarResponse(
  body: string,
  headers: Record<string, string> = {},
  status = 200,
): Response {
  return new Response(body, {
    status,
    headers: { 'content-type': 'text/calendar; charset=utf-8', ...headers },
  });
}

function recordingFetch(handler: (url: string, init: RequestInit) => Response): {
  fetch: FetchLike;
  calls: Array<{ url: string; init: RequestInit }>;
} {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const fetchImpl: FetchLike = (url, init) => {
    calls.push({ url, init });
    return Promise.resolve(handler(url, init));
  };
  return { fetch: fetchImpl, calls };
}

describe('GooglePublicIcsClient', () => {
  it('downloads the FIXED public feed URL and returns the body + validators', async () => {
    const { fetch, calls } = recordingFetch(() =>
      calendarResponse(VALID_ICS, {
        etag: '"abc"',
        'last-modified': 'Wed, 10 Jun 2026 00:00:00 GMT',
      }),
    );
    const client = new GooglePublicIcsClient(CONFIG, fetch);
    const result = await client.fetchCalendar(SYNTHETIC_ID);

    expect(result.kind).toBe('ok');
    if (result.kind === 'ok') {
      expect(result.body).toContain('BEGIN:VCALENDAR');
      expect(result.etag).toBe('"abc"');
      expect(result.lastModified).toBe('Wed, 10 Jun 2026 00:00:00 GMT');
    }
    expect(firstCall(calls).url).toBe(
      'https://calendar.google.com/calendar/ical/' +
        encodeURIComponent(SYNTHETIC_ID) +
        '/public/basic.ics',
    );
    expect(firstCall(calls).init.redirect).toBe('manual');
  });

  it('sends If-None-Match / If-Modified-Since and handles 304', async () => {
    const { fetch, calls } = recordingFetch(() => new Response(null, { status: 304 }));
    const client = new GooglePublicIcsClient(CONFIG, fetch);
    const result = await client.fetchCalendar(SYNTHETIC_ID, {
      etag: '"abc"',
      lastModified: 'Wed, 10 Jun 2026 00:00:00 GMT',
    });
    expect(result.kind).toBe('notModified');
    const headers = firstCall(calls).init.headers as Record<string, string>;
    expect(headers['If-None-Match']).toBe('"abc"');
    expect(headers['If-Modified-Since']).toBe('Wed, 10 Jun 2026 00:00:00 GMT');
  });

  it('maps 404 to feedNotFound without retrying', async () => {
    const { fetch, calls } = recordingFetch(() => new Response('nope', { status: 404 }));
    const client = new GooglePublicIcsClient(CONFIG, fetch);
    await expect(client.fetchCalendar(SYNTHETIC_ID)).rejects.toMatchObject({
      kind: 'feedNotFound',
    });
    expect(calls).toHaveLength(1); // 4xx is not retried
  });

  it('maps 410 to permissionRevoked', async () => {
    const { fetch } = recordingFetch(() => new Response('gone', { status: 410 }));
    const client = new GooglePublicIcsClient(CONFIG, fetch);
    await expect(client.fetchCalendar(SYNTHETIC_ID)).rejects.toMatchObject({
      kind: 'permissionRevoked',
    });
  });

  it('retries a 5xx then succeeds', async () => {
    let n = 0;
    const { fetch, calls } = recordingFetch(() => {
      n += 1;
      return n === 1 ? new Response('err', { status: 503 }) : calendarResponse(VALID_ICS);
    });
    const client = new GooglePublicIcsClient(CONFIG, fetch);
    const result = await client.fetchCalendar(SYNTHETIC_ID);
    expect(result.kind).toBe('ok');
    expect(calls.length).toBe(2);
  });

  it('maps 429 to rateLimited', async () => {
    const { fetch } = recordingFetch(() => new Response('slow down', { status: 429 }));
    const client = new GooglePublicIcsClient({ ...CONFIG, retryAttempts: 0 }, fetch);
    await expect(client.fetchCalendar(SYNTHETIC_ID)).rejects.toMatchObject({ kind: 'rateLimited' });
  });

  it('refuses a redirect (never followed)', async () => {
    const { fetch } = recordingFetch(
      () =>
        new Response(null, { status: 302, headers: { location: 'https://evil.example.com/x' } }),
    );
    const client = new GooglePublicIcsClient({ ...CONFIG, retryAttempts: 0 }, fetch);
    await expect(client.fetchCalendar(SYNTHETIC_ID)).rejects.toMatchObject({ kind: 'redirected' });
  });

  it('rejects a non-calendar content type with a non-calendar body', async () => {
    const { fetch } = recordingFetch(
      () =>
        new Response('<html>login</html>', {
          status: 200,
          headers: { 'content-type': 'text/html' },
        }),
    );
    const client = new GooglePublicIcsClient({ ...CONFIG, retryAttempts: 0 }, fetch);
    await expect(client.fetchCalendar(SYNTHETIC_ID)).rejects.toMatchObject({
      kind: 'invalidContentType',
    });
  });

  it('tolerates an odd content type when the body IS a VCALENDAR', async () => {
    const { fetch } = recordingFetch(
      () =>
        new Response(VALID_ICS, {
          status: 200,
          headers: { 'content-type': 'application/octet-stream' },
        }),
    );
    const client = new GooglePublicIcsClient({ ...CONFIG, retryAttempts: 0 }, fetch);
    const result = await client.fetchCalendar(SYNTHETIC_ID);
    expect(result.kind).toBe('ok');
  });

  it('rejects a body over the size cap (declared content-length)', async () => {
    const { fetch } = recordingFetch(() =>
      calendarResponse(VALID_ICS, { 'content-length': '999999' }),
    );
    const client = new GooglePublicIcsClient({ ...CONFIG, retryAttempts: 0 }, fetch);
    await expect(client.fetchCalendar(SYNTHETIC_ID)).rejects.toMatchObject({
      kind: 'feedTooLarge',
    });
  });

  it('rejects a body over the size cap (streamed, no content-length)', async () => {
    const big = 'BEGIN:VCALENDAR\r\n' + 'X'.repeat(5000) + '\r\nEND:VCALENDAR';
    const { fetch } = recordingFetch(
      () => new Response(big, { status: 200, headers: { 'content-type': 'text/calendar' } }),
    );
    const client = new GooglePublicIcsClient(
      { ...CONFIG, retryAttempts: 0, maxBytes: 1024 },
      fetch,
    );
    await expect(client.fetchCalendar(SYNTHETIC_ID)).rejects.toMatchObject({
      kind: 'feedTooLarge',
    });
  });

  it('stops the download instead of buffering an oversized feed first', async () => {
    // Chunked, no content-length — which is how Google actually serves ICS.
    // The old cap was checked after `response.text()`, so a feed that omits or
    // lies about its length was fully in memory before anything refused it.
    let pulled = 0;
    const chunk = new TextEncoder().encode('X'.repeat(1024));
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        pulled += 1;
        controller.enqueue(chunk);
      },
    });
    const { fetch } = recordingFetch(
      () => new Response(stream, { status: 200, headers: { 'content-type': 'text/calendar' } }),
    );
    const client = new GooglePublicIcsClient(
      { ...CONFIG, retryAttempts: 0, maxBytes: 4096 },
      fetch,
    );

    await expect(client.fetchCalendar(SYNTHETIC_ID)).rejects.toMatchObject({
      kind: 'feedTooLarge',
    });
    // 4096 bytes = 4 chunks; the stream would otherwise never end at all.
    expect(pulled).toBeLessThan(10);
  });

  it('spaces concurrent requests apart instead of releasing them together', async () => {
    // The event job runs four feeds at once through ONE client. Each caller
    // used to measure its wait from the same `lastRequestAt` and only stamp it
    // after sleeping, so every waiting caller woke up — and hit Google — at the
    // same instant. The slot has to be reserved before the wait.
    const spacing = 60;
    const sentAt: number[] = [];
    const { fetch } = recordingFetch(() => {
      sentAt.push(Date.now());
      return calendarResponse(VALID_ICS);
    });
    const client = new GooglePublicIcsClient(
      { ...CONFIG, retryAttempts: 0, requestSpacingMs: spacing },
      fetch,
    );

    await Promise.all(Array.from({ length: 4 }, () => client.fetchCalendar(SYNTHETIC_ID)));

    expect(sentAt).toHaveLength(4);
    const ordered = [...sentAt].sort((a, b) => a - b);
    for (let index = 1; index < ordered.length; index += 1) {
      // A little timer slack, but nowhere near "simultaneous".
      expect(ordered[index]! - ordered[index - 1]!).toBeGreaterThanOrEqual(spacing - 15);
    }
  });

  it('never leaks the feed URL or calendar id in a thrown error', async () => {
    const { fetch } = recordingFetch(() => new Response('nope', { status: 404 }));
    const client = new GooglePublicIcsClient({ ...CONFIG, retryAttempts: 0 }, fetch);
    try {
      await client.fetchCalendar(SYNTHETIC_ID);
      throw new Error('should have thrown');
    } catch (error) {
      expect(error).toBeInstanceOf(IcsClientError);
      const message = (error as IcsClientError).message;
      expect(message).not.toContain(SYNTHETIC_ID);
      expect(message).not.toContain('basic.ics');
    }
  });
});
