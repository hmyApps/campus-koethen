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
