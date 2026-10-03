import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../../src/generated/prisma/client';

/**
 * Real-database helper for integration tests.
 *
 * The synchronisation guarantees this project makes ("an empty or failed
 * upstream response never deletes stored data") are statements about database
 * state. Asserting them against a mock would prove nothing, so these tests run
 * against a genuine PostgreSQL instance — locally via
 * infrastructure/local/compose.yaml, in CI via a postgres service container.
 */

const testDatabaseName = /^campus_app_test(?:_[a-z0-9-]+)?$/i;

/**
 * Returns the connection string reserved for destructive integration tests.
 *
 * The independent checks are deliberate: the dedicated environment key and
 * its exact match with the application URL prevent split test/app targets,
 * Jest's test mode prevents use from a normal process, and the project-specific
 * database namespace catches a copied development or production URL. Target
 * overrides in query parameters are forbidden. Error messages never
 * interpolate the supplied value because it may contain a password.
 */
export function requireTestDatabaseUrl(): string {
  if (process.env['NODE_ENV'] !== 'test') {
    throw new Error('Destructive database tests require NODE_ENV=test.');
  }

  const value = process.env['TEST_DATABASE_URL'];
  if (!value) {
    throw new Error(
      'TEST_DATABASE_URL is not set. Configure an isolated database named ' +
        'campus_app_test or campus_app_test_<run-id>.',
    );
  }
  if (process.env['DATABASE_URL'] !== value) {
    throw new Error(
      'DATABASE_URL must exactly match TEST_DATABASE_URL while integration tests run.',
    );
  }

  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error('TEST_DATABASE_URL must be a valid PostgreSQL connection string.');
  }
  if (parsed.protocol !== 'postgresql:' && parsed.protocol !== 'postgres:') {
    throw new Error('TEST_DATABASE_URL must use the PostgreSQL protocol.');
  }
  if (!parsed.hostname) {
    throw new Error('TEST_DATABASE_URL must contain an explicit host.');
  }
  const targetOverrides = new Set(['database', 'dbname', 'host', 'hostaddr', 'port', 'service']);
  if ([...parsed.searchParams.keys()].some((key) => targetOverrides.has(key.toLowerCase()))) {
    throw new Error(
      'TEST_DATABASE_URL must not override its connection target in query parameters.',
    );
  }

  let databaseName: string;
  try {
    databaseName = decodeURIComponent(parsed.pathname.replace(/^\//, ''));
  } catch {
    throw new Error('TEST_DATABASE_URL contains an invalid database name.');
  }
  if (!testDatabaseName.test(databaseName)) {
    throw new Error(
      'TEST_DATABASE_URL must target a dedicated Campus test database named ' +
        'campus_app_test or campus_app_test_<run-id>.',
    );
  }
  return value;
}

export function createTestPrisma(): PrismaClient {
  return new PrismaClient({
    adapter: new PrismaPg({ connectionString: requireTestDatabaseUrl() }),
  });
}

/** Wipes all operational tables. Order respects foreign keys. */
export async function resetDatabase(prisma: PrismaClient): Promise<void> {
  // Re-check at the destructive boundary as defence in depth. This also keeps
  // a future caller from passing an unrelated Prisma client to this helper in
  // a non-test process and assuming createTestPrisma() already guarded it.
  requireTestDatabaseUrl();
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE ' +
      'timetable_entry_groups, timetable_entries, timetable_groups, timetable_contexts, ' +
      'timetable_sync_runs, meal_prices, meals, sync_runs, ingredient_definitions, canteens, ' +
      'public_calendar_events, public_calendar_sync_runs, public_calendars ' +
      'RESTART IDENTITY CASCADE',
  );
}
