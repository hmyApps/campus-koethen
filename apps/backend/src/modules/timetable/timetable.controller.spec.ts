import { Env } from '../../config/env.schema';
import { TimetableController } from './timetable.controller';
import { TimetableService } from './timetable.service';

describe('TimetableController groups metadata', () => {
  afterEach(() => jest.useRealTimers());

  it('advertises the configured timetable horizon to the app', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-09-24T12:00:00.000Z'));
    const service = {
      listGroups: jest.fn().mockResolvedValue({
        data: [],
        pagination: { page: 1, pageSize: 20, total: 0, totalPages: 0 },
        lastSyncAt: null,
        stale: false,
      }),
      featureEnabled: true,
    } as unknown as TimetableService;
    const controller = new TimetableController(service, {
      WEBUNTIS_LOOKAHEAD_DAYS: 28,
    } as Env);

    const response = await controller.groups({ requestedLocale: 'de', resolvedLocale: 'de' }, {});

    expect(response.meta.from).toBe('2026-09-24');
    expect(response.meta.to).toBe('2026-10-22');
  });

  it('advertises a full semester when configured for 210 days', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-09-24T12:00:00.000Z'));
    const service = {
      listGroups: jest.fn().mockResolvedValue({
        data: [],
        pagination: { page: 1, pageSize: 20, total: 0, totalPages: 0 },
        lastSyncAt: null,
        stale: false,
      }),
      featureEnabled: true,
    } as unknown as TimetableService;
    const controller = new TimetableController(service, {
      WEBUNTIS_LOOKAHEAD_DAYS: 210,
    } as Env);

    const response = await controller.groups({ requestedLocale: 'de', resolvedLocale: 'de' }, {});

    expect(response.meta.to).toBe('2027-04-22');
  });

  it('starts the advertised horizon on the Berlin calendar day, not the UTC day', async () => {
    // 00:30 CEST on 24 September is still 23 September in UTC.
    jest.useFakeTimers().setSystemTime(new Date('2026-09-23T22:30:00.000Z'));
    const service = {
      listGroups: jest.fn().mockResolvedValue({
        data: [],
        pagination: { page: 1, pageSize: 20, total: 0, totalPages: 0 },
        lastSyncAt: null,
        stale: false,
      }),
      getGroup: jest.fn().mockResolvedValue({
        data: {
          id: '43a7302c-19ce-4fd7-a06e-003599fd75d0',
          shortName: 'DEMO',
          longName: 'Demo group',
          department: null,
        },
        lastSyncAt: null,
        stale: false,
      }),
      featureEnabled: true,
    } as unknown as TimetableService;
    const controller = new TimetableController(service, {
      WEBUNTIS_LOOKAHEAD_DAYS: 28,
    } as Env);
    const locale = { requestedLocale: 'de', resolvedLocale: 'de' } as const;

    const catalogue = await controller.groups(locale, {});
    const single = await controller.group(locale, {
      groupId: '43a7302c-19ce-4fd7-a06e-003599fd75d0',
    });

    for (const response of [catalogue, single]) {
      expect(response.meta.from).toBe('2026-09-24');
      expect(response.meta.to).toBe('2026-10-22');
    }
  });

  it('validates pagination and exposes the resolved page metadata', async () => {
    const listGroups = jest.fn().mockResolvedValue({
      data: [],
      pagination: { page: 11, pageSize: 50, total: 503, totalPages: 11 },
      lastSyncAt: null,
      stale: false,
    });
    const service = { listGroups, featureEnabled: true } as unknown as TimetableService;
    const controller = new TimetableController(service, {
      WEBUNTIS_LOOKAHEAD_DAYS: 210,
    } as Env);

    const response = await controller.groups(
      { requestedLocale: 'de', resolvedLocale: 'de' },
      { page: '11', pageSize: '50', query: ' informatik ' },
    );

    expect(listGroups).toHaveBeenCalledWith(
      { requestedLocale: 'de', resolvedLocale: 'de' },
      { page: 11, pageSize: 50, query: 'informatik' },
    );
    expect(response.meta.pagination).toEqual({
      page: 11,
      pageSize: 50,
      total: 503,
      totalPages: 11,
    });
  });
});
