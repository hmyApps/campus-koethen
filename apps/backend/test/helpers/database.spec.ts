import { requireTestDatabaseUrl } from './database';

describe('destructive integration-test database guard', () => {
  const originalNodeEnv = process.env['NODE_ENV'];
  const originalDatabaseUrl = process.env['DATABASE_URL'];
  const originalTestDatabaseUrl = process.env['TEST_DATABASE_URL'];

  beforeEach(() => {
    process.env['NODE_ENV'] = 'test';
    process.env['DATABASE_URL'] =
      'postgresql://campus_app:development@localhost:5433/campus_app_local';
    delete process.env['TEST_DATABASE_URL'];
  });

  afterAll(() => {
    restoreEnvironment('NODE_ENV', originalNodeEnv);
    restoreEnvironment('DATABASE_URL', originalDatabaseUrl);
    restoreEnvironment('TEST_DATABASE_URL', originalTestDatabaseUrl);
  });

  it('never falls back to the application DATABASE_URL', () => {
    expect(() => requireTestDatabaseUrl()).toThrow(/TEST_DATABASE_URL is not set/);
  });

  it('accepts only the dedicated Campus test-database namespace', () => {
    const url =
      'postgresql://campus_app:test-only@localhost:5432/campus_app_test_run-42?schema=public';
    process.env['TEST_DATABASE_URL'] = url;
    process.env['DATABASE_URL'] = url;

    expect(requireTestDatabaseUrl()).toBe(url);
  });

  it('rejects a different application URL before a test can boot AppModule', () => {
    process.env['TEST_DATABASE_URL'] =
      'postgresql://campus_app:test-only@localhost:5432/campus_app_test';

    expect(() => requireTestDatabaseUrl()).toThrow(
      /DATABASE_URL must exactly match TEST_DATABASE_URL/,
    );
  });

  it.each([
    'postgresql://campus_app:secret@localhost:5432/campus_app_local',
    'postgresql://campus_app:secret@localhost:5432/campus_app_production',
    'postgresql://campus_app:secret@localhost:5432/not_this_project_test',
  ])('rejects an unmarked database name', (url) => {
    process.env['TEST_DATABASE_URL'] = url;
    process.env['DATABASE_URL'] = url;

    expect(() => requireTestDatabaseUrl()).toThrow(/dedicated Campus test database/);
  });

  it('rejects execution outside NODE_ENV=test', () => {
    process.env['NODE_ENV'] = 'development';
    process.env['TEST_DATABASE_URL'] =
      'postgresql://campus_app:secret@localhost:5432/campus_app_test';

    expect(() => requireTestDatabaseUrl()).toThrow(/NODE_ENV=test/);
  });

  it('rejects malformed and non-PostgreSQL URLs without disclosing their values', () => {
    const secret = 'do-not-print-this-password';
    const values = [
      `not-a-url-${secret}`,
      `mysql://campus_app:${secret}@localhost:3306/campus_app_test`,
    ];

    for (const value of values) {
      process.env['TEST_DATABASE_URL'] = value;
      process.env['DATABASE_URL'] = value;
      try {
        requireTestDatabaseUrl();
        throw new Error('Expected the database guard to reject the URL');
      } catch (error) {
        expect(String(error)).not.toContain(secret);
        expect(String(error)).not.toContain(value);
      }
    }
  });

  it.each([
    'postgresql://campus_app:secret@localhost:5432/campus_app_test?database=campus_app_local',
    'postgresql://campus_app:secret@localhost:5432/campus_app_test?dbname=campus_app_local',
    'postgresql://campus_app:secret@localhost:5432/campus_app_test?host=production-db',
    'postgresql://campus_app:secret@localhost:5432/campus_app_test?port=5439',
  ])('rejects query parameters that could override the guarded target', (url) => {
    process.env['TEST_DATABASE_URL'] = url;
    process.env['DATABASE_URL'] = url;

    expect(() => requireTestDatabaseUrl()).toThrow(/must not override its connection target/);
  });

  it('rejects a connection URL without an explicit host', () => {
    const url = 'postgresql:///campus_app_test';
    process.env['TEST_DATABASE_URL'] = url;
    process.env['DATABASE_URL'] = url;

    expect(() => requireTestDatabaseUrl()).toThrow(/explicit host/);
  });
});

function restoreEnvironment(key: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = value;
  }
}
