import { JsonLogger, redactValue } from './json-logger.service';

describe('redactValue', () => {
  it('redacts credentials embedded in a connection string', () => {
    const out = redactValue('postgresql://campus_app:s3cr3t-pw@db:5432/campus') as string;
    expect(out).not.toContain('s3cr3t-pw');
    expect(out).toContain('campus_app');
    expect(out).toContain('[redacted]');
  });

  it('redacts a bearer token in free text', () => {
    const out = redactValue('called with Bearer abcdef0123456789ABC') as string;
    expect(out).not.toContain('abcdef0123456789ABC');
    expect(out).toContain('[redacted]');
  });

  it('redacts values of sensitive keys regardless of case', () => {
    const out = redactValue({
      STRAPI_API_TOKEN: 'tok_live_123',
      Password: 'hunter2',
      apiKey: 'k-1',
      authorization: 'Bearer x',
      encryptionKey: 'e',
      safe: 'visible',
    }) as Record<string, unknown>;

    expect(out['STRAPI_API_TOKEN']).toBe('[redacted]');
    expect(out['Password']).toBe('[redacted]');
    expect(out['apiKey']).toBe('[redacted]');
    expect(out['authorization']).toBe('[redacted]');
    expect(out['encryptionKey']).toBe('[redacted]');
    expect(out['safe']).toBe('visible');
  });

  it('redacts recursively through nested structures', () => {
    const out = JSON.stringify(redactValue({ outer: { inner: [{ token: 'leak-me' }] } }));
    expect(out).not.toContain('leak-me');
  });

  it('does not recurse without bound', () => {
    const deep: Record<string, unknown> = {};
    let cursor = deep;
    for (let i = 0; i < 30; i += 1) {
      const next: Record<string, unknown> = {};
      cursor['next'] = next;
      cursor = next;
    }
    expect(() => JSON.stringify(redactValue(deep))).not.toThrow();
    expect(JSON.stringify(redactValue(deep))).toContain('[truncated]');
  });

  it('keeps ordinary values untouched', () => {
    expect(redactValue('plain message')).toBe('plain message');
    expect(redactValue(42)).toBe(42);
    expect(redactValue(null)).toBeNull();
  });

  describe('an Error', () => {
    const originalNodeEnv = process.env['NODE_ENV'];

    afterEach(() => {
      process.env['NODE_ENV'] = originalNodeEnv;
    });

    function failure(): Error {
      // The message is the sensitive part: it is free text that can carry
      // whatever the failing code interpolated — a query value, an address.
      return Object.assign(new Error('lookup failed for demo-person@example.invalid'), {
        code: 'P2025',
      });
    }

    it('is reduced to its name and code in production — no message, no stack', () => {
      process.env['NODE_ENV'] = 'production';

      const out = redactValue(failure());

      expect(out).toEqual({ name: 'Error', code: 'P2025' });
      expect(JSON.stringify(out)).not.toContain('demo-person@example.invalid');
    });

    it('keeps message and stack outside production, still redacted', () => {
      process.env['NODE_ENV'] = 'development';
      const error = new Error('connecting to postgresql://campus_app:s3cr3t-pw@db:5432/campus');

      const out = redactValue(error) as Record<string, unknown>;

      expect(out['name']).toBe('Error');
      expect(String(out['message'])).not.toContain('s3cr3t-pw');
      expect(String(out['message'])).toContain('[redacted]');
      expect(typeof out['stack']).toBe('string');
    });
  });
});

describe('JsonLogger', () => {
  let written: string[];
  let stdout: jest.SpyInstance;
  let stderr: jest.SpyInstance;

  beforeEach(() => {
    written = [];
    const capture = (chunk: unknown): boolean => {
      written.push(String(chunk));
      return true;
    };
    stdout = jest.spyOn(process.stdout, 'write').mockImplementation(capture);
    stderr = jest.spyOn(process.stderr, 'write').mockImplementation(capture);
  });

  afterEach(() => {
    stdout.mockRestore();
    stderr.mockRestore();
  });

  it('redacts a sensitive key inside an OBJECT message', () => {
    // The codebase logs objects (see PublicCalendarSyncService, PostsService).
    // Serialising first and redacting the resulting string afterwards means the
    // key-based rules never run — which is the whole second line of defence.
    new JsonLogger().warn({ message: 'sync failed', token: 'tok_live_123' });

    expect(written.join('')).not.toContain('tok_live_123');
    expect(written.join('')).toContain('[redacted]');
  });

  it('still redacts credentials in a plain string message', () => {
    new JsonLogger().warn('connecting to postgresql://campus_app:s3cr3t-pw@db:5432/campus');

    expect(written.join('')).not.toContain('s3cr3t-pw');
  });

  it('logs a circular structure instead of throwing inside the logger', () => {
    const circular: Record<string, unknown> = { name: 'run' };
    circular['self'] = circular;

    expect(() => new JsonLogger().error(circular)).not.toThrow();
    expect(written.join('')).toContain('run');
  });

  it('writes one JSON object per line', () => {
    new JsonLogger().log('hello', 'SomeContext');

    expect(written).toHaveLength(1);
    const entry = JSON.parse(written[0]!.trimEnd()) as Record<string, unknown>;
    expect(entry['level']).toBe('info');
    expect(entry['message']).toBe('hello');
    expect(entry['context']).toBe('SomeContext');
  });
});
