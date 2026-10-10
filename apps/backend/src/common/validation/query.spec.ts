import { z } from 'zod';

import { ApiError } from '../errors/api-error';
import {
  dateRangeSchema,
  isoDate,
  MAX_FILTER_VALUES,
  MAX_FILTER_VALUE_LENGTH,
  parseChannels,
  parseIsoDayUtc,
  parseTags,
  refineDateRange,
} from './query';

/**
 * The list filters go straight into a Strapi `$in`, so their size is the size
 * of the upstream request. AGENTS.md §7 asks every query parameter to be
 * bounded; the timetable and public-calendar endpoints already are, `/v1/posts`
 * was not.
 */
describe('list filter parsing', () => {
  /** Both parsers, reduced to what the shared rules can be stated against. */
  const parsers: Array<{
    name: 'channels' | 'tags';
    parse: (raw: unknown) => { values: string[]; present: boolean };
  }> = [
    {
      name: 'channels',
      parse: (raw) => {
        const result = parseChannels(raw, 'de');
        return { values: result.channels, present: result.channelsParamPresent };
      },
    },
    {
      name: 'tags',
      parse: (raw) => {
        const result = parseTags(raw, 'de');
        return { values: result.tags, present: result.tagsParamPresent };
      },
    },
  ];

  const listOf = (count: number, value?: string): string =>
    Array.from({ length: count }, (_, index) => value ?? `s${index}`).join(',');

  for (const { name, parse } of parsers) {
    describe(name, () => {
      it('keeps the absent / present-but-empty distinction', () => {
        expect(parse(undefined)).toEqual({ values: [], present: false });
        expect(parse(null)).toEqual({ values: [], present: false });
        expect(parse('')).toEqual({ values: [], present: true });
      });

      it('splits, trims and drops blanks', () => {
        expect(parse(' a , b ,,c ')).toEqual({
          values: ['a', 'b', 'c'],
          present: true,
        });
      });

      it(`accepts exactly ${MAX_FILTER_VALUES} values`, () => {
        expect(parse(listOf(MAX_FILTER_VALUES)).values).toHaveLength(MAX_FILTER_VALUES);
      });

      it('refuses one value too many instead of asking Strapi', () => {
        expect(() => parse(listOf(MAX_FILTER_VALUES + 1))).toThrow(ApiError);
      });

      it('counts duplicates too — a repeated slug still travels upstream', () => {
        expect(() => parse(listOf(MAX_FILTER_VALUES + 1, 'same'))).toThrow(ApiError);
      });

      it('accepts a value of the maximum length and refuses a longer one', () => {
        expect(parse('x'.repeat(MAX_FILTER_VALUE_LENGTH)).values).toHaveLength(1);
        expect(() => parse('x'.repeat(MAX_FILTER_VALUE_LENGTH + 1))).toThrow(ApiError);
      });

      it('answers a refusal as a 400 VALIDATION_FAILED naming the parameter', () => {
        let caught: unknown;
        try {
          parse(listOf(MAX_FILTER_VALUES + 1));
        } catch (error) {
          caught = error;
        }
        expect(caught).toBeInstanceOf(ApiError);
        const apiError = caught as ApiError;
        expect(apiError.code).toBe('VALIDATION_FAILED');
        expect(apiError.getStatus()).toBe(400);
        expect(apiError.details?.join(' ')).toContain(name);
      });
    });
  }
});

/**
 * A date that does not exist must be REFUSED, not silently moved.
 *
 * `Date.parse` rolls a day overflow forward — `2026-02-30` becomes 2026-03-02 —
 * so the old `!Number.isNaN(Date.parse(…))` check only ever caught a month
 * outside 01–12. The damage was not just a wrong window: the ordering check
 * compared the STRINGS while the span check compared the parsed timestamps, so
 * an overflowed `from` passed as ordered and then arrived inverted, and
 * `/v1/canteens/{slug}/menu` answered 200 with zero days — the exact state its
 * "every requested day is present" promise exists to rule out.
 */
describe('date range parsing', () => {
  const parse = (query: Record<string, string>) => dateRangeSchema.safeParse(query);

  it('accepts a real day', () => {
    expect(parse({ from: '2026-03-01', to: '2026-03-02' }).success).toBe(true);
  });

  it.each([
    ['a day past the end of a short month', '2026-02-30'],
    ['29 February in a non-leap year', '2025-02-29'],
    ['a 31st in a 30-day month', '2026-04-31'],
    ['day 00', '2026-03-00'],
    ['day 32', '2026-03-32'],
    ['month 13', '2026-13-01'],
  ])('refuses %s (%s) instead of shifting it', (_label, day) => {
    const result = parse({ from: day, to: '2026-03-05' });
    expect(result.success).toBe(false);
    expect(JSON.stringify(result.error?.issues)).toContain('must be a valid date');
  });

  it('accepts 29 February in a leap year', () => {
    expect(parse({ from: '2024-02-29', to: '2024-03-01' }).success).toBe(true);
  });

  it('never reports an impossible day as an ordering or span problem', () => {
    // Both of these used to answer with a message that named the wrong cause.
    for (const query of [
      { from: '2026-04-31', to: '2026-03-01' },
      { from: '2025-02-29', to: '2026-03-01' },
    ]) {
      const issues = JSON.stringify(parse(query).error?.issues);
      expect(issues).toContain('must be a valid date');
      expect(issues).not.toContain('must not be earlier');
      expect(issues).not.toContain('must not exceed');
    }
  });

  it('still refuses a genuinely inverted range', () => {
    const issues = JSON.stringify(parse({ from: '2026-03-05', to: '2026-03-01' }).error?.issues);
    expect(issues).toContain('must not be earlier');
  });

  it('still refuses a range wider than the limit', () => {
    const issues = JSON.stringify(parse({ from: '2026-03-01', to: '2026-05-01' }).error?.issues);
    expect(issues).toContain('must not exceed');
  });

  it('accepts a range of exactly the maximum width', () => {
    // 2026-03-01 + 31 days
    expect(parse({ from: '2026-03-01', to: '2026-04-01' }).success).toBe(true);
  });

  /**
   * "Today" is the campus day, not the UTC day. Between midnight and 01:00
   * (winter) or 02:00 (summer) Berlin time the UTC date is still yesterday, so
   * a default taken from `toISOString()` started the menu one day early.
   */
  describe('default window', () => {
    afterEach(() => jest.useRealTimers());

    it.each([
      ['summer time, 00:30 CEST', '2026-07-19T22:30:00.000Z', '2026-07-20', '2026-08-03'],
      ['winter time, 00:30 CET', '2026-01-14T23:30:00.000Z', '2026-01-15', '2026-01-29'],
      ['the middle of a Berlin day', '2026-07-20T12:00:00.000Z', '2026-07-20', '2026-08-03'],
    ])('starts on the Berlin calendar day (%s)', (_label, now, from, to) => {
      jest.useFakeTimers().setSystemTime(new Date(now));

      const result = parse({});

      expect(result.success).toBe(true);
      expect(result.data).toEqual({ from, to });
    });
  });

  describe('parseIsoDayUtc', () => {
    it('returns midnight UTC for a real day', () => {
      expect(parseIsoDayUtc('2026-03-01')).toBe(Date.UTC(2026, 2, 1));
    });

    it('returns NaN for a day the calendar does not have', () => {
      expect(parseIsoDayUtc('2026-02-30')).toBeNaN();
      expect(parseIsoDayUtc('not-a-date')).toBeNaN();
    });
  });
});

/**
 * The timetable route wraps a PLAIN object, not the transforming one
 * `dateRangeSchema` builds on.
 *
 * That difference mattered. A transform aborts once an inner field fails, so
 * `dateRangeSchema` never reached its refinements with a broken date and the
 * canteen and calendar routes answered cleanly. A plain object has no such
 * gate: both refinements still ran, `NaN >= NaN` and `NaN <= maxDays` are both
 * false, and one impossible day produced two further complaints about an order
 * and a span that were never wrong. A caller reading `details` was told three
 * things and only one of them was true.
 */
describe('date range refinement on a plain object (timetable shape)', () => {
  const MAX_RANGE_DAYS = 42;
  const schema = refineDateRange(
    z.object({ groupId: z.uuid('must be a Campus group id'), from: isoDate, to: isoDate }),
    MAX_RANGE_DAYS,
  );
  const groupId = '00000000-0000-4000-8000-000000000000';
  const messages = (query: Record<string, string>): string[] =>
    (schema.safeParse(query).error?.issues ?? []).map((issue) => issue.message);

  it('accepts a real, ordered, bounded range', () => {
    expect(schema.safeParse({ groupId, from: '2026-08-25', to: '2026-08-26' }).success).toBe(true);
  });

  it.each([
    ['from', { groupId, from: '2026-02-30', to: '2026-03-01' }],
    ['to', { groupId, from: '2026-08-25', to: '2026-02-30' }],
  ])('reports an impossible %s exactly once, with the true cause', (_field, query) => {
    const found = messages(query);
    expect(found).toEqual(['must be a valid date']);
  });

  it('still refuses a genuinely inverted range', () => {
    expect(messages({ groupId, from: '2026-08-26', to: '2026-08-25' })).toContain(
      '`to` must not be earlier than `from`',
    );
  });

  it('still refuses a range wider than the limit', () => {
    expect(messages({ groupId, from: '2026-01-01', to: '2026-06-01' })).toContain(
      `the range must not exceed ${MAX_RANGE_DAYS} days`,
    );
  });

  it('does not swallow an unrelated field error', () => {
    expect(messages({ groupId: 'nope', from: '2026-08-25', to: '2026-08-26' })).toContain(
      'must be a Campus group id',
    );
  });
});
