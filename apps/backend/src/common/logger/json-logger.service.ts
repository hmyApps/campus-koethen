import { ConsoleLogger, Injectable, LogLevel, Scope } from '@nestjs/common';

/**
 * Structured JSON logger.
 *
 * One JSON object per line so a log shipper can parse it without a regex.
 * Deliberately dependency-free: no external logging service, no telemetry.
 *
 * Secrets never reach the log. Values that look like credentials are redacted
 * defensively here as a second line of defence — the first is simply not
 * logging them.
 */

const LEVEL_SEVERITY: Record<string, number> = {
  debug: 10,
  verbose: 10,
  log: 20,
  info: 20,
  warn: 30,
  error: 40,
  fatal: 50,
};

const REDACTED = '[redacted]';

/** Keys whose values are never safe to print, matched case-insensitively. */
const SENSITIVE_KEY_PATTERN =
  /(pass(word)?|secret|token|api[-_]?key|authorization|cookie|credential|salt|encryption)/i;

/** Inline credentials inside a connection string or URL. */
const URL_CREDENTIALS_PATTERN = /(\b[a-z][a-z0-9+.-]*:\/\/)([^:/\s@]+):([^@/\s]+)@/gi;

/** Bearer tokens that slipped into a free-text message. */
const BEARER_PATTERN = /\b(bearer\s+)[A-Za-z0-9._~+/-]{8,}=*/gi;

/** Machine-readable error codes such as `P2025` or `ECONNREFUSED`, never free text. */
const ERROR_CODE_PATTERN = /^[A-Za-z0-9_.-]{1,64}$/;

function errorCode(error: Error): string | number | undefined {
  const code = (error as { code?: unknown }).code;
  if (typeof code === 'number' && Number.isFinite(code)) return code;
  if (typeof code === 'string' && ERROR_CODE_PATTERN.test(code)) return code;
  return undefined;
}

export function redactValue(value: unknown, depth = 0): unknown {
  if (depth > 6) {
    return '[truncated]';
  }
  if (typeof value === 'string') {
    return value
      .replace(URL_CREDENTIALS_PATTERN, `$1$2:${REDACTED}@`)
      .replace(BEARER_PATTERN, `$1${REDACTED}`);
  }
  if (Array.isArray(value)) {
    return value.map((entry) => redactValue(entry, depth + 1));
  }
  if (value instanceof Error) {
    const code = errorCode(value);
    const identity = { name: value.name, ...(code === undefined ? {} : { code }) };
    // The message is free text — whatever the failing code interpolated, a
    // query value or an address — and a stack starts with that very message.
    // Production logs get only what classifies the failure.
    if (process.env['NODE_ENV'] === 'production') {
      return identity;
    }
    return {
      ...identity,
      message: redactValue(value.message, depth + 1),
      stack: typeof value.stack === 'string' ? redactValue(value.stack, depth + 1) : undefined,
    };
  }
  if (value && typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      result[key] = SENSITIVE_KEY_PATTERN.test(key) ? REDACTED : redactValue(entry, depth + 1);
    }
    return result;
  }
  return value;
}

/**
 * Serialises an already-redacted value.
 *
 * Logging must not be able to take the caller down with it, and `JSON.stringify`
 * throws on a cycle and on a BigInt — both of which reach a logger through an
 * ordinary domain object often enough.
 */
function safeStringify(value: unknown): string {
  const seen = new WeakSet<object>();
  try {
    return (
      JSON.stringify(value, (_key, entry: unknown) => {
        if (typeof entry === 'object' && entry !== null) {
          if (seen.has(entry)) return '[circular]';
          seen.add(entry);
        }
        return typeof entry === 'bigint' ? entry.toString() : entry;
      }) ?? String(value)
    );
  } catch {
    return '[unserialisable]';
  }
}

/**
 * Redacts FIRST, serialises second.
 *
 * The order is the whole point. `redactValue` blanks the value of any key that
 * looks like a credential, and that rule only exists on its object branch —
 * running it on an already-serialised object leaves nothing but the two
 * free-text patterns, so `{ token: … }` would have travelled verbatim.
 */
function renderMessage(message: unknown): string {
  const redacted = redactValue(message);
  return typeof redacted === 'string' ? redacted : safeStringify(redacted);
}

@Injectable({ scope: Scope.TRANSIENT })
export class JsonLogger extends ConsoleLogger {
  private readonly minSeverity: number;
  private readonly pretty: boolean;

  constructor() {
    super();
    const level = process.env['LOG_LEVEL'] ?? 'info';
    this.minSeverity = LEVEL_SEVERITY[level] ?? LEVEL_SEVERITY['info']!;
    this.pretty = process.env['LOG_PRETTY'] === 'true' || process.env['LOG_PRETTY'] === '1';
  }

  private write(level: LogLevel | 'info' | 'fatal', message: unknown, params: unknown[]): void {
    const severity = LEVEL_SEVERITY[level] ?? 20;
    if (severity < this.minSeverity) {
      return;
    }

    // A trailing string argument is Nest's context convention.
    let context = this.context;
    const rest = [...params];
    if (rest.length > 0 && typeof rest[rest.length - 1] === 'string') {
      context = rest.pop() as string;
    }

    const entry: Record<string, unknown> = {
      timestamp: new Date().toISOString(),
      level: level === 'log' ? 'info' : level,
      message: renderMessage(message),
    };
    if (context) {
      entry['context'] = context;
    }
    if (rest.length > 0) {
      entry['details'] = rest.map((item) => redactValue(item));
    }

    const line = this.pretty ? JSON.stringify(entry, null, 2) : JSON.stringify(entry);
    const stream = severity >= LEVEL_SEVERITY['error']! ? process.stderr : process.stdout;
    stream.write(`${line}\n`);
  }

  override log(message: unknown, ...params: unknown[]): void {
    this.write('log', message, params);
  }
  override error(message: unknown, ...params: unknown[]): void {
    this.write('error', message, params);
  }
  override warn(message: unknown, ...params: unknown[]): void {
    this.write('warn', message, params);
  }
  override debug(message: unknown, ...params: unknown[]): void {
    this.write('debug', message, params);
  }
  override verbose(message: unknown, ...params: unknown[]): void {
    this.write('verbose', message, params);
  }
  override fatal(message: unknown, ...params: unknown[]): void {
    this.write('fatal', message, params);
  }
}
