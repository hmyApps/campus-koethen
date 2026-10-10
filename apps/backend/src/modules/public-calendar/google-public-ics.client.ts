import { BodyTooLargeError, readBoundedText } from '../../common/http/bounded-body';
import { buildIcsFeedUrl } from './google-calendar-url';

/**
 * The ONLY component that downloads a Google ICS feed.
 *
 * Given an ALREADY-VALIDATED calendar id, it constructs the fixed public feed
 * URL itself (`buildIcsFeedUrl`) and downloads it under a strict policy:
 *  - HTTPS + host `calendar.google.com` only (guaranteed by the URL builder),
 *  - no API key, no OAuth, no cookies, no user account,
 *  - redirects are NOT followed (a 3xx is refused so the request can never be
 *    bounced to another host),
 *  - a hard timeout, bounded retries (5xx / 429 / transport only) and a polite
 *    request spacing,
 *  - `Content-Length` pre-check AND a streamed byte cap that aborts mid-download,
 *  - `Content-Type` is expected to be `text/calendar`; a tolerated mismatch is
 *    only accepted when the body still begins a VCALENDAR (validated in full by
 *    the parser),
 *  - conditional requests via ETag / Last-Modified with HTTP 304 support,
 *  - the full feed URL and the raw calendar id never appear in a thrown error.
 */

export type IcsClientErrorKind =
  | 'timeout'
  | 'network'
  | 'rateLimited'
  | 'upstreamUnavailable'
  | 'feedNotFound'
  | 'permissionRevoked'
  | 'invalidContentType'
  | 'feedTooLarge'
  | 'redirected'
  | 'invalidResponse';

export class IcsClientError extends Error {
  retryAfterMs?: number;
  constructor(
    public readonly kind: IcsClientErrorKind,
    message: string,
    public readonly status?: number,
  ) {
    super(message);
    this.name = 'IcsClientError';
  }
}

export interface IcsClientConfig {
  timeoutMs: number;
  retryAttempts: number;
  requestSpacingMs: number;
  maxBytes: number;
  userAgent: string;
}

export interface ConditionalHeaders {
  etag?: string | null;
  lastModified?: string | null;
}

export type IcsFetchResult =
  | { kind: 'ok'; body: string; etag: string | null; lastModified: string | null }
  | { kind: 'notModified' };

export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

export class GooglePublicIcsClient {
  /** Earliest instant (epoch ms) the next request may be sent. */
  private nextRequestAt = 0;

  constructor(
    private readonly config: IcsClientConfig,
    private readonly fetchImpl: FetchLike = (url, init) => fetch(url, init),
  ) {}

  async fetchCalendar(
    calendarId: string,
    conditional: ConditionalHeaders = {},
  ): Promise<IcsFetchResult> {
    const url = buildIcsFeedUrl(calendarId);
    const attempts = this.config.retryAttempts + 1;
    let lastError = new IcsClientError('network', 'The calendar feed was never contacted.');

    for (let attempt = 1; attempt <= attempts; attempt += 1) {
      await this.throttle();
      try {
        return await this.attempt(url, conditional);
      } catch (error) {
        lastError =
          error instanceof IcsClientError
            ? error
            : new IcsClientError('network', 'transport failure');
        const retryable =
          lastError.kind === 'timeout' ||
          lastError.kind === 'network' ||
          lastError.kind === 'rateLimited' ||
          lastError.kind === 'upstreamUnavailable';
        if (!retryable || attempt === attempts) break;
        const backoff = 500 * 2 ** (attempt - 1) + Math.floor(Math.random() * 250);
        await this.sleep(lastError.retryAfterMs ?? backoff);
      }
    }
    throw lastError;
  }

  /**
   * Reserves this request's send slot BEFORE waiting for it.
   *
   * The event job drives several feeds through one client at once. Stamping
   * the slot only after the sleep let every concurrent caller compute its wait
   * from the same previous request and wake up together, which defeats the
   * spacing exactly when it matters.
   */
  private async throttle(): Promise<void> {
    const spacing = this.config.requestSpacingMs;
    if (spacing <= 0) return;
    const now = Date.now();
    const slot = Math.max(now, this.nextRequestAt);
    this.nextRequestAt = slot + spacing;
    const wait = slot - now;
    if (wait > 0) await this.sleep(wait);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  private async attempt(url: string, conditional: ConditionalHeaders): Promise<IcsFetchResult> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);
    try {
      const headers: Record<string, string> = {
        Accept: 'text/calendar',
        'User-Agent': this.config.userAgent,
        'Accept-Encoding': 'gzip, deflate',
      };
      if (conditional.etag) headers['If-None-Match'] = conditional.etag;
      if (conditional.lastModified) headers['If-Modified-Since'] = conditional.lastModified;

      const response = await this.fetchImpl(url, {
        method: 'GET',
        signal: controller.signal,
        redirect: 'manual', // never follow a redirect with our request
        headers,
      });

      const status = response.status;
      if (status === 304) return { kind: 'notModified' };
      // `redirect: 'manual'` surfaces 3xx as an opaque-redirect (status 0) or a
      // 3xx status; either way we refuse it.
      if (status === 0 || (status >= 300 && status < 400)) {
        throw new IcsClientError(
          'redirected',
          'The feed responded with a redirect, which is not followed.',
        );
      }
      if (status === 404)
        throw new IcsClientError('feedNotFound', 'The calendar feed does not exist.', 404);
      if (status === 403 || status === 410) {
        throw new IcsClientError('permissionRevoked', 'The calendar is no longer public.', status);
      }
      if (status === 429) {
        const retryAfter = Number(response.headers.get('retry-after'));
        const err = new IcsClientError('rateLimited', 'The feed is rate limiting requests.', 429);
        if (Number.isFinite(retryAfter) && retryAfter > 0)
          err.retryAfterMs = Math.min(retryAfter * 1000, 60_000);
        throw err;
      }
      if (status >= 500)
        throw new IcsClientError(
          'upstreamUnavailable',
          'The feed is temporarily unavailable.',
          status,
        );
      if (status < 200 || status >= 300) {
        throw new IcsClientError('upstreamUnavailable', `Unexpected status ${status}.`, status);
      }

      const declared = Number(response.headers.get('content-length'));
      if (Number.isFinite(declared) && declared > this.config.maxBytes) {
        throw new IcsClientError('feedTooLarge', 'The feed exceeds the size limit.');
      }

      const body = await this.readBounded(response);

      const contentType = (response.headers.get('content-type') ?? '').toLowerCase();
      const looksLikeCalendar = body.trimStart().startsWith('BEGIN:VCALENDAR');
      if (!contentType.includes('text/calendar') && !looksLikeCalendar) {
        throw new IcsClientError('invalidContentType', 'The feed did not return calendar data.');
      }
      if (!looksLikeCalendar) {
        throw new IcsClientError('invalidResponse', 'The feed body is not a VCALENDAR.');
      }

      return {
        kind: 'ok',
        body,
        etag: response.headers.get('etag'),
        lastModified: response.headers.get('last-modified'),
      };
    } catch (error) {
      if (error instanceof IcsClientError) throw error;
      if (error instanceof Error && error.name === 'AbortError') {
        throw new IcsClientError('timeout', 'The calendar feed request timed out.');
      }
      throw new IcsClientError('network', 'The calendar feed is unreachable.');
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * Reads the body with a hard byte cap, enforced WHILE reading.
   *
   * The `Content-Length` pre-check in [attempt] rejects a declared-oversize
   * feed before this runs, but that header is a claim and Google serves ICS
   * chunked, so it is usually absent. The transfer is therefore cancelled the
   * moment the limit is passed — a server that lies about (or omits) the length
   * cannot make this process buffer more than the limit.
   */
  private async readBounded(response: Response): Promise<string> {
    try {
      return await readBoundedText(response, this.config.maxBytes);
    } catch (error) {
      if (error instanceof BodyTooLargeError) {
        throw new IcsClientError('feedTooLarge', 'The feed exceeds the size limit.');
      }
      throw error;
    }
  }
}
