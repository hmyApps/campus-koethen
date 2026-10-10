import { Env } from '../../config/env.schema';
import { PostsController } from './posts.controller';
import { PostsService } from './posts.service';

/**
 * Default date window of the event-post route.
 *
 * "Today" is the Europe/Berlin calendar day: just after local midnight the UTC
 * day still names yesterday, and a window taken from it started a day early.
 */
describe('PostsController event range', () => {
  const locale = { requestedLocale: 'de', resolvedLocale: 'de' } as const;

  function harness() {
    const getEvents = jest.fn().mockResolvedValue({
      data: [],
      meta: { page: 1, pageSize: 20, total: 0 },
      translationFallback: false,
    });
    const controller = new PostsController(
      { getEvents } as unknown as PostsService,
      {
        PUBLIC_CALENDAR_API_MAX_RANGE_DAYS: 400,
      } as Env,
    );
    return { controller, getEvents };
  }

  afterEach(() => {
    jest.useRealTimers();
  });

  it('starts the default window on the Berlin day just after local midnight', async () => {
    const { controller, getEvents } = harness();
    // 00:30 CEST on 21 July is still 20 July in UTC.
    jest.useFakeTimers().setSystemTime(new Date('2026-07-20T22:30:00.000Z'));

    await controller.events(locale, {});

    expect(getEvents).toHaveBeenCalledWith(
      locale,
      expect.objectContaining({ from: '2026-07-21', to: '2027-08-25' }),
    );
  });

  it('still honours an explicit range', async () => {
    const { controller, getEvents } = harness();

    await controller.events(locale, { from: '2026-05-01', to: '2026-05-31' });

    expect(getEvents).toHaveBeenCalledWith(
      locale,
      expect.objectContaining({ from: '2026-05-01', to: '2026-05-31' }),
    );
  });
});
