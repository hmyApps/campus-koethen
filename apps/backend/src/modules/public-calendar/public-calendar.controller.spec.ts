import { ApiError } from '../../common/errors/api-error';
import { Env } from '../../config/env.schema';
import { PublicCalendarController } from './public-calendar.controller';
import { PublicCalendarService } from './public-calendar.service';

/**
 * Query contract of the calendar event routes.
 *
 * The date-range schema is built once per controller instance rather than per
 * request. What must survive that: the DEFAULT window is relative to "now", so
 * it has to move with the clock even though the schema itself does not.
 */
describe('PublicCalendarController date range', () => {
  const MAX_RANGE_DAYS = 400;

  function harness() {
    const getAggregatedEvents = jest.fn().mockResolvedValue({ events: [], truncated: false });
    const service = { getAggregatedEvents } as unknown as PublicCalendarService;
    const controller = new PublicCalendarController(service, {
      PUBLIC_CALENDAR_API_MAX_RANGE_DAYS: MAX_RANGE_DAYS,
      PUBLIC_CALENDAR_API_MAX_CALENDARS: 50,
      PUBLIC_CALENDAR_ENABLED: true,
    } as Env);
    return { controller, getAggregatedEvents };
  }

  const locale = { requestedLocale: 'de', resolvedLocale: 'de' } as const;

  afterEach(() => {
    jest.useRealTimers();
  });

  it('resolves the default window against the clock, not against build time', async () => {
    const { controller, getAggregatedEvents } = harness();

    jest.useFakeTimers().setSystemTime(new Date('2026-03-01T09:00:00.000Z'));
    await controller.aggregated(locale, { calendar: 'beispielkalender-a' });
    const early = getAggregatedEvents.mock.calls[0]! as [string[], Date, Date];

    // Same controller instance, months later.
    jest.setSystemTime(new Date('2026-09-01T09:00:00.000Z'));
    await controller.aggregated(locale, { calendar: 'beispielkalender-a' });
    const late = getAggregatedEvents.mock.calls[1]! as [string[], Date, Date];

    expect(early[1].toISOString()).toBe('2026-03-01T00:00:00.000Z');
    expect(late[1].toISOString()).toBe('2026-09-01T00:00:00.000Z');
    // The lookahead end moves with it, by exactly the configured window.
    expect(early[2].toISOString()).toBe('2027-04-05T23:59:59.999Z');
    expect(late[2].toISOString()).toBe('2027-10-06T23:59:59.999Z');
  });

  it('advertises the full imported horizon and request size for the app list', async () => {
    const service = {
      listCalendars: jest.fn().mockResolvedValue({ data: [], translationFallback: false }),
    } as unknown as PublicCalendarService;
    const controller = new PublicCalendarController(service, {
      PUBLIC_CALENDAR_API_MAX_RANGE_DAYS: 120,
      PUBLIC_CALENDAR_LOOKAHEAD_DAYS: 180,
      PUBLIC_CALENDAR_ENABLED: true,
    } as Env);
    jest.useFakeTimers().setSystemTime(new Date('2026-09-24T12:00:00.000Z'));

    const response = await controller.list(locale);

    expect(response.meta.from).toBe('2026-09-24');
    expect(response.meta.to).toBe('2027-03-23');
    expect(response.meta.maxRangeDays).toBe(120);
  });

  it('starts the default window on the Berlin day just after local midnight', async () => {
    const { controller, getAggregatedEvents } = harness();
    // 00:30 CEST on 21 July is still 20 July in UTC.
    jest.useFakeTimers().setSystemTime(new Date('2026-07-20T22:30:00.000Z'));

    await controller.aggregated(locale, { calendar: 'beispielkalender-a' });

    const [, from] = getAggregatedEvents.mock.calls[0]! as [string[], Date, Date];
    expect(from.toISOString()).toBe('2026-07-21T00:00:00.000Z');
  });

  it('advertises the Berlin day as the start of the app list horizon', async () => {
    const service = {
      listCalendars: jest.fn().mockResolvedValue({ data: [], translationFallback: false }),
    } as unknown as PublicCalendarService;
    const controller = new PublicCalendarController(service, {
      PUBLIC_CALENDAR_API_MAX_RANGE_DAYS: 120,
      PUBLIC_CALENDAR_LOOKAHEAD_DAYS: 180,
      PUBLIC_CALENDAR_ENABLED: true,
    } as Env);
    jest.useFakeTimers().setSystemTime(new Date('2026-07-20T22:30:00.000Z'));

    const response = await controller.list(locale);

    expect(response.meta.from).toBe('2026-07-21');
    expect(response.meta.to).toBe('2027-01-17');
  });

  it('still honours an explicit range', async () => {
    const { controller, getAggregatedEvents } = harness();

    await controller.aggregated(locale, {
      calendar: 'beispielkalender-a',
      from: '2026-05-01',
      to: '2026-05-31',
    });

    const [, from, to] = getAggregatedEvents.mock.calls[0]! as [string[], Date, Date];
    expect(from.toISOString()).toBe('2026-05-01T00:00:00.000Z');
    expect(to.toISOString()).toBe('2026-05-31T23:59:59.999Z');
  });

  it('still rejects a malformed date, an inverted range and an over-long range', async () => {
    const { controller } = harness();

    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '01.05.2026' }),
    ).rejects.toBeInstanceOf(ApiError);
    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '2026-05-31', to: '2026-05-01' }),
    ).rejects.toBeInstanceOf(ApiError);
    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '2026-01-01', to: '2027-12-31' }),
    ).rejects.toBeInstanceOf(ApiError);
  });

  it('refuses a day the calendar does not have instead of shifting the window', async () => {
    const { controller, getAggregatedEvents } = harness();

    // `Date.parse('2026-02-30…')` rolls forward to 2026-03-02, so this used to
    // pass validation and reach the service as from=03-02 > to=03-01 — an
    // inverted window answered with 200 and `meta.from > meta.to`.
    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '2026-02-30', to: '2026-03-01' }),
    ).rejects.toBeInstanceOf(ApiError);
    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '2026-03-01', to: '2025-02-29' }),
    ).rejects.toBeInstanceOf(ApiError);
    expect(getAggregatedEvents).not.toHaveBeenCalled();

    // A leap day that does exist stays acceptable.
    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '2024-02-29', to: '2024-03-01' }),
    ).resolves.toBeDefined();
  });

  it('validates the same way on every request, not just the first', async () => {
    // A schema that is built once is also reused once — a stale transform or a
    // consumed refinement would only show up on the second call.
    const { controller } = harness();

    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '2026-05-31', to: '2026-05-01' }),
    ).rejects.toBeInstanceOf(ApiError);
    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '2026-05-31', to: '2026-05-01' }),
    ).rejects.toBeInstanceOf(ApiError);
    await expect(
      controller.aggregated(locale, { calendar: 'a', from: '2026-05-01', to: '2026-05-31' }),
    ).resolves.toBeDefined();
  });
});
