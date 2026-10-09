/**
 * Per-request database evidence for the Campus API baseline.
 *
 * Latency alone cannot tell an optimisation team WHERE a request spends its
 * time, and "how many queries does this endpoint run" is the single most
 * actionable number for a Prisma codebase — an N+1 shows up as a query count
 * that scales with the result set, which a millisecond figure hides.
 *
 * Method: PostgreSQL logs every statement (log_statement=all,
 * log_min_duration_statement=0). Each endpoint is bracketed by a sentinel
 * statement, one request is issued, and the statements logged between the two
 * sentinels are attributed to that request. Counting is therefore observational
 * rather than instrumented — no application code is modified to measure it.
 *
 * The endpoint is called TWICE and only the second call is attributed: the
 * first fills the TTL caches, so the count reported is the steady-state one an
 * ordinary request pays. The cold count is reported alongside it, because the
 * gap between the two is exactly what the caches are worth.
 *
 * Usage:
 *   node scripts/perf/measure-queries.mjs --base-url http://127.0.0.1:3099 \
 *     --container campus-perf-pg --out artifacts/perf/query-counts.json
 */

import { execFileSync, execSync } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};

const baseUrl = (arg('base-url', 'http://127.0.0.1:3099') ?? '').replace(/\/+$/, '');
const container = arg('container', 'campus-perf-pg');
const database = arg('database', 'campus_app_perf');
const outFile = arg('out', '');

const ROUTES = [
  { name: 'canteens-list', path: '/v1/canteens?locale=de' },
  {
    name: 'canteen-menu-7d',
    path: '/v1/canteens/perf-canteen-1/menu?locale=de&from=2026-03-02&to=2026-03-08',
  },
  {
    name: 'canteen-menu-14d',
    path: '/v1/canteens/perf-canteen-1/menu?locale=de&from=2026-03-02&to=2026-03-15',
  },
  { name: 'timetable-status', path: '/v1/timetable/status' },
  { name: 'timetable-groups', path: '/v1/timetable/groups?locale=de' },
  { name: 'calendars-list', path: '/v1/calendars?locale=de' },
  {
    name: 'calendar-events-single-30d',
    path: '/v1/calendars/perf-calendar-00/events?from=2026-03-02&to=2026-04-01',
  },
  {
    name: 'calendar-events-agg-12x30d',
    path: `/v1/calendars/events?from=2026-03-02&to=2026-04-01&${Array.from(
      { length: 12 },
      (_, i) => `calendar=perf-calendar-${String(i).padStart(2, '0')}`,
    ).join('&')}`,
  },
  { name: 'posts-list-p1', path: '/v1/posts?locale=de&page=1&pageSize=20' },
  { name: 'posts-detail', path: '/v1/posts/perf-post-1?locale=de' },
  { name: 'contact-areas', path: '/v1/contact-areas?locale=de' },
  { name: 'rooms-list', path: '/v1/rooms?locale=de' },
];

function psql(sql) {
  return execFileSync(
    'docker',
    ['exec', container, 'psql', '-U', 'postgres', '-d', database, '-t', '-c', sql],
    {
      encoding: 'utf8',
    },
  );
}

function containerLog() {
  // PostgreSQL writes its log to stderr, so the stream has to be merged
  // explicitly — reading stdout alone yields an empty log and, with it, a
  // silent zero for every query count.
  return execSync(`docker logs --tail 40000 ${container} 2>&1`, {
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
  });
}

function sentinel(tag) {
  psql(`SELECT 'PERF_SENTINEL_${tag}' AS marker;`);
}

/**
 * Statements between two sentinels.
 *
 * PostgreSQL logs a prepared statement as two lines — `execute <unnamed>: SQL`
 * and, once it finishes, a bare `duration: N ms` from the same backend pid.
 * They are paired by pid here rather than by adjacency, because a concurrent
 * backend (the sentinel's own psql session) interleaves its lines with the
 * API's.
 *
 * The sentinel SELECTs and the readiness probe's `SELECT 1` are excluded:
 * counting them would add a constant to every endpoint and make the numbers
 * useless for comparison.
 */
function statementsBetween(log, openTag, closeTag) {
  const start = log.lastIndexOf(`PERF_SENTINEL_${openTag}`);
  const end = log.lastIndexOf(`PERF_SENTINEL_${closeTag}`);
  if (start < 0 || end < 0 || end <= start) return { count: 0, totalMs: 0, statements: [] };

  const lines = log.slice(start, end).split('\n');
  const pending = new Map();
  const statements = [];
  let totalMs = 0;
  // A statement can span several log lines (the raw LATERAL query does).
  // Continuation lines carry no timestamp, so they are appended to whichever
  // backend logged the statement last.
  let lastPid = null;

  for (const line of lines) {
    const pidMatch = /^\d{4}-\d{2}-\d{2} [\d:.]+ \w+ \[(\d+)\]/.exec(line);
    if (!pidMatch) {
      if (lastPid !== null && pending.has(lastPid)) {
        pending.set(lastPid, `${pending.get(lastPid)} ${line.trim()}`);
      }
      continue;
    }
    const pid = pidMatch[1];
    lastPid = pid;

    const stmtMatch = /LOG: {2}(?:execute [^:]*|statement): (.*)$/.exec(line);
    if (stmtMatch) {
      const sql = stmtMatch[1].trim();
      if (sql.includes('PERF_SENTINEL') || /^SELECT 1\b/.test(sql)) {
        pending.delete(pid);
        lastPid = null;
        continue;
      }
      pending.set(pid, sql);
      continue;
    }

    const durationMatch = /LOG: {2}duration: ([\d.]+) ms\s*$/.exec(line);
    if (durationMatch && pending.has(pid)) {
      const sql = pending.get(pid).replace(/\s+/g, ' ').trim();
      pending.delete(pid);
      const ms = Number(durationMatch[1]);
      totalMs += ms;
      statements.push({ ms, sql: sql.length > 400 ? `${sql.slice(0, 400)}...` : sql });
    }
  }

  return { count: statements.length, totalMs: Number(totalMs.toFixed(2)), statements };
}

async function main() {
  const results = [];

  for (const route of ROUTES) {
    const url = `${baseUrl}${route.path}`;

    // Cold: caches empty for this route's data.
    sentinel(`${route.name}_COLD_OPEN`);
    await fetch(url, { headers: { accept: 'application/json' } }).then((r) => r.arrayBuffer());
    sentinel(`${route.name}_COLD_CLOSE`);

    // Warm: TTL caches now populated.
    sentinel(`${route.name}_WARM_OPEN`);
    const response = await fetch(url, { headers: { accept: 'application/json' } });
    await response.arrayBuffer();
    sentinel(`${route.name}_WARM_CLOSE`);

    const log = containerLog();
    const cold = statementsBetween(log, `${route.name}_COLD_OPEN`, `${route.name}_COLD_CLOSE`);
    const warm = statementsBetween(log, `${route.name}_WARM_OPEN`, `${route.name}_WARM_CLOSE`);

    results.push({
      name: route.name,
      path: route.path,
      status: response.status,
      coldQueries: cold.count,
      coldDbMs: cold.totalMs,
      warmQueries: warm.count,
      warmDbMs: warm.totalMs,
      warmStatements: warm.statements,
    });

    process.stdout.write(
      `${route.name.padEnd(30)} cold=${String(cold.count).padStart(2)}q/${String(cold.totalMs).padStart(7)}ms  ` +
        `warm=${String(warm.count).padStart(2)}q/${String(warm.totalMs).padStart(7)}ms\n`,
    );
  }

  if (outFile) {
    mkdirSync(dirname(outFile), { recursive: true });
    writeFileSync(outFile, `${JSON.stringify({ baseUrl, results }, null, 2)}\n`);
    process.stdout.write(`\nWrote ${outFile}\n`);
  }
}

await main();
