import { addCalendarDays, campusToday } from './campus-date';

describe('campusToday', () => {
  it.each([
    ['just after midnight in summer (CEST, UTC+2)', '2026-07-19T22:30:00.000Z', '2026-07-20'],
    ['just before midnight in summer', '2026-07-19T21:59:59.999Z', '2026-07-19'],
    ['just after midnight in winter (CET, UTC+1)', '2026-01-14T23:30:00.000Z', '2026-01-15'],
    ['just before midnight in winter', '2026-01-14T22:59:59.999Z', '2026-01-14'],
    ['the night the clocks go forward', '2026-03-28T23:30:00.000Z', '2026-03-29'],
    ['the night the clocks go back', '2026-10-24T22:30:00.000Z', '2026-10-25'],
    [
      'New Year in Berlin while UTC is still in the old year',
      '2026-12-31T23:15:00.000Z',
      '2027-01-01',
    ],
  ])('answers the Berlin calendar day %s', (_label, instant, expected) => {
    expect(campusToday(new Date(instant))).toBe(expected);
  });
});

describe('addCalendarDays', () => {
  it('counts whole calendar days, unaffected by daylight-saving changes', () => {
    expect(addCalendarDays('2026-03-28', 1)).toBe('2026-03-29');
    expect(addCalendarDays('2026-10-24', 1)).toBe('2026-10-25');
    expect(addCalendarDays('2026-09-24', 28)).toBe('2026-10-22');
    expect(addCalendarDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addCalendarDays('2026-07-20', 0)).toBe('2026-07-20');
  });
});
