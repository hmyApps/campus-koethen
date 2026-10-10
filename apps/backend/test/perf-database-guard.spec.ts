import { requirePerfDatabaseUrl } from '../../../scripts/perf/perf-database-url';

/**
 * The benchmark seed writes hundreds of thousands of rows and `--reset`
 * deletes rows. It used to take the ordinary `DATABASE_URL`, and the runbook's
 * `prisma migrate deploy` let dotenv fill that variable from the development
 * `.env` — so a copied command line seeded the development database
 * (AGENTS.md §8: benchmarks only against an explicitly configured, isolated
 * database). These are the same independent checks the integration-test guard
 * (test/helpers/database.ts) applies, for the performance namespace.
 */
describe('performance-seed database guard', () => {
  const perf = 'postgresql://campus_app:perf-only@127.0.0.1:5443/campus_app_perf';

  it('never falls back to the application DATABASE_URL', () => {
    expect(() =>
      requirePerfDatabaseUrl({
        DATABASE_URL: 'postgresql://campus_app:development@localhost:5433/campus_app_local',
      }),
    ).toThrow(/PERF_DATABASE_URL is not set/);
  });

  it.each([perf, 'postgresql://campus_app:perf-only@127.0.0.1:5443/campus_app_perf_run-7'])(
    'accepts the dedicated performance namespace %#',
    (url) => {
      expect(requirePerfDatabaseUrl({ PERF_DATABASE_URL: url, DATABASE_URL: url })).toBe(url);
    },
  );

  it.each([undefined, 'postgresql://campus_app:development@localhost:5433/campus_app_local'])(
    'requires DATABASE_URL to point at the same database (%#)',
    (databaseUrl) => {
      // `prisma migrate deploy` in the same shell reads DATABASE_URL; dotenv
      // only fills it when it is unset. Requiring the match keeps schema and
      // seed on one target.
      expect(() =>
        requirePerfDatabaseUrl({ PERF_DATABASE_URL: perf, DATABASE_URL: databaseUrl }),
      ).toThrow(/DATABASE_URL must exactly match PERF_DATABASE_URL/);
    },
  );

  it.each([
    'postgresql://campus_app:secret-pw@localhost:5432/campus_app_local',
    'postgresql://campus_app:secret-pw@localhost:5432/campus_app_test',
    'postgresql://campus_app:secret-pw@localhost:5432/campus_app_production',
    'postgresql://campus_app:secret-pw@localhost:5432/not_campus_app_perf',
  ])('rejects a database outside the performance namespace %#', (url) => {
    let message = '';
    try {
      requirePerfDatabaseUrl({ PERF_DATABASE_URL: url, DATABASE_URL: url });
    } catch (error) {
      message = (error as Error).message;
    }
    expect(message).toMatch(/dedicated Campus performance database/);
    // The value may hold a password; it is never echoed.
    expect(message).not.toContain('secret-pw');
  });

  it('rejects a connection target overridden in the query string', () => {
    const url = `${perf}?host=db.example.invalid`;
    expect(() => requirePerfDatabaseUrl({ PERF_DATABASE_URL: url, DATABASE_URL: url })).toThrow(
      /must not override its connection target/,
    );
  });

  it('rejects a non-PostgreSQL URL', () => {
    const url = 'mysql://campus_app:x@127.0.0.1:3306/campus_app_perf';
    expect(() => requirePerfDatabaseUrl({ PERF_DATABASE_URL: url, DATABASE_URL: url })).toThrow(
      /PostgreSQL protocol/,
    );
  });

  it('refuses to run with NODE_ENV=production', () => {
    expect(() =>
      requirePerfDatabaseUrl({
        NODE_ENV: 'production',
        PERF_DATABASE_URL: perf,
        DATABASE_URL: perf,
      }),
    ).toThrow(/NODE_ENV=production/);
  });
});
