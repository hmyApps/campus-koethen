import { z } from 'zod';

/**
 * Single source of truth for every environment variable the backend reads.
 *
 * Environment is the ONLY thing that differs between DEV and PROD — there is no
 * environment-specific source code and no hardcoded host anywhere. Validation
 * happens once at boot so a misconfigured deployment fails immediately and
 * loudly instead of erroring on the first request.
 */

const booleanFromEnv = z
  .enum(['true', 'false', '1', '0'])
  .transform((value) => value === 'true' || value === '1');

const csv = z.string().transform((value) =>
  value
    .split(',')
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0),
);

const ianaTimeZone = z
  .string()
  .min(1)
  .refine(
    (value) => {
      try {
        new Intl.DateTimeFormat('en-US', { timeZone: value }).format();
        return true;
      } catch {
        return false;
      }
    },
    { message: 'must be a valid IANA time zone' },
  );

export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),

  // --- HTTP server ---------------------------------------------------------
  HOST: z.string().min(1).default('0.0.0.0'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),

  /**
   * Comma-separated allowlist. A wildcard is rejected in production so a
   * permissive local default can never be promoted to a live deployment.
   */
  // Zod 4: `.default()` takes the OUTPUT type, i.e. the already-split array.
  CORS_ALLOWED_ORIGINS: csv.default(['http://localhost:3000']),

  // --- Database ------------------------------------------------------------
  DATABASE_URL: z
    .string()
    .min(1)
    .refine(
      (value) => value.startsWith('postgresql://') || value.startsWith('postgres://'),
      'DATABASE_URL must be a PostgreSQL connection string',
    ),

  // --- Strapi --------------------------------------------------------------
  /** Never a source constant — the CMS address is configuration, always. */
  STRAPI_BASE_URL: z.url({ protocol: /^https?$/ }).default('http://127.0.0.1:1337'),
  /**
   * Server-side READ-ONLY token. Optional so the stack can boot before the
   * token exists; /health/ready then reports strapi as degraded, which is the
   * honest signal rather than a hidden failure.
   */
  STRAPI_API_TOKEN: z.string().default(''),
  STRAPI_TIMEOUT_MS: z.coerce.number().int().min(500).max(60_000).default(10_000),
  STRAPI_RETRY_ATTEMPTS: z.coerce.number().int().min(0).max(5).default(2),

  // --- Canteen source ------------------------------------------------------
  CANTEEN_SOURCE_URL: z
    .url({ protocol: /^https$/ })
    .default('https://meine-mensa.de/api/food_plans'),
  CANTEEN_HTTP_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120_000).default(15_000),
  CANTEEN_RETRY_ATTEMPTS: z.coerce.number().int().min(0).max(5).default(3),
  /**
   * Largest response we are willing to buffer, as a crude runaway guard.
   *
   * One sync fetches at most two weeks for a single location, which is a few
   * hundred kilobytes; 8 MB leaves generous headroom while still keeping a
   * misbehaving or hostile source from deciding how much memory this process
   * spends.
   */
  CANTEEN_MAX_RESPONSE_BYTES: z.coerce
    .number()
    .int()
    .min(64_000)
    .max(64_000_000)
    .default(8_000_000),
  /** Politeness delay between per-canteen requests, in milliseconds. */
  CANTEEN_REQUEST_SPACING_MS: z.coerce.number().int().min(0).max(60_000).default(1_000),
  /** Every two hours. Deliberately not aggressive. */
  CANTEEN_SYNC_CRON: z.string().min(1).default('0 */2 * * *'),
  CANTEEN_SYNC_ON_BOOT: booleanFromEnv.default(true),
  /** Data older than this is reported to the client as `dataStale`. */
  CANTEEN_STALE_AFTER_MINUTES: z.coerce.number().int().min(5).max(10_080).default(240),
  /** How far ahead a sync fetches: current + next week. */
  CANTEEN_SYNC_DAYS_AHEAD: z.coerce.number().int().min(1).max(60).default(14),

  // --- WebUntis timetable --------------------------------------------------
  /**
   * OFF by default, on purpose. The source is an internal interface of a
   * third party's public web UI, and automated use is not cleared yet. The
   * feature ships complete but dormant until that is a deliberate decision.
   */
  WEBUNTIS_ENABLED: booleanFromEnv.default(false),
  WEBUNTIS_BASE_URL: z
    .url({ protocol: /^https$/ })
    .default('https://hsa.webuntis.com/WebUntis/api/rest/view/v1'),
  /**
   * Identifies the tenant for the anonymous public view. Not a credential, but
   * still server-side configuration: it must never reach the app.
   */
  WEBUNTIS_ANONYMOUS_SCHOOL: z.string().min(1).default('hsa'),
  WEBUNTIS_HTTP_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120_000).default(20_000),
  WEBUNTIS_RETRY_ATTEMPTS: z.coerce.number().int().min(0).max(5).default(3),
  /** Politeness delay between consecutive upstream requests. */
  WEBUNTIS_REQUEST_SPACING_MS: z.coerce.number().int().min(0).max(60_000).default(1_500),
  /** Largest response we are willing to buffer, as a crude runaway guard. */
  WEBUNTIS_MAX_RESPONSE_BYTES: z.coerce
    .number()
    .int()
    .min(64_000)
    .max(64_000_000)
    .default(16_000_000),
  /** Daily catalogue refresh, before the per-class entry requests. */
  WEBUNTIS_GROUP_SYNC_CRON: z.string().min(1).default('0 2 * * *'),
  /** The public view requires one request per class; avoid an hourly full scan. */
  WEBUNTIS_ENTRY_SYNC_CRON: z.string().min(1).default('15 2 * * *'),
  WEBUNTIS_SYNC_ON_BOOT: booleanFromEnv.default(true),
  WEBUNTIS_LOOKBACK_DAYS: z.coerce.number().int().min(0).max(90).default(7),
  WEBUNTIS_LOOKAHEAD_DAYS: z.coerce.number().int().min(1).max(210).default(28),
  WEBUNTIS_STALE_AFTER_MINUTES: z.coerce.number().int().min(5).max(10_080).default(1800),

  // --- Public Google calendars (public ICS feed) ---------------------------
  /**
   * OFF by default. The feature ships complete but dormant until public
   * calendars are actually configured in Strapi. NO Google API key exists —
   * the worker downloads the public ICS feed directly, so there is deliberately
   * no GOOGLE_API_KEY / OAuth / service-account configuration anywhere.
   */
  PUBLIC_CALENDAR_ENABLED: booleanFromEnv.default(false),
  PUBLIC_CALENDAR_HTTP_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120_000).default(20_000),
  PUBLIC_CALENDAR_RETRY_ATTEMPTS: z.coerce.number().int().min(0).max(5).default(2),
  /** Politeness delay between consecutive feed downloads. */
  PUBLIC_CALENDAR_REQUEST_SPACING_MS: z.coerce.number().int().min(0).max(60_000).default(1_000),
  /**
   * Catalogue (Strapi → read-model): every 10 minutes, so a newly published
   * calendar appears quickly. The reconcile is cheap (a bounded Strapi read).
   */
  PUBLIC_CALENDAR_CATALOG_SYNC_CRON: z.string().min(1).default('*/10 * * * *'),
  /**
   * Events: every 10 minutes. Kept polite by conditional requests
   * (If-None-Match / If-Modified-Since → 304) and a content-hash short-circuit,
   * so unchanged feeds skip parsing/persistence; the overlap guard prevents
   * runs from piling up.
   */
  PUBLIC_CALENDAR_EVENT_SYNC_CRON: z.string().min(1).default('*/10 * * * *'),
  PUBLIC_CALENDAR_SYNC_ON_BOOT: booleanFromEnv.default(true),
  /** Largest feed we will buffer, as a runaway guard. */
  PUBLIC_CALENDAR_MAX_FEED_BYTES: z.coerce
    .number()
    .int()
    .min(64_000)
    .max(64_000_000)
    .default(8_000_000),
  PUBLIC_CALENDAR_MAX_EVENTS: z.coerce.number().int().min(10).max(50_000).default(5_000),
  PUBLIC_CALENDAR_MAX_OCCURRENCES: z.coerce.number().int().min(10).max(200_000).default(25_000),
  /** Counts only the occurrences of one event that REACH the window. */
  PUBLIC_CALENDAR_MAX_OCCURRENCES_PER_EVENT: z.coerce
    .number()
    .int()
    .min(10)
    .max(20_000)
    .default(2_000),
  /**
   * Total iterator steps a feed may cost, occurrences before the window
   * included. A recurrence is anchored at DTSTART and cannot be seeked, so a
   * series that started years ago has to be walked up to the window; this is
   * the bound on that walk, and the guard against a high-frequency rule that
   * begins long before the window and would otherwise never terminate.
   */
  PUBLIC_CALENDAR_MAX_SCANNED_OCCURRENCES: z.coerce
    .number()
    .int()
    .min(1_000)
    .max(5_000_000)
    .default(250_000),
  PUBLIC_CALENDAR_MAX_TEXT_LENGTH: z.coerce.number().int().min(100).max(10_000).default(2_000),
  PUBLIC_CALENDAR_LOOKBACK_DAYS: z.coerce.number().int().min(0).max(365).default(30),
  PUBLIC_CALENDAR_LOOKAHEAD_DAYS: z.coerce.number().int().min(1).max(730).default(400),
  PUBLIC_CALENDAR_STALE_AFTER_MINUTES: z.coerce.number().int().min(5).max(43_200).default(720),
  /** Fallback zone for floating (zone-less) event times only. */
  PUBLIC_CALENDAR_FALLBACK_TIME_ZONE: ianaTimeZone.default('Europe/Berlin'),
  PUBLIC_CALENDAR_USER_AGENT: z
    .string()
    .min(1)
    .default('CampusKoethen/1.2.4 (+https://dev.erikengler.campuskoethen)'),
  /** API bounds: max calendars per aggregated/combined request, max date range. */
  PUBLIC_CALENDAR_API_MAX_CALENDARS: z.coerce.number().int().min(1).max(100).default(50),
  PUBLIC_CALENDAR_API_MAX_RANGE_DAYS: z.coerce.number().int().min(1).max(400).default(400),
  /**
   * Hard ceiling on how many events one event response may carry. Calendars and
   * the date range are already bounded, but the RESULT was not: 50 calendars
   * over 400 days is an unbounded row count. Hitting the ceiling is reported as
   * `meta.truncated`, never silently cut.
   */
  PUBLIC_CALENDAR_API_MAX_EVENTS: z.coerce.number().int().min(1).max(20000).default(2000),

  // --- Worker scheduling --------------------------------------------------
  /** Explicit wall-clock zone for every cron expression. */
  WORKER_TIME_ZONE: ianaTimeZone.default('UTC'),

  // --- Controlled user-test data ------------------------------------------
  /**
   * Explicit safety switch for the local, synthetic user-test seed. The same
   * flag also makes the API advertise the environment to the mobile client.
   * It is OFF everywhere unless a deployment deliberately opts in.
   */
  USER_TEST_DATA_ENABLED: booleanFromEnv.default(false),

  /**
   * Serves the rendered Swagger UI at `/docs` and the document at `/docs-json`.
   *
   * Unset means "on outside production, off in production" — resolved in
   * {@link validateEnv} because the default depends on NODE_ENV. Rationale:
   * `/docs` is a real HTML page on the same origin the media endpoint serves
   * bytes from, and it deliberately runs under a LOOSER CSP than the API
   * (DOCS_CONTENT_SECURITY_POLICY). None of that is worth carrying live for a
   * contract that is already published, versioned, in
   * `packages/openapi/openapi.json`.
   *
   * Setting it to `true` in production is a deliberate, single-variable
   * decision — the point is that it is made, not that it is made one way.
   */
  DOCS_ENABLED: booleanFromEnv.optional(),

  // --- Observability -------------------------------------------------------
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  /** Pretty console output for humans; JSON is the default and the server format. */
  LOG_PRETTY: booleanFromEnv.default(false),
});

export type Env = Omit<z.infer<typeof envSchema>, 'DOCS_ENABLED'> & { DOCS_ENABLED: boolean };

export class EnvValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EnvValidationError';
  }
}

export function validateEnv(raw: NodeJS.ProcessEnv): Env {
  // Empty strings are treated as "unset" so an empty compose variable falls
  // through to the documented default instead of failing validation.
  const cleaned: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (value !== undefined && value !== '') {
      cleaned[key] = value;
    }
  }
  // STRAPI_API_TOKEN is legitimately empty-but-present; keep it explicit.
  if (raw.STRAPI_API_TOKEN !== undefined) {
    cleaned['STRAPI_API_TOKEN'] = raw.STRAPI_API_TOKEN;
  }

  const parsed = envSchema.safeParse(cleaned);

  if (!parsed.success) {
    // Report the offending KEYS and reasons, never the values — a validation
    // error must not print a database password into the logs.
    const issues = parsed.error.issues
      .map((issue) => `  - ${issue.path.join('.') || '(root)'}: ${issue.message}`)
      .join('\n');
    throw new EnvValidationError(`Invalid environment configuration:\n${issues}`);
  }

  // Resolved here rather than as a schema default: the safe value depends on
  // NODE_ENV, which the schema cannot see from inside a single field.
  const env: Env = {
    ...parsed.data,
    DOCS_ENABLED: parsed.data.DOCS_ENABLED ?? parsed.data.NODE_ENV !== 'production',
  };

  if (env.NODE_ENV === 'production') {
    if (env.CORS_ALLOWED_ORIGINS.includes('*')) {
      throw new EnvValidationError(
        'CORS_ALLOWED_ORIGINS must not contain "*" when NODE_ENV=production.',
      );
    }
    if (env.CORS_ALLOWED_ORIGINS.length === 0) {
      throw new EnvValidationError(
        'CORS_ALLOWED_ORIGINS must list at least one origin when NODE_ENV=production.',
      );
    }
  }

  return env;
}
