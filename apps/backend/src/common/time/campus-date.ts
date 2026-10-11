/**
 * Calendar days as the campus lives them.
 *
 * "Today" on a campus in Köthen is the Europe/Berlin calendar day. The UTC day
 * that `new Date().toISOString().slice(0, 10)` answers lags it by one or two
 * hours, so between local midnight and 01:00 (CET) or 02:00 (CEST) a default
 * window taken from it started yesterday. Every default "today" goes through
 * here instead.
 */

export const CAMPUS_TIME_ZONE = 'Europe/Berlin';

const DAY_MS = 86_400_000;

// `en-CA` orders the parts as year-month-day; the parts are still read by
// type, so the result does not depend on the locale's separator.
const campusDayFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: CAMPUS_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/** The Europe/Berlin calendar day of an instant, as `YYYY-MM-DD`. */
export function campusToday(now: Date = new Date()): string {
  let year = '';
  let month = '';
  let day = '';
  for (const part of campusDayFormatter.formatToParts(now)) {
    if (part.type === 'year') year = part.value;
    else if (part.type === 'month') month = part.value;
    else if (part.type === 'day') day = part.value;
  }
  return `${year}-${month}-${day}`;
}

/**
 * A `YYYY-MM-DD` day moved by whole calendar days.
 *
 * Counted on the UTC midnight of the day, where every day has exactly 24 hours,
 * so a daylight-saving change can never skip or repeat a date.
 */
export function addCalendarDays(isoDay: string, days: number): string {
  return new Date(Date.parse(`${isoDay}T00:00:00.000Z`) + days * DAY_MS).toISOString().slice(0, 10);
}

const campusClockFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: CAMPUS_TIME_ZONE,
  hourCycle: 'h23',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

/** How far Europe/Berlin's wall clock is ahead of UTC at `instant`, in ms. */
function campusOffsetMs(instant: number): number {
  const parts = new Map<string, number>();
  for (const part of campusClockFormatter.formatToParts(new Date(instant))) {
    if (part.type !== 'literal') parts.set(part.type, Number(part.value));
  }
  const read = (type: string): number => parts.get(type) ?? 0;
  const wall = Date.UTC(
    read('year'),
    read('month') - 1,
    read('day'),
    read('hour'),
    read('minute'),
    read('second'),
  );
  return wall - Math.floor(instant / 1000) * 1000;
}

/**
 * The instant a `YYYY-MM-DD` campus day begins: local midnight in
 * Europe/Berlin. Berlin changes its clocks at 02:00/03:00, never at midnight,
 * so midnight always exists exactly once; the second lookup settles the offset
 * on the night of a change.
 */
export function campusDayStart(isoDay: string): Date {
  const wall = Date.parse(`${isoDay}T00:00:00.000Z`);
  const guess = wall - campusOffsetMs(wall);
  return new Date(wall - campusOffsetMs(guess));
}

/** The last millisecond of a `YYYY-MM-DD` campus day in Europe/Berlin. */
export function campusDayEnd(isoDay: string): Date {
  return new Date(campusDayStart(addCalendarDays(isoDay, 1)).getTime() - 1);
}
