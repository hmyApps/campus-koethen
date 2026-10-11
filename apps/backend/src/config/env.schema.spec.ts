import { EnvValidationError, validateEnv } from './env.schema';

const BASE = {
  DATABASE_URL: 'postgresql://user:pw@localhost:5432/db',
};

describe('validateEnv', () => {
  it('applies documented defaults', () => {
    const env = validateEnv({ ...BASE });
    expect(env.PORT).toBe(3000);
    expect(env.HOST).toBe('0.0.0.0');
    expect(env.CANTEEN_SYNC_CRON).toBe('0 */2 * * *');
    expect(env.CANTEEN_SYNC_ON_BOOT).toBe(true);
    expect(env.CANTEEN_STALE_AFTER_MINUTES).toBe(240);
    expect(env.WORKER_TIME_ZONE).toBe('UTC');
    expect(env.USER_TEST_DATA_ENABLED).toBe(false);
    expect(env.LOG_LEVEL).toBe('info');
    expect(env.PUBLIC_CALENDAR_LOOKAHEAD_DAYS).toBe(400);
    expect(env.PUBLIC_CALENDAR_API_MAX_RANGE_DAYS).toBe(400);
    expect(env.PUBLIC_CALENDAR_MAX_OCCURRENCES_PER_EVENT).toBe(2000);
    expect(env.PUBLIC_CALENDAR_MAX_OCCURRENCES).toBe(25000);
    expect(env.PUBLIC_CALENDAR_SYNC_ON_BOOT).toBe(true);
    expect(env.WEBUNTIS_GROUP_SYNC_CRON).toBe('0 2 * * *');
    expect(env.WEBUNTIS_ENTRY_SYNC_CRON).toBe('15 2 * * *');
    expect(env.WEBUNTIS_STALE_AFTER_MINUTES).toBe(1800);
    expect(env.WEBUNTIS_SYNC_ON_BOOT).toBe(true);
  });

  it('sends a neutral public-calendar User-Agent without a made-up contact URL', () => {
    const agent = validateEnv({ ...BASE }).PUBLIC_CALENDAR_USER_AGENT;
    expect(agent).toBe('CampusKoethen');
    expect(agent).not.toMatch(/https?:|\d+\.\d+/);
    expect(
      validateEnv({ ...BASE, PUBLIC_CALENDAR_USER_AGENT: 'CampusKoethen (+https://example.org)' })
        .PUBLIC_CALENDAR_USER_AGENT,
    ).toBe('CampusKoethen (+https://example.org)');
  });

  it('accepts a 210-day WebUntis horizon for a full semester', () => {
    expect(validateEnv({ ...BASE, WEBUNTIS_LOOKAHEAD_DAYS: '210' }).WEBUNTIS_LOOKAHEAD_DAYS).toBe(
      210,
    );
  });

  it('rejects a WebUntis horizon longer than the supported semester window', () => {
    expect(() => validateEnv({ ...BASE, WEBUNTIS_LOOKAHEAD_DAYS: '211' })).toThrow(
      EnvValidationError,
    );
  });

  it('accepts an explicit IANA timezone for worker schedules', () => {
    expect(validateEnv({ ...BASE, WORKER_TIME_ZONE: 'Europe/Berlin' }).WORKER_TIME_ZONE).toBe(
      'Europe/Berlin',
    );
  });

  it('uses UTC when the worker timezone is present but empty', () => {
    expect(validateEnv({ ...BASE, WORKER_TIME_ZONE: '' }).WORKER_TIME_ZONE).toBe('UTC');
  });

  it('rejects an invalid worker timezone', () => {
    expect(() => validateEnv({ ...BASE, WORKER_TIME_ZONE: 'Europe/Berln' })).toThrow(
      EnvValidationError,
    );
  });

  it('rejects an invalid public-calendar fallback timezone', () => {
    expect(() =>
      validateEnv({
        ...BASE,
        PUBLIC_CALENDAR_FALLBACK_TIME_ZONE: 'Europe/Berln',
      }),
    ).toThrow(EnvValidationError);
  });

  it('rejects a non-PostgreSQL database url', () => {
    expect(() => validateEnv({ ...BASE, DATABASE_URL: 'mysql://x/y' })).toThrow(EnvValidationError);
  });

  it('requires a database url', () => {
    expect(() => validateEnv({})).toThrow(EnvValidationError);
  });

  it('never includes a secret value in the error message', () => {
    const secret = 'super-secret-password-value';
    try {
      validateEnv({ DATABASE_URL: `mysql://user:${secret}@h/db` });
      throw new Error('expected validation to fail');
    } catch (error) {
      expect((error as Error).message).not.toContain(secret);
      expect((error as Error).message).toContain('DATABASE_URL');
    }
  });

  it('parses a CORS allowlist into trimmed entries', () => {
    const env = validateEnv({
      ...BASE,
      CORS_ALLOWED_ORIGINS: 'https://a.example, https://b.example ,',
    });
    expect(env.CORS_ALLOWED_ORIGINS).toEqual(['https://a.example', 'https://b.example']);
  });

  it('rejects a CORS wildcard in production', () => {
    expect(() =>
      validateEnv({
        ...BASE,
        NODE_ENV: 'production',
        CORS_ALLOWED_ORIGINS: '*',
      }),
    ).toThrow(/must not contain/);
  });

  it('allows a wildcard outside production', () => {
    const env = validateEnv({
      ...BASE,
      NODE_ENV: 'development',
      CORS_ALLOWED_ORIGINS: '*',
    });
    expect(env.CORS_ALLOWED_ORIGINS).toEqual(['*']);
  });

  it('treats an empty variable as unset and uses the default', () => {
    const env = validateEnv({ ...BASE, PORT: '' });
    expect(env.PORT).toBe(3000);
  });

  it('keeps an intentionally empty Strapi token without failing', () => {
    const env = validateEnv({ ...BASE, STRAPI_API_TOKEN: '' });
    expect(env.STRAPI_API_TOKEN).toBe('');
  });

  it('rejects a Strapi base url that is not http(s)', () => {
    expect(() => validateEnv({ ...BASE, STRAPI_BASE_URL: 'ftp://cms.example' })).toThrow(
      EnvValidationError,
    );
  });

  it('requires HTTPS for the public upstream sources', () => {
    expect(() =>
      validateEnv({ ...BASE, CANTEEN_SOURCE_URL: 'http://meine-mensa.example/api' }),
    ).toThrow(EnvValidationError);
    expect(() =>
      validateEnv({ ...BASE, WEBUNTIS_BASE_URL: 'http://webuntis.example/api' }),
    ).toThrow(EnvValidationError);
  });

  it('accepts explicitly configured HTTPS upstream sources', () => {
    const env = validateEnv({
      ...BASE,
      CANTEEN_SOURCE_URL: 'https://meine-mensa.example/api',
      WEBUNTIS_BASE_URL: 'https://webuntis.example/api',
    });

    expect(env.CANTEEN_SOURCE_URL).toBe('https://meine-mensa.example/api');
    expect(env.WEBUNTIS_BASE_URL).toBe('https://webuntis.example/api');
  });

  it('coerces and range-checks numeric settings', () => {
    expect(() => validateEnv({ ...BASE, PORT: '70000' })).toThrow();
    expect(validateEnv({ ...BASE, PORT: '8080' }).PORT).toBe(8080);
  });

  it('parses boolean-ish flags', () => {
    expect(validateEnv({ ...BASE, CANTEEN_SYNC_ON_BOOT: 'true' }).CANTEEN_SYNC_ON_BOOT).toBe(true);
    expect(validateEnv({ ...BASE, CANTEEN_SYNC_ON_BOOT: '0' }).CANTEEN_SYNC_ON_BOOT).toBe(false);
    expect(validateEnv({ ...BASE, USER_TEST_DATA_ENABLED: '1' }).USER_TEST_DATA_ENABLED).toBe(true);
  });

  it('bounds what the canteen client may buffer', () => {
    expect(validateEnv(BASE).CANTEEN_MAX_RESPONSE_BYTES).toBe(8_000_000);
    expect(
      validateEnv({ ...BASE, CANTEEN_MAX_RESPONSE_BYTES: '100000' }).CANTEEN_MAX_RESPONSE_BYTES,
    ).toBe(100_000);
    // Not a limit anyone should be able to switch off by widening it.
    expect(() => validateEnv({ ...BASE, CANTEEN_MAX_RESPONSE_BYTES: '1000' })).toThrow();
  });

  describe('DOCS_ENABLED', () => {
    it('serves the docs page outside production', () => {
      expect(validateEnv({ ...BASE, NODE_ENV: 'development' }).DOCS_ENABLED).toBe(true);
    });

    it('does not serve it in production unless asked to', () => {
      // The page runs under a looser CSP than the API on the same origin, and
      // the contract it renders is already published and versioned.
      expect(
        validateEnv({ ...BASE, NODE_ENV: 'production', CORS_ALLOWED_ORIGINS: 'https://a.example' })
          .DOCS_ENABLED,
      ).toBe(false);
    });

    it('honours an explicit decision in either direction', () => {
      expect(
        validateEnv({
          ...BASE,
          NODE_ENV: 'production',
          CORS_ALLOWED_ORIGINS: 'https://a.example',
          DOCS_ENABLED: 'true',
        }).DOCS_ENABLED,
      ).toBe(true);
      expect(
        validateEnv({ ...BASE, NODE_ENV: 'development', DOCS_ENABLED: 'false' }).DOCS_ENABLED,
      ).toBe(false);
    });
  });
});
