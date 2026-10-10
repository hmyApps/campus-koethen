/**
 * Target guard for the performance-baseline seed.
 *
 * The seed writes hundreds of thousands of rows and `--reset` deletes rows, so
 * it may only ever touch a database created for exactly that purpose
 * (AGENTS.md §8). It deliberately does NOT read the ordinary `DATABASE_URL` on
 * its own: that variable points at the development database in every normal
 * shell, and `prisma migrate deploy` lets dotenv fill it from `.env` whenever
 * it is unset.
 *
 * The checks mirror the integration-test guard (apps/backend/test/helpers/
 * database.ts): a dedicated variable, an exact match with `DATABASE_URL` so
 * migrations and seed share one target, a project-specific database name, and
 * no target overrides hidden in query parameters. Error messages never
 * interpolate the supplied value because it may contain a password.
 */

const PERF_DATABASE_NAME = /^campus_app_perf(?:_[a-z0-9-]+)?$/i;
const TARGET_OVERRIDES = new Set(['database', 'dbname', 'host', 'hostaddr', 'port', 'service']);

export function requirePerfDatabaseUrl(
  env: Readonly<Record<string, string | undefined>> = process.env,
): string {
  if (env['NODE_ENV'] === 'production') {
    throw new Error('seed-perf-dataset refuses to run with NODE_ENV=production.');
  }

  const value = env['PERF_DATABASE_URL'];
  if (!value) {
    throw new Error(
      'PERF_DATABASE_URL is not set. Configure an isolated database named ' +
        'campus_app_perf or campus_app_perf_<run-id> (docs/performance-baseline.md, section 11).',
    );
  }
  if (env['DATABASE_URL'] !== value) {
    throw new Error(
      'DATABASE_URL must exactly match PERF_DATABASE_URL, so that `prisma migrate deploy` ' +
        'and the seed target the same isolated database.',
    );
  }

  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error('PERF_DATABASE_URL must be a valid PostgreSQL connection string.');
  }
  if (parsed.protocol !== 'postgresql:' && parsed.protocol !== 'postgres:') {
    throw new Error('PERF_DATABASE_URL must use the PostgreSQL protocol.');
  }
  if (!parsed.hostname) {
    throw new Error('PERF_DATABASE_URL must contain an explicit host.');
  }
  if ([...parsed.searchParams.keys()].some((key) => TARGET_OVERRIDES.has(key.toLowerCase()))) {
    throw new Error(
      'PERF_DATABASE_URL must not override its connection target in query parameters.',
    );
  }

  let databaseName: string;
  try {
    databaseName = decodeURIComponent(parsed.pathname.replace(/^\//, ''));
  } catch {
    throw new Error('PERF_DATABASE_URL contains an invalid database name.');
  }
  if (!PERF_DATABASE_NAME.test(databaseName)) {
    throw new Error(
      'PERF_DATABASE_URL must target a dedicated Campus performance database named ' +
        'campus_app_perf or campus_app_perf_<run-id>.',
    );
  }
  return value;
}
