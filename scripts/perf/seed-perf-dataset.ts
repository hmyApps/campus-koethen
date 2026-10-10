/**
 * Deterministic benchmark dataset for the Campus API performance baseline.
 *
 * Reproducibility is the whole point, so nothing here is random in the usual
 * sense: the generator is seeded, the base date is passed in rather than read
 * from the clock, and running it twice against an empty database produces byte
 * identical rows. A baseline taken today can therefore be compared with a
 * measurement taken after an optimisation.
 *
 * SAFETY: every row this writes carries the marker source `perf-baseline` or
 * the slug prefix `perf-`. `--reset` deletes exactly those rows and nothing
 * else, so the script can never remove imported or editorial data. It refuses
 * to run against NODE_ENV=production, and it only connects to a dedicated
 * performance database: PERF_DATABASE_URL, named campus_app_perf[_<run-id>],
 * with DATABASE_URL set to the very same value (perf-database-url.ts).
 *
 * Usage (from the repository root, see docs/performance-baseline.md §11):
 *   export PERF_DATABASE_URL="postgresql://campus_app:<lokal>@127.0.0.1:5443/campus_app_perf"
 *   export DATABASE_URL="$PERF_DATABASE_URL"
 *   pnpm --filter @campus/backend exec ts-node --project ../../scripts/perf/tsconfig.json \
 *     ../../scripts/perf/seed-perf-dataset.ts --profile realistic --reset
 */

import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../../apps/backend/src/generated/prisma/client';
import { DatasetProfile, PROFILES, ProfileName, expectedRowCounts } from './dataset-profiles';
import { requirePerfDatabaseUrl } from './perf-database-url';

/** Fixed anchor so dates — and therefore query plans — repeat exactly. */
const BASE_DATE = new Date('2026-03-02T00:00:00.000Z');
const MARKER_SOURCE = 'perf-baseline';
const SLUG_PREFIX = 'perf-';
const BATCH = 5_000;

/** Mulberry32: tiny, seeded, and stable across Node versions. */
function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pick<T>(random: () => number, values: readonly T[]): T {
  return values[Math.floor(random() * values.length)] as T;
}

function addDays(base: Date, days: number): Date {
  return new Date(base.getTime() + days * 86_400_000);
}

async function insertInBatches<T>(
  label: string,
  rows: T[],
  write: (chunk: T[]) => Promise<unknown>,
): Promise<void> {
  const started = Date.now();
  for (let i = 0; i < rows.length; i += BATCH) {
    await write(rows.slice(i, i + BATCH));
  }
  process.stdout.write(`  ${label}: ${rows.length} rows in ${Date.now() - started} ms\n`);
}

const DISH_NAMES = [
  'Kartoffelgratin mit Blattspinat',
  'Hähnchenbrust in Kräuterrahm',
  'Gemüsepfanne mit Basmatireis',
  'Rindergulasch mit Rotkohl',
  'Nudelauflauf mit Tomatensauce',
  'Linseneintopf mit Bauernbrot',
  'Seelachsfilet mit Petersilienkartoffeln',
  'Süßkartoffelcurry mit Kokosmilch',
] as const;

const SUBJECTS = [
  'Analysis',
  'Technische Mechanik',
  'Datenbanken',
  'Softwaretechnik',
  'Regelungstechnik',
  'Betriebswirtschaftslehre',
  'Verfahrenstechnik',
  'Werkstoffkunde',
] as const;

const DEPARTMENTS = ['EMW', 'INF', 'WIW', 'LOEL', 'BAU'] as const;

async function reset(prisma: PrismaClient): Promise<void> {
  process.stdout.write('Removing previous perf-baseline rows...\n');
  // Order matters only where no cascade exists; meals/events cascade from their
  // parents, but the markers are on the child rows too, so they are explicit.
  await prisma.mealPrice.deleteMany({ where: { meal: { source: MARKER_SOURCE } } });
  await prisma.meal.deleteMany({ where: { source: MARKER_SOURCE } });
  await prisma.syncRun.deleteMany({ where: { source: MARKER_SOURCE } });
  await prisma.canteen.deleteMany({ where: { slug: { startsWith: SLUG_PREFIX } } });

  await prisma.timetableEntryGroup.deleteMany({
    where: { entry: { source: MARKER_SOURCE } },
  });
  await prisma.timetableEntry.deleteMany({ where: { source: MARKER_SOURCE } });
  await prisma.timetableGroup.deleteMany({ where: { source: MARKER_SOURCE } });
  await prisma.timetableSyncRun.deleteMany({ where: { kind: { startsWith: SLUG_PREFIX } } });

  await prisma.publicCalendarEvent.deleteMany({
    where: { calendar: { slug: { startsWith: SLUG_PREFIX } } },
  });
  await prisma.publicCalendar.deleteMany({ where: { slug: { startsWith: SLUG_PREFIX } } });
}

async function seedCanteen(prisma: PrismaClient, p: DatasetProfile): Promise<void> {
  const random = rng(1001);

  const canteenIds: string[] = [];
  for (let i = 0; i < p.canteens; i += 1) {
    const created = await prisma.canteen.create({
      data: {
        slug: `${SLUG_PREFIX}canteen-${i + 1}`,
        // Kept far away from the real location_ids in canteens.config.ts.
        sourceLocationId: 900_000 + i,
        displayNameDe: `Perf-Mensa ${i + 1}`,
        displayNameEn: `Perf Canteen ${i + 1}`,
        campusLabelDe: `Perf-Campus ${i + 1}`,
        campusLabelEn: `Perf Campus ${i + 1}`,
        active: true,
        sortOrder: (i + 1) * 10,
      },
      select: { id: true },
    });
    canteenIds.push(created.id);
  }

  // Ingredient dictionary: the real import produces well under a hundred codes.
  const definitions = Array.from({ length: 80 }, (_, i) => ({
    code: `P${String(i).padStart(3, '0')}`,
    labelDe: `Perf-Zutat ${i}`,
    labelEn: null,
    kind: i % 4 === 0 ? 'marker' : 'ingredient',
  }));
  await prisma.ingredientDefinition.createMany({ data: definitions, skipDuplicates: true });

  let planId = 900_000_000;
  const meals: Array<{
    sourcePlanId: number;
    source: string;
    canteenId: string;
    date: Date;
    counterId: number;
    isSprint: boolean;
    name: string;
    subtitle: string | null;
    extras: string[];
    ingredientCodes: string[];
  }> = [];

  // Menu history runs backwards from the anchor and forwards over the
  // CANTEEN_SYNC_DAYS_AHEAD window, which is what a live database looks like.
  const firstDay = -(p.canteenDays - 14);
  for (const canteenId of canteenIds) {
    for (let day = firstDay; day < 14; day += 1) {
      for (let m = 0; m < p.mealsPerCanteenDay; m += 1) {
        planId += 1;
        meals.push({
          sourcePlanId: planId,
          source: MARKER_SOURCE,
          canteenId,
          date: addDays(BASE_DATE, day),
          counterId: 1 + (m % 4),
          isSprint: m % 6 === 0,
          name: pick(random, DISH_NAMES),
          subtitle: random() < 0.6 ? 'mit Salatbeilage' : null,
          extras: random() < 0.4 ? ['Dessert', 'Salat'] : [],
          ingredientCodes: Array.from(
            { length: 2 + Math.floor(random() * 4) },
            () => `P${String(Math.floor(random() * 80)).padStart(3, '0')}`,
          ),
        });
      }
    }
  }

  await insertInBatches('meals', meals, (chunk) =>
    prisma.meal.createMany({ data: chunk, skipDuplicates: true }),
  );

  // Prices are read back by id because createMany does not return them.
  const created = await prisma.meal.findMany({
    where: { source: MARKER_SOURCE },
    select: { id: true },
  });
  const prices = created.flatMap((meal) => [
    { mealId: meal.id, group: 'student', amount: '2.90' },
    { mealId: meal.id, group: 'employee', amount: '4.60' },
    { mealId: meal.id, group: 'guest', amount: '6.10' },
  ]);
  await insertInBatches('meal_prices', prices, (chunk) =>
    prisma.mealPrice.createMany({ data: chunk, skipDuplicates: true }),
  );

  // Twelve runs a day per canteen, matching CANTEEN_SYNC_CRON.
  const runs: Array<{
    source: string;
    canteenId: string;
    startedAt: Date;
    finishedAt: Date;
    status: string;
    recordsReceived: number;
    recordsUpserted: number;
    recordsRejected: number;
  }> = [];
  for (const canteenId of canteenIds) {
    for (let day = 0; day < p.canteenSyncRunDays; day += 1) {
      for (let slot = 0; slot < 12; slot += 1) {
        const startedAt = new Date(BASE_DATE.getTime() - day * 86_400_000 + slot * 2 * 3_600_000);
        // A small share of failures, so "newest successful run" is a real
        // filter rather than "newest row".
        const failed = (day * 12 + slot) % 37 === 0;
        runs.push({
          source: MARKER_SOURCE,
          canteenId,
          startedAt,
          finishedAt: new Date(startedAt.getTime() + 4_000),
          status: failed ? 'failed' : 'success',
          recordsReceived: failed ? 0 : 168,
          recordsUpserted: failed ? 0 : 168,
          recordsRejected: 0,
        });
      }
    }
  }
  await insertInBatches('sync_runs', runs, (chunk) => prisma.syncRun.createMany({ data: chunk }));
}

async function seedTimetable(prisma: PrismaClient, p: DatasetProfile): Promise<void> {
  const random = rng(2002);

  const groups = Array.from({ length: p.timetableGroups }, (_, i) => ({
    source: MARKER_SOURCE,
    externalId: `perf-group-${i}`,
    shortName: `PG${String(i).padStart(3, '0')}`,
    longName: `Perf-Gruppe ${i} ${pick(random, SUBJECTS)}`,
    department: pick(random, DEPARTMENTS),
    active: true,
  }));
  await insertInBatches('timetable_groups', groups, (chunk) =>
    prisma.timetableGroup.createMany({ data: chunk, skipDuplicates: true }),
  );
  const groupRows = await prisma.timetableGroup.findMany({
    where: { source: MARKER_SOURCE },
    select: { id: true },
    orderBy: { externalId: 'asc' },
  });

  const entries: Array<{
    source: string;
    externalKey: string;
    startsAt: Date;
    endsAt: Date;
    date: Date;
    title: string;
    subjectCode: string;
    type: string;
    status: string;
    teachers: Array<{ shortName: string; displayName: string }>;
    rooms: Array<{ shortName: string; longName: null }>;
  }> = [];
  // Centred on the anchor so both the lookback and the lookahead window hold
  // data, matching WEBUNTIS_LOOKBACK_DAYS / WEBUNTIS_LOOKAHEAD_DAYS.
  const firstDay = -Math.floor(p.timetableDays / 2);
  for (let day = firstDay; day < firstDay + p.timetableDays; day += 1) {
    const date = addDays(BASE_DATE, day);
    for (let n = 0; n < p.timetableEntriesPerDay; n += 1) {
      const hour = 8 + (n % 10);
      const subject = pick(random, SUBJECTS);
      entries.push({
        source: MARKER_SOURCE,
        externalKey: `perf-entry-${day}-${n}`,
        startsAt: new Date(date.getTime() + hour * 3_600_000),
        endsAt: new Date(date.getTime() + (hour * 3_600_000 + 5_400_000)),
        date,
        title: subject,
        subjectCode: subject.slice(0, 4).toUpperCase(),
        type: 'regular_teaching',
        status: n % 23 === 0 ? 'cancelled' : 'regular',
        teachers: [{ shortName: `T${n % 40}`, displayName: `Perf Lehrkraft ${n % 40}` }],
        rooms: [{ shortName: `R${100 + (n % 60)}`, longName: null }],
      });
    }
  }
  await insertInBatches('timetable_entries', entries, (chunk) =>
    prisma.timetableEntry.createMany({ data: chunk, skipDuplicates: true }),
  );

  const entryRows = await prisma.timetableEntry.findMany({
    where: { source: MARKER_SOURCE },
    select: { id: true },
    orderBy: { externalKey: 'asc' },
  });

  // A lesson is attended by one or more groups. Assignment is deterministic so
  // the same group id always yields the same week — a fair before/after test
  // needs the same working set, not just the same row count. Distribute the
  // fractional profile average exactly instead of choosing one of two rounded
  // values randomly; expectedRowCounts() and the generated data must agree.
  const links: Array<{ entryId: string; groupId: string }> = [];
  const seen = new Set<string>();
  const targetLinkCount = Math.max(
    entryRows.length,
    Math.round(entryRows.length * p.groupsPerEntry),
  );
  const attendeesPerEntry = Math.floor(targetLinkCount / entryRows.length);
  const entriesWithExtraAttendee = targetLinkCount % entryRows.length;
  for (const [index, entry] of entryRows.entries()) {
    const extrasBefore = Math.floor((index * entriesWithExtraAttendee) / entryRows.length);
    const extrasAfter = Math.floor(((index + 1) * entriesWithExtraAttendee) / entryRows.length);
    const attendees = attendeesPerEntry + extrasAfter - extrasBefore;
    for (let a = 0; a < attendees; a += 1) {
      const group = groupRows[(index * 7 + a * 13) % groupRows.length];
      if (!group) continue;
      const key = `${entry.id}:${group.id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      links.push({ entryId: entry.id, groupId: group.id });
    }
  }
  if (links.length !== targetLinkCount) {
    throw new Error(
      `Timetable link invariant violated: expected ${targetLinkCount}, generated ${links.length}`,
    );
  }
  await insertInBatches('timetable_entry_groups', links, (chunk) =>
    prisma.timetableEntryGroup.createMany({ data: chunk, skipDuplicates: true }),
  );

  await prisma.timetableSyncRun.createMany({
    data: [
      {
        kind: `${SLUG_PREFIX}groups`,
        status: 'success',
        startedAt: new Date(BASE_DATE.getTime() - 3_600_000),
        finishedAt: new Date(BASE_DATE.getTime() - 3_500_000),
      },
      {
        kind: `${SLUG_PREFIX}entries`,
        status: 'success',
        startedAt: new Date(BASE_DATE.getTime() - 1_800_000),
        finishedAt: new Date(BASE_DATE.getTime() - 1_700_000),
        rangeFrom: addDays(BASE_DATE, -7),
        rangeTo: addDays(BASE_DATE, 28),
      },
    ],
  });
}

async function seedPublicCalendars(prisma: PrismaClient, p: DatasetProfile): Promise<void> {
  const random = rng(3003);

  const calendarIds: Array<{ id: string; slug: string }> = [];
  for (let i = 0; i < p.publicCalendars; i += 1) {
    const created = await prisma.publicCalendar.create({
      data: {
        slug: `${SLUG_PREFIX}calendar-${String(i).padStart(2, '0')}`,
        // Synthetic and clearly not a real calendar id.
        googleCalendarId: `perf-baseline-${i}@group.calendar.example.invalid`,
        nameDe: `Perf-Kalender ${i}`,
        nameEn: i % 3 === 0 ? null : `Perf Calendar ${i}`,
        colorHex: '#3366CC',
        sortOrder: i * 10,
        // Active on purpose: the public calendar routes serve active calendars
        // only, so inactive rows would benchmark an empty answer. These rows
        // only ever exist in the guarded performance database, where no worker
        // runs that could try to sync the `.invalid` ids.
        isActive: true,
        defaultSubscribed: i < 3,
        // Both on, so an event carries its description and location and the
        // measured response stays the largest one the route can produce.
        includeEventDescription: true,
        includeEventLocation: true,
        operationalStatus: 'ready',
        lastCatalogSyncAt: new Date(BASE_DATE.getTime() - 600_000),
        lastSuccessfulSyncAt: new Date(BASE_DATE.getTime() - 600_000),
      },
      select: { id: true, slug: true },
    });
    calendarIds.push(created);
  }

  const events: Array<{
    calendarId: string;
    occurrenceKey: string;
    uid: string;
    title: string;
    description: string;
    location: string;
    startsAt: Date;
    endsAt: Date;
    allDay: boolean;
    status: string;
  }> = [];
  const firstDay = -30; // PUBLIC_CALENDAR_LOOKBACK_DAYS
  for (const calendar of calendarIds) {
    for (let day = firstDay; day < firstDay + p.publicCalendarDays; day += 1) {
      for (let n = 0; n < p.eventsPerCalendarDay; n += 1) {
        const date = addDays(BASE_DATE, day);
        const hour = 9 + ((n * 3) % 9);
        events.push({
          calendarId: calendar.id,
          occurrenceKey: `perf-${day}-${n}`,
          uid: `perf-${calendar.slug}-${day}-${n}`,
          title: `Perf-Termin ${day}/${n}`,
          description: 'Synthetischer Termin für die Performance-Baseline.',
          location: `Raum ${100 + Math.floor(random() * 60)}`,
          startsAt: new Date(date.getTime() + hour * 3_600_000),
          endsAt: new Date(date.getTime() + (hour + 2) * 3_600_000),
          allDay: n % 9 === 0,
          status: n % 17 === 0 ? 'cancelled' : 'confirmed',
        });
      }
    }
  }
  await insertInBatches('public_calendar_events', events, (chunk) =>
    prisma.publicCalendarEvent.createMany({ data: chunk, skipDuplicates: true }),
  );
}

async function main(): Promise<void> {
  // Never the ordinary DATABASE_URL on its own: only a dedicated, name-checked
  // performance database (see perf-database-url.ts).
  const databaseUrl = requirePerfDatabaseUrl();

  const args = process.argv.slice(2);
  const profileArg = (args[args.indexOf('--profile') + 1] ?? 'realistic') as ProfileName;
  const profile = PROFILES[profileArg];
  if (!profile) {
    throw new Error(`Unknown profile "${profileArg}". Use realistic or stress.`);
  }

  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
  const started = Date.now();
  process.stdout.write(`Seeding profile "${profile.name}"\n`);
  process.stdout.write(`Expected rows: ${JSON.stringify(expectedRowCounts(profile))}\n`);

  try {
    if (args.includes('--reset')) {
      await reset(prisma);
    }
    await seedCanteen(prisma, profile);
    await seedTimetable(prisma, profile);
    await seedPublicCalendars(prisma, profile);
    // Planner statistics decide which index the hot reads use. Measuring
    // before ANALYZE would benchmark stale statistics, not the query.
    await prisma.$executeRawUnsafe('ANALYZE');
    process.stdout.write(`Done in ${Math.round((Date.now() - started) / 1000)} s\n`);
  } finally {
    await prisma.$disconnect();
  }
}

void main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
