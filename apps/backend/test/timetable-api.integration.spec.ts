import { INestApplication, VersioningType } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AllExceptionsFilter } from '../src/common/filters/all-exceptions.filter';
import { PrismaClient } from '../src/generated/prisma/client';
import { createTestPrisma, resetDatabase } from './helpers/database';

// Real PostgreSQL setup and cleanup can exceed Jest's 5s default on shared CI.
jest.setTimeout(60_000);

/**
 * API-level tests over real HTTP against a real database.
 *
 * WEBUNTIS_ENABLED is forced on here so the read path is exercised; no upstream
 * call happens either way, because the API only ever reads our own tables.
 */
describe('/v1/timetable (integration)', () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let groupId: string;

  beforeAll(async () => {
    process.env['WEBUNTIS_ENABLED'] = 'true';

    prisma = createTestPrisma();
    await prisma.$connect();

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication({ logger: false });
    app.enableVersioning({ type: VersioningType.URI, prefix: 'v' });
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
    await prisma?.$disconnect();
  });

  beforeEach(async () => {
    await resetDatabase(prisma);

    const group = await prisma.timetableGroup.create({
      data: {
        externalId: '14622',
        shortName: 'AIN2 - BT',
        longName: 'AIN2-Angewandte Informatik Vertiefung: Biotechnologie',
        department: 'FB5',
      },
    });
    groupId = group.id;

    await prisma.timetableGroup.create({
      data: { externalId: '15027', shortName: 'AR2Ü1', longName: '2. AR Gr. 1', department: 'FB1' },
    });

    const entry = await prisma.timetableEntry.create({
      data: {
        externalKey: '2686630',
        startsAt: new Date('2026-07-20T08:00:00.000Z'),
        endsAt: new Date('2026-07-20T09:30:00.000Z'),
        date: new Date('2026-07-20T00:00:00.000Z'),
        title: 'Englisch als Fremdsprache',
        subjectCode: 'Englisch als Fremdsp',
        type: 'regular_teaching',
        status: 'cancelled',
        sourceStatus: 'CANCELLED',
        teachers: [{ shortName: 'D-Demo01', displayName: 'Demo Demoperson01' }],
        rooms: [{ shortName: 'D-04/201', longName: 'Seminarraum VM/GIN' }],
      },
    });
    await prisma.timetableEntryGroup.create({ data: { entryId: entry.id, groupId } });

    await prisma.timetableSyncRun.create({
      data: {
        kind: 'entries',
        status: 'success',
        finishedAt: new Date(),
        rangeFrom: new Date('2026-07-20T00:00:00.000Z'),
        rangeTo: new Date('2026-08-02T00:00:00.000Z'),
      },
    });
    await prisma.timetableSyncRun.create({
      data: { kind: 'groups', status: 'success', finishedAt: new Date() },
    });
  });

  describe('GET /v1/timetable/groups', () => {
    it('lists the catalogue', async () => {
      const res = await request(app.getHttpServer()).get('/v1/timetable/groups').expect(200);
      expect(res.body.data).toHaveLength(2);
      expect(res.body.data[0].shortName).toBe('AIN2 - BT');
      expect(res.body.meta.pagination).toEqual({
        page: 1,
        pageSize: 20,
        total: 2,
        totalPages: 1,
      });
    });

    it('reaches every row beyond the former 500-group cap', async () => {
      await prisma.timetableGroup.createMany({
        data: Array.from({ length: 501 }, (_, index) => ({
          externalId: `bulk-${index.toString().padStart(3, '0')}`,
          shortName: `ZZ-${index.toString().padStart(3, '0')}`,
          longName: `Synthetic catalogue group ${index}`,
          department: 'DEMO',
        })),
      });

      const res = await request(app.getHttpServer())
        .get('/v1/timetable/groups?page=11&pageSize=50')
        .expect(200);

      expect(res.body.meta.pagination).toEqual({
        page: 11,
        pageSize: 50,
        total: 503,
        totalPages: 11,
      });
      expect(res.body.data).toHaveLength(3);
    });

    it('rejects unbounded page sizes', async () => {
      await request(app.getHttpServer()).get('/v1/timetable/groups?pageSize=51').expect(400);
    });

    it('searches short name, long name and department', async () => {
      const byShort = await request(app.getHttpServer()).get('/v1/timetable/groups?query=AR2');
      expect(byShort.body.data).toHaveLength(1);

      const byLong = await request(app.getHttpServer()).get('/v1/timetable/groups?query=biotech');
      expect(byLong.body.data).toHaveLength(1);

      const byDept = await request(app.getHttpServer()).get('/v1/timetable/groups?query=fb5');
      expect(byDept.body.data).toHaveLength(1);
    });

    it('filters by department exactly', async () => {
      const res = await request(app.getHttpServer()).get('/v1/timetable/groups?department=FB1');
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].department).toBe('FB1');
    });

    it('never exposes the upstream identifier', async () => {
      const res = await request(app.getHttpServer()).get('/v1/timetable/groups').expect(200);
      const body = JSON.stringify(res.body);
      expect(body).not.toContain('externalId');
      expect(body).not.toContain('14622');
      expect(body).not.toContain('15027');
      expect(body).not.toContain('webuntis');
    });

    it('resolves a saved group by Campus UUID without exposing source ids', async () => {
      const res = await request(app.getHttpServer())
        .get(`/v1/timetable/groups/${groupId}`)
        .expect(200);

      expect(res.body.data).toMatchObject({ id: groupId, shortName: 'AIN2 - BT' });
      expect(JSON.stringify(res.body)).not.toContain('14622');
      expect(res.body.meta.from).toBeTruthy();
      expect(res.body.meta.to).toBeTruthy();
    });
  });

  describe('GET /v1/timetable/entries', () => {
    const url = (params: string) => `/v1/timetable/entries?${params}`;

    it('returns every day of the range, including free ones', async () => {
      const res = await request(app.getHttpServer())
        .get(url(`groupId=${groupId}&from=2026-07-20&to=2026-07-24`))
        .expect(200);

      expect(res.body.data.days).toHaveLength(5);
      expect(res.body.data.days[0].entries).toHaveLength(1);
      // A free day is an empty array, NOT a missing day.
      expect(res.body.data.days[1].entries).toEqual([]);
    });

    it('serves normalised status and untranslated source text', async () => {
      const res = await request(app.getHttpServer())
        .get(url(`groupId=${groupId}&from=2026-07-20&to=2026-07-20`))
        .expect(200);

      const entry = res.body.data.days[0].entries[0];
      expect(entry.status).toBe('cancelled');
      expect(entry.title).toBe('Englisch als Fremdsprache');
      expect(entry.timezone).toBe('Europe/Berlin');
      expect(entry.teachers[0].shortName).toBe('D-Demo01');
      expect(entry.rooms[0].longName).toBe('Seminarraum VM/GIN');
    });

    it('reports freshness metadata', async () => {
      const res = await request(app.getHttpServer())
        .get(url(`groupId=${groupId}&from=2026-07-20&to=2026-07-24`))
        .expect(200);

      expect(res.body.meta.dataState).toBe('ready');
      expect(res.body.meta.featureEnabled).toBe(true);
      expect(res.body.meta.timezone).toBe('Europe/Berlin');
      expect(res.body.meta.from).toBe('2026-07-20');
      expect(res.body.meta.lastSuccessfulSyncAt).toBeTruthy();
      expect(res.body.meta.dataStale).toBe(false);
    });

    it('flags English as a fallback, because source text is never translated', async () => {
      const res = await request(app.getHttpServer())
        .get(url(`groupId=${groupId}&from=2026-07-20&to=2026-07-20&locale=en`))
        .expect(200);

      expect(res.body.meta.resolvedLocale).toBe('en');
      expect(res.body.meta.translationFallback).toBe(true);
      expect(res.body.data.days[0].entries[0].title).toBe('Englisch als Fremdsprache');
    });

    it('rejects an invalid date', async () => {
      await request(app.getHttpServer())
        .get(url(`groupId=${groupId}&from=20-07-2026&to=2026-07-24`))
        .expect(400);
    });

    it('rejects a reversed range', async () => {
      await request(app.getHttpServer())
        .get(url(`groupId=${groupId}&from=2026-07-24&to=2026-07-20`))
        .expect(400);
    });

    it('rejects a range longer than 42 days', async () => {
      await request(app.getHttpServer())
        .get(url(`groupId=${groupId}&from=2026-01-01&to=2026-12-31`))
        .expect(400);
    });

    it('rejects a non-UUID group id, so upstream ids cannot be passed in', async () => {
      await request(app.getHttpServer())
        .get(url('groupId=14622&from=2026-07-20&to=2026-07-24'))
        .expect(400);
    });

    it('returns 404 for an unknown group', async () => {
      await request(app.getHttpServer())
        .get(url('groupId=00000000-0000-4000-8000-000000000000&from=2026-07-20&to=2026-07-24'))
        .expect(404);
    });
  });

  describe('GET /v1/timetable/status', () => {
    it('reports a thin public state without upstream detail', async () => {
      const res = await request(app.getHttpServer()).get('/v1/timetable/status').expect(200);

      expect(res.body.data.featureEnabled).toBe(true);
      expect(res.body.data.groupCount).toBe(2);
      expect(res.body.data.lastEntrySyncAt).toBeTruthy();
      expect(res.body.data.coveredFrom).toBe('2026-07-20');

      const body = JSON.stringify(res.body);
      expect(body).not.toContain('webuntis');
      expect(body).not.toContain('anonymous-school');
      expect(body).not.toContain('hsa');
    });

    /** One entry run; `hoursAgo` decides how old it is. */
    async function recordEntryRun(
      status: string,
      hoursAgo: number,
      window: { from: string; to: string },
      finished = true,
    ): Promise<void> {
      const at = new Date(Date.now() - hoursAgo * 3_600_000);
      await prisma.timetableSyncRun.create({
        data: {
          kind: 'entries',
          status,
          startedAt: at,
          finishedAt: finished ? at : null,
          rangeFrom: new Date(`${window.from}T00:00:00.000Z`),
          rangeTo: new Date(`${window.to}T00:00:00.000Z`),
        },
      });
    }

    async function status() {
      const res = await request(app.getHttpServer()).get('/v1/timetable/status').expect(200);
      return res.body.data as {
        lastEntrySyncAt: string | null;
        coveredFrom: string | null;
        coveredTo: string | null;
      };
    }

    it('reports the window of the newest successful run', async () => {
      await prisma.timetableSyncRun.deleteMany({ where: { kind: 'entries' } });
      // Written last, but older: insertion order must not decide the answer.
      await recordEntryRun('success', 1, { from: '2026-08-17', to: '2026-08-31' });
      await recordEntryRun('success', 100, { from: '2026-01-05', to: '2026-01-19' });

      expect(await status()).toMatchObject({
        coveredFrom: '2026-08-17',
        coveredTo: '2026-08-31',
      });
    });

    it('keeps the confirmed window while the next run is still in flight', async () => {
      // The worker records the window it is attempting before it knows whether
      // the attempt works out. Until that run finishes successfully, the status
      // endpoint must keep reporting the window that was actually confirmed —
      // otherwise every hourly sync would briefly advertise coverage the data
      // does not have.
      const confirmed = await status();
      await recordEntryRun('running', 0, { from: '2026-09-01', to: '2026-09-14' }, false);

      expect(await status()).toMatchObject({
        lastEntrySyncAt: confirmed.lastEntrySyncAt,
        coveredFrom: confirmed.coveredFrom,
        coveredTo: confirmed.coveredTo,
      });
    });

    it('ignores runs that failed or came back empty', async () => {
      const confirmed = await status();
      await recordEntryRun('failed', 0, { from: '2026-09-01', to: '2026-09-14' });
      await recordEntryRun('empty', 0, { from: '2026-09-15', to: '2026-09-28' });

      expect(await status()).toMatchObject({
        lastEntrySyncAt: confirmed.lastEntrySyncAt,
        coveredFrom: confirmed.coveredFrom,
        coveredTo: confirmed.coveredTo,
      });
    });
  });
});
