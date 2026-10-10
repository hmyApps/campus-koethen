import { IcsParseError, ParseOptions, ParsedEvent, parseIcs } from './ics-parser';

function first(events: ParsedEvent[]): ParsedEvent {
  const e = events[0];
  if (!e) throw new Error('expected at least one event');
  return e;
}

/**
 * Synthetic ICS fixtures only. Every calendar below is made up ("Beispielkurs",
 * "Mustertermine", "Öffentliche Veranstaltungen") — no real Google calendar,
 * no real people, no real e-mail addresses.
 *
 * ICS uses CRLF line endings; the fixtures use \r\n deliberately.
 */
function ics(lines: string[]): string {
  return lines.join('\r\n') + '\r\n';
}

const VCAL_OPEN = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Synthetic//Test//EN'];
const VCAL_CLOSE = ['END:VCALENDAR'];

function baseOptions(overrides: Partial<ParseOptions> = {}): ParseOptions {
  return {
    windowStart: new Date('2026-01-01T00:00:00.000Z'),
    windowEnd: new Date('2026-12-31T00:00:00.000Z'),
    fallbackTimeZone: 'Europe/Berlin',
    includeDescription: true,
    includeLocation: true,
    maxEvents: 1000,
    maxOccurrences: 5000,
    maxOccurrencesPerEvent: 750,
    maxScannedOccurrences: 250_000,
    maxTextLength: 2000,
    ...overrides,
  };
}

describe('parseIcs — invalid input', () => {
  it('rejects a non-VCALENDAR body', () => {
    expect(() => parseIcs('this is not ics', baseOptions())).toThrow(IcsParseError);
  });
  it('rejects an empty string', () => {
    expect(() => parseIcs('', baseOptions())).toThrow(IcsParseError);
  });
  it('accepts a valid but empty VCALENDAR as zero events', () => {
    const events = parseIcs(ics([...VCAL_OPEN, ...VCAL_CLOSE]), baseOptions());
    expect(events).toEqual([]);
  });
});

describe('parseIcs — single timed events', () => {
  it('parses a UTC timed event to an absolute instant', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-utc-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DTEND:20260610T093000Z',
        'SUMMARY:Beispielsitzung',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    expect(events).toHaveLength(1);
    expect(first(events).title).toBe('Beispielsitzung');
    expect(first(events).allDay).toBe(false);
    expect(first(events).start.toISOString()).toBe('2026-06-10T08:00:00.000Z');
    expect(first(events).end.toISOString()).toBe('2026-06-10T09:30:00.000Z');
  });

  it('converts a TZID + VTIMEZONE event to the correct UTC instant (summer, +02:00)', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VTIMEZONE',
        'TZID:Europe/Berlin',
        'BEGIN:DAYLIGHT',
        'TZOFFSETFROM:+0100',
        'TZOFFSETTO:+0200',
        'TZNAME:CEST',
        'DTSTART:19700329T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
        'END:DAYLIGHT',
        'BEGIN:STANDARD',
        'TZOFFSETFROM:+0200',
        'TZOFFSETTO:+0100',
        'TZNAME:CET',
        'DTSTART:19701025T030000',
        'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
        'END:STANDARD',
        'END:VTIMEZONE',
        'BEGIN:VEVENT',
        'UID:evt-tz-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART;TZID=Europe/Berlin:20260610T100000',
        'DTEND;TZID=Europe/Berlin:20260610T113000',
        'SUMMARY:Mustertermin',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    expect(events).toHaveLength(1);
    // 10:00 CEST (+02:00) == 08:00 UTC
    expect(first(events).start.toISOString()).toBe('2026-06-10T08:00:00.000Z');
    expect(first(events).end.toISOString()).toBe('2026-06-10T09:30:00.000Z');
  });

  it('derives the end from DTSTART + DURATION', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-dur-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DURATION:PT1H30M',
        'SUMMARY:Mit Dauer',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    expect(first(events).end.toISOString()).toBe('2026-06-10T09:30:00.000Z');
  });
});

describe('parseIcs — floating times on DST change days', () => {
  /** One zone-less event at `local`, read in the Europe/Berlin fallback. */
  function floatingStart(local: string): string {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        `UID:evt-floating-${local}`,
        'DTSTAMP:20260301T120000Z',
        `DTSTART:${local}`,
        'DURATION:PT30M',
        'SUMMARY:Ohne Zeitzone',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    return first(events).start.toISOString();
  }

  // A single offset lookup at "wall clock read as UTC" lands on the wrong side
  // of the change whenever the change happens between the two readings —
  // in Berlin that is 01:00–01:59 local on both change days.
  it('reads 01:30 on the spring-forward day as CET (+01:00)', () => {
    expect(floatingStart('20260329T013000')).toBe('2026-03-29T00:30:00.000Z');
  });

  it('reads 01:30 on the fall-back day as CEST (+02:00)', () => {
    expect(floatingStart('20261025T013000')).toBe('2026-10-24T23:30:00.000Z');
  });

  it('reads a time inside the spring-forward gap with the offset before the gap', () => {
    // RFC 5545 §3.3.5: 02:30 does not exist; it means 03:30 CEST.
    expect(floatingStart('20260329T023000')).toBe('2026-03-29T01:30:00.000Z');
  });

  it('reads an ambiguous fall-back time as its first occurrence', () => {
    // RFC 5545 §3.3.5: 02:30 occurs twice; it means the first, still CEST.
    expect(floatingStart('20261025T023000')).toBe('2026-10-25T00:30:00.000Z');
  });

  it('is unchanged away from the change', () => {
    expect(floatingStart('20260329T033000')).toBe('2026-03-29T01:30:00.000Z');
    expect(floatingStart('20261025T033000')).toBe('2026-10-25T02:30:00.000Z');
    expect(floatingStart('20260115T120000')).toBe('2026-01-15T11:00:00.000Z');
    expect(floatingStart('20260715T120000')).toBe('2026-07-15T10:00:00.000Z');
  });
});

describe('parseIcs — all-day events', () => {
  it('treats VALUE=DATE as a local calendar day with an EXCLUSIVE end date', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-allday-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART;VALUE=DATE:20260610',
        'DTEND;VALUE=DATE:20260611',
        'SUMMARY:Ganztag',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    expect(events).toHaveLength(1);
    expect(first(events).allDay).toBe(true);
    // Start is the local date at 00:00; end is the exclusive next day at 00:00.
    // Represented as the UTC midnight of those dates (no device-zone shift).
    expect(first(events).start.toISOString()).toBe('2026-06-10T00:00:00.000Z');
    expect(first(events).end.toISOString()).toBe('2026-06-11T00:00:00.000Z');
  });
});

describe('parseIcs — recurrence', () => {
  it('expands a weekly RRULE only within the window', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-rrule-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260601T080000Z',
        'DTEND:20260601T090000Z',
        'RRULE:FREQ=WEEKLY;COUNT=5',
        'SUMMARY:Wöchentlich',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({
        windowStart: new Date('2026-06-01T00:00:00.000Z'),
        windowEnd: new Date('2026-06-15T00:00:00.000Z'),
      }),
    );
    // Jun 1, Jun 8 within window; Jun 15 is the exclusive end boundary; later ones out.
    const starts = events.map((e) => e.start.toISOString());
    expect(starts).toContain('2026-06-01T08:00:00.000Z');
    expect(starts).toContain('2026-06-08T08:00:00.000Z');
    expect(starts.every((s) => new Date(s) < new Date('2026-06-15T00:00:00.000Z'))).toBe(true);
    // Every occurrence keeps the master UID and gets a distinct occurrence key.
    expect(new Set(events.map((e) => e.uid))).toEqual(new Set(['evt-rrule-1']));
    expect(new Set(events.map((e) => e.occurrenceKey)).size).toBe(events.length);
  });

  it('windows a floating (zone-less) series by the same instants it emits', () => {
    // Floating times are the one path where the absolute instant is derived by
    // this module rather than by ical.js. The loop decides membership of the
    // window from those instants and the emitted event carries them, so the two
    // must not be able to disagree: an occurrence that survives the window check
    // has to be reported with exactly the instants that check used.
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-floating-window',
        'DTSTAMP:20260301T120000Z',
        // No Z, no TZID: interpreted in the configured fallback zone.
        'DTSTART:20260322T230000',
        'DTEND:20260323T003000',
        'RRULE:FREQ=DAILY;COUNT=14',
        'SUMMARY:Späte Übung',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({
        // Deliberately across the spring-forward change (2026-03-29), so the
        // UTC offset is not constant over the series.
        windowStart: new Date('2026-03-27T00:00:00.000Z'),
        windowEnd: new Date('2026-04-02T00:00:00.000Z'),
      }),
    );

    expect(events.map((e) => e.start.toISOString())).toEqual([
      // 26.03. 23:00 CET ends at 26.03. 23:30 UTC, before the window opens.
      '2026-03-27T22:00:00.000Z',
      '2026-03-28T22:00:00.000Z',
      '2026-03-29T21:00:00.000Z', // CEST from here on: 23:00 local is 21:00 UTC
      '2026-03-30T21:00:00.000Z',
      '2026-03-31T21:00:00.000Z',
      '2026-04-01T21:00:00.000Z',
    ]);
    for (const event of events) {
      expect(event.end.getTime()).toBeGreaterThan(event.start.getTime());
      expect(event.end.getTime()).toBeGreaterThan(new Date('2026-03-27T00:00:00.000Z').getTime());
      expect(event.start.getTime()).toBeLessThan(new Date('2026-04-02T00:00:00.000Z').getTime());
    }
  });

  it('applies EXDATE to remove one occurrence', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-exdate-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260601T080000Z',
        'DTEND:20260601T090000Z',
        'RRULE:FREQ=WEEKLY;COUNT=3',
        'EXDATE:20260608T080000Z',
        'SUMMARY:Mit Ausnahme',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({
        windowStart: new Date('2026-06-01T00:00:00.000Z'),
        windowEnd: new Date('2026-06-30T00:00:00.000Z'),
      }),
    );
    const starts = events.map((e) => e.start.toISOString());
    expect(starts).toContain('2026-06-01T08:00:00.000Z');
    expect(starts).not.toContain('2026-06-08T08:00:00.000Z');
    expect(starts).toContain('2026-06-15T08:00:00.000Z');
  });

  it('keeps an override\u2019s own text, status, sequence and modification time', () => {
    // Per-component values (SUMMARY, DESCRIPTION, LOCATION, SEQUENCE, STATUS,
    // LAST-MODIFIED) are derived once per source component. An override IS its
    // own component, so it must not inherit the series\u2019 values \u2014 and the
    // series must not inherit the override\u2019s.
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-override-fields',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260601T080000Z',
        'DTEND:20260601T090000Z',
        'RRULE:FREQ=WEEKLY;COUNT=3',
        'SEQUENCE:1',
        'STATUS:CONFIRMED',
        'LAST-MODIFIED:20260301T100000Z',
        'SUMMARY:Serie',
        'LOCATION:Raum 1',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:evt-override-fields',
        'RECURRENCE-ID:20260608T080000Z',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260608T080000Z',
        'DTEND:20260608T090000Z',
        'SEQUENCE:4',
        'STATUS:CANCELLED',
        'LAST-MODIFIED:20260504T090000Z',
        'SUMMARY:Entf\u00e4llt',
        'LOCATION:Raum 2',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({
        windowStart: new Date('2026-06-01T00:00:00.000Z'),
        windowEnd: new Date('2026-06-30T00:00:00.000Z'),
      }),
    );

    const series = events.filter((e) => e.title === 'Serie');
    const override = events.find((e) => e.title === 'Entf\u00e4llt');

    expect(series).toHaveLength(2);
    for (const occurrence of series) {
      expect(occurrence.sequence).toBe(1);
      expect(occurrence.status).toBe('confirmed');
      expect(occurrence.location).toBe('Raum 1');
      expect(occurrence.sourceUpdatedAt?.toISOString()).toBe('2026-03-01T10:00:00.000Z');
    }

    expect(override).toBeDefined();
    expect(override?.sequence).toBe(4);
    expect(override?.status).toBe('cancelled');
    expect(override?.location).toBe('Raum 2');
    expect(override?.sourceUpdatedAt?.toISOString()).toBe('2026-05-04T09:00:00.000Z');

    // Every occurrence gets its own Date: a shared instance would be mutable
    // state common to the whole series.
    expect(series[0]!.sourceUpdatedAt).not.toBe(series[1]!.sourceUpdatedAt);
    series[0]!.sourceUpdatedAt?.setTime(0);
    expect(series[1]!.sourceUpdatedAt?.toISOString()).toBe('2026-03-01T10:00:00.000Z');
  });

  it('applies a RECURRENCE-ID override that moves one occurrence', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-override-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260601T080000Z',
        'DTEND:20260601T090000Z',
        'RRULE:FREQ=WEEKLY;COUNT=3',
        'SUMMARY:Serie',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:evt-override-1',
        'RECURRENCE-ID:20260608T080000Z',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260608T140000Z',
        'DTEND:20260608T150000Z',
        'SUMMARY:Verschoben',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({
        windowStart: new Date('2026-06-01T00:00:00.000Z'),
        windowEnd: new Date('2026-06-30T00:00:00.000Z'),
      }),
    );
    const moved = events.find((e) => e.title === 'Verschoben');
    expect(moved).toBeDefined();
    expect(moved?.start.toISOString()).toBe('2026-06-08T14:00:00.000Z');
    // The original 08:00 occurrence on Jun 8 must be gone.
    expect(events.filter((e) => e.start.toISOString() === '2026-06-08T08:00:00.000Z')).toHaveLength(
      0,
    );
  });

  it('keeps expanding a series after one occurrence was moved past the window end', () => {
    // The loop used to stop at the first occurrence whose (moved) START lay
    // past the window, as if iteration were monotonic in the moved start. It
    // is only monotonic in the original slot, so every later regular
    // occurrence silently disappeared.
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-moved-out',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260601T080000Z',
        'DTEND:20260601T090000Z',
        'RRULE:FREQ=WEEKLY;COUNT=12',
        'SUMMARY:Serie',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:evt-moved-out',
        'RECURRENCE-ID:20260608T080000Z',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260901T080000Z',
        'DTEND:20260901T090000Z',
        'SUMMARY:Weit verschoben',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({
        windowStart: new Date('2026-06-01T00:00:00.000Z'),
        windowEnd: new Date('2026-08-01T00:00:00.000Z'),
      }),
    );

    expect(events.map((e) => e.start.toISOString())).toEqual([
      '2026-06-01T08:00:00.000Z',
      '2026-06-15T08:00:00.000Z',
      '2026-06-22T08:00:00.000Z',
      '2026-06-29T08:00:00.000Z',
      '2026-07-06T08:00:00.000Z',
      '2026-07-13T08:00:00.000Z',
      '2026-07-20T08:00:00.000Z',
      '2026-07-27T08:00:00.000Z',
    ]);
    expect(events.some((e) => e.title === 'Weit verschoben')).toBe(false);
  });

  it('emits an occurrence moved INTO the window from a slot after it', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-moved-in',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260601T080000Z',
        'DTEND:20260601T090000Z',
        'RRULE:FREQ=WEEKLY;COUNT=12',
        'SUMMARY:Serie',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:evt-moved-in',
        'RECURRENCE-ID:20260810T080000Z',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260701T140000Z',
        'DTEND:20260701T150000Z',
        'SUMMARY:Vorgezogen',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({
        windowStart: new Date('2026-06-01T00:00:00.000Z'),
        windowEnd: new Date('2026-08-01T00:00:00.000Z'),
      }),
    );

    const moved = events.find((e) => e.title === 'Vorgezogen');
    expect(moved).toBeDefined();
    expect(moved?.start.toISOString()).toBe('2026-07-01T14:00:00.000Z');
    expect(moved?.recurrenceId).toBe('2026-08-10T08:00:00.000Z');
    expect(moved?.occurrenceKey).toBe('evt-moved-in::2026-08-10T08:00:00.000Z');
    // The nine regular occurrences inside the window are all still there.
    expect(events.filter((e) => e.title === 'Serie')).toHaveLength(9);
    expect(new Set(events.map((e) => e.occurrenceKey)).size).toBe(events.length);
  });

  it('never applies one series’ override to another series sharing the slot', () => {
    // ical.js relates EVERY RECURRENCE-ID component of the calendar to a
    // master unless it is handed the exceptions explicitly. Two series that
    // share a slot time then both picked up the one override — the other
    // series showed a foreign cancellation, under a duplicate occurrence key.
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:series-a',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260601T080000Z',
        'DTEND:20260601T090000Z',
        'RRULE:FREQ=WEEKLY;COUNT=3',
        'SUMMARY:Serie A',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:series-b',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260601T080000Z',
        'DTEND:20260601T090000Z',
        'RRULE:FREQ=WEEKLY;COUNT=3',
        'SUMMARY:Serie B',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:series-a',
        'RECURRENCE-ID:20260608T080000Z',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260608T140000Z',
        'DTEND:20260608T150000Z',
        'STATUS:CANCELLED',
        'SUMMARY:A entfällt',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({
        windowStart: new Date('2026-06-01T00:00:00.000Z'),
        windowEnd: new Date('2026-06-30T00:00:00.000Z'),
      }),
    );

    const seriesB = events.filter((e) => e.uid === 'series-b');
    expect(seriesB.map((e) => [e.title, e.status, e.start.toISOString()])).toEqual([
      ['Serie B', 'confirmed', '2026-06-01T08:00:00.000Z'],
      ['Serie B', 'confirmed', '2026-06-08T08:00:00.000Z'],
      ['Serie B', 'confirmed', '2026-06-15T08:00:00.000Z'],
    ]);
    expect(events.filter((e) => e.title === 'A entfällt')).toHaveLength(1);
    expect(new Set(events.map((e) => e.occurrenceKey)).size).toBe(events.length);
  });

  it('marks a cancelled whole event', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-cancelled-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DTEND:20260610T090000Z',
        'STATUS:CANCELLED',
        'SUMMARY:Abgesagt',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    expect(events).toHaveLength(1);
    expect(first(events).status).toBe('cancelled');
  });
});

describe('parseIcs — redaction and safety', () => {
  it('never carries ATTENDEE / ORGANIZER e-mail addresses', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-pii-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DTEND:20260610T090000Z',
        'SUMMARY:Öffentliche Veranstaltung',
        'ORGANIZER;CN=Muster:mailto:organizer@example.invalid',
        'ATTENDEE;CN=Gast:mailto:attendee@example.invalid',
        'DESCRIPTION:Beschreibung ohne PII',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    const serialised = JSON.stringify(first(events));
    expect(serialised).not.toContain('example.invalid');
    expect(serialised).not.toContain('organizer');
    expect(serialised).not.toContain('attendee');
  });

  it('omits description and location when the calendar disables them', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-gate-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DTEND:20260610T090000Z',
        'SUMMARY:Ohne Details',
        'DESCRIPTION:Geheime Beschreibung',
        'LOCATION:Geheimer Ort',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({ includeDescription: false, includeLocation: false }),
    );
    expect(first(events).description).toBeNull();
    expect(first(events).location).toBeNull();
  });

  it('unescapes text and strips control characters, and never renders HTML', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-escape-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DTEND:20260610T090000Z',
        'SUMMARY:Titel mit Komma\\, Semikolon\\; und Zeile\\nZwei',
        'DESCRIPTION:<script>alert(1)</script>',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    expect(first(events).title).toContain(',');
    expect(first(events).title).toContain(';');
    expect(first(events).title).toContain('\n');
    // Description is kept verbatim as PLAIN TEXT (never parsed as HTML by us).
    expect(first(events).description).toBe('<script>alert(1)</script>');
  });

  it('truncates over-long text', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-long-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DTEND:20260610T090000Z',
        'SUMMARY:' + 'x'.repeat(500),
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({ maxTextLength: 100 }),
    );
    expect(first(events).title.length).toBeLessThanOrEqual(100);
  });

  it('never cuts a surrogate pair in half when truncating', () => {
    // The limit is counted in UTF-16 code units, and an emoji occupies two of
    // them. Cutting between the halves leaves a lone high surrogate: not valid
    // text, and PostgreSQL stores it as the replacement character.
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-surrogate-1',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DTEND:20260610T090000Z',
        // The 100th and 101st code unit are the two halves of one emoji.
        'DESCRIPTION:' + 'x'.repeat(99) + '\u{1F600}Rest',
        'SUMMARY:Mustertermin',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions({ maxTextLength: 100 }),
    );

    const description = first(events).description ?? '';
    expect(description).toBe('x'.repeat(99));
    // Every code unit is a complete character: no half of a pair survived.
    expect([...description]).toHaveLength(99);
  });
});

/**
 * Zones a feed names but never defines.
 *
 * A `TZID` parameter is only meaningful when the feed ships the matching
 * `VTIMEZONE`. When it does not, ical.js falls back to another reading, and an
 * exception that no longer matches its slot is not applied at all — the
 * occurrence is then published with the master's time and status, which for a
 * cancelled or moved date is a false statement about a campus event.
 *
 * `DTSTART`/`DTEND` were already guarded. `RECURRENCE-ID`, `EXDATE` and
 * `RDATE` carry the same parameter and are guarded here for the same reason.
 * Refusing the feed is the conservative answer: `unsupportedTimeZone` keeps the
 * last good events and marks the calendar, it never deletes anything.
 */
describe('parseIcs — undefined time zones', () => {
  const SERIES = [
    'BEGIN:VEVENT',
    'UID:evt-serie-1',
    'DTSTAMP:20260301T120000Z',
    'DTSTART:20260610T100000Z',
    'DTEND:20260610T110000Z',
    'RRULE:FREQ=DAILY;COUNT=4',
    'SUMMARY:Mustertermine',
    'END:VEVENT',
  ];

  const VTIMEZONE_BERLIN = [
    'BEGIN:VTIMEZONE',
    'TZID:Europe/Berlin',
    'BEGIN:STANDARD',
    'DTSTART:19701025T030000',
    'TZOFFSETFROM:+0200',
    'TZOFFSETTO:+0100',
    'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
    'TZNAME:CET',
    'END:STANDARD',
    'BEGIN:DAYLIGHT',
    'DTSTART:19700329T020000',
    'TZOFFSETFROM:+0100',
    'TZOFFSETTO:+0200',
    'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
    'TZNAME:CEST',
    'END:DAYLIGHT',
    'END:VTIMEZONE',
  ];

  it('refuses a DTSTART whose zone the feed never defined', () => {
    expect(() =>
      parseIcs(
        ics([
          ...VCAL_OPEN,
          'BEGIN:VEVENT',
          'UID:evt-tz-1',
          'DTSTAMP:20260301T120000Z',
          'DTSTART;TZID=Europe/Berlin:20260610T100000',
          'DTEND;TZID=Europe/Berlin:20260610T110000',
          'SUMMARY:Beispielkurs',
          'END:VEVENT',
          ...VCAL_CLOSE,
        ]),
        baseOptions(),
      ),
    ).toThrow(IcsParseError);
  });

  it('refuses a RECURRENCE-ID whose zone the feed never defined', () => {
    // Without this the cancellation is silently dropped and the occurrence is
    // published as an ordinary, confirmed date.
    expect(() =>
      parseIcs(
        ics([
          ...VCAL_OPEN,
          ...SERIES,
          'BEGIN:VEVENT',
          'UID:evt-serie-1',
          'DTSTAMP:20260301T120000Z',
          'RECURRENCE-ID;TZID=Europe/Berlin:20260611T120000',
          'DTSTART:20260611T100000Z',
          'DTEND:20260611T110000Z',
          'STATUS:CANCELLED',
          'SUMMARY:Mustertermine',
          'END:VEVENT',
          ...VCAL_CLOSE,
        ]),
        baseOptions(),
      ),
    ).toThrow(IcsParseError);
  });

  it('refuses an EXDATE whose zone the feed never defined', () => {
    expect(() =>
      parseIcs(
        ics([
          ...VCAL_OPEN,
          'BEGIN:VEVENT',
          'UID:evt-serie-2',
          'DTSTAMP:20260301T120000Z',
          'DTSTART:20260610T100000Z',
          'DTEND:20260610T110000Z',
          'RRULE:FREQ=DAILY;COUNT=3',
          'EXDATE;TZID=Europe/Berlin:20260611T120000',
          'SUMMARY:Mustertermine',
          'END:VEVENT',
          ...VCAL_CLOSE,
        ]),
        baseOptions(),
      ),
    ).toThrow(IcsParseError);
  });

  it('refuses an RDATE whose zone the feed never defined', () => {
    expect(() =>
      parseIcs(
        ics([
          ...VCAL_OPEN,
          'BEGIN:VEVENT',
          'UID:evt-serie-3',
          'DTSTAMP:20260301T120000Z',
          'DTSTART:20260610T100000Z',
          'DTEND:20260610T110000Z',
          'RDATE;TZID=Europe/Berlin:20260615T120000',
          'SUMMARY:Mustertermine',
          'END:VEVENT',
          ...VCAL_CLOSE,
        ]),
        baseOptions(),
      ),
    ).toThrow(IcsParseError);
  });

  it('checks every EXDATE, not only the first', () => {
    expect(() =>
      parseIcs(
        ics([
          ...VCAL_OPEN,
          ...VTIMEZONE_BERLIN,
          'BEGIN:VEVENT',
          'UID:evt-serie-4',
          'DTSTAMP:20260301T120000Z',
          'DTSTART:20260610T100000Z',
          'DTEND:20260610T110000Z',
          'RRULE:FREQ=DAILY;COUNT=4',
          'EXDATE;TZID=Europe/Berlin:20260611T120000',
          'EXDATE;TZID=Europe/Lisbon:20260612T110000',
          'SUMMARY:Mustertermine',
          'END:VEVENT',
          ...VCAL_CLOSE,
        ]),
        baseOptions(),
      ),
    ).toThrow(IcsParseError);
  });

  it('applies the cancellation when the feed does define the zone', () => {
    // The control for the four refusals above: a complete feed keeps working
    // exactly as before, so the guard cannot be mistaken for a new limitation.
    // This is the shape Google actually exports — series and exception in the
    // same declared zone.
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        ...VTIMEZONE_BERLIN,
        'BEGIN:VEVENT',
        'UID:evt-serie-5',
        'DTSTAMP:20260301T120000Z',
        'DTSTART;TZID=Europe/Berlin:20260610T120000',
        'DTEND;TZID=Europe/Berlin:20260610T130000',
        'RRULE:FREQ=DAILY;COUNT=4',
        'SUMMARY:Mustertermine',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:evt-serie-5',
        'DTSTAMP:20260301T120000Z',
        'RECURRENCE-ID;TZID=Europe/Berlin:20260611T120000',
        'DTSTART;TZID=Europe/Berlin:20260611T120000',
        'DTEND;TZID=Europe/Berlin:20260611T130000',
        'STATUS:CANCELLED',
        'SUMMARY:Mustertermine',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );

    expect(events).toHaveLength(4);
    expect(events.map((e) => e.status)).toEqual([
      'confirmed',
      'cancelled',
      'confirmed',
      'confirmed',
    ]);
  });

  it('leaves a UTC or zone-less feed untouched', () => {
    const events = parseIcs(ics([...VCAL_OPEN, ...SERIES, ...VCAL_CLOSE]), baseOptions());
    expect(events).toHaveLength(4);
  });
});

describe('parseIcs — resource limits', () => {
  it('throws when the event count exceeds the limit', () => {
    const many: string[] = [];
    for (let i = 0; i < 5; i++) {
      many.push(
        'BEGIN:VEVENT',
        `UID:evt-${i}`,
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20260610T080000Z',
        'DTEND:20260610T090000Z',
        `SUMMARY:Termin ${i}`,
        'END:VEVENT',
      );
    }
    expect(() =>
      parseIcs(ics([...VCAL_OPEN, ...many, ...VCAL_CLOSE]), baseOptions({ maxEvents: 3 })),
    ).toThrow(IcsParseError);
  });

  it('throws recurrenceLimitExceeded on an unbounded high-frequency rule', () => {
    expect(() =>
      parseIcs(
        ics([
          ...VCAL_OPEN,
          'BEGIN:VEVENT',
          'UID:evt-bomb-1',
          'DTSTAMP:20260301T120000Z',
          'DTSTART:20260101T000000Z',
          'DTEND:20260101T000100Z',
          'RRULE:FREQ=MINUTELY',
          'SUMMARY:Bombe',
          'END:VEVENT',
          ...VCAL_CLOSE,
        ]),
        baseOptions({ maxOccurrencesPerEvent: 100 }),
      ),
    ).toThrow(IcsParseError);
  });
  it('expands a long-running weekly series that started years before the window', () => {
    // The iterator always starts at DTSTART. Occurrences BEFORE the window are
    // skipped, not charged against the per-event budget — otherwise an ordinary
    // recurring lecture from 2010 would take the whole feed down with it.
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-weekly-legacy',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20100104T080000Z',
        'DTEND:20100104T090000Z',
        'RRULE:FREQ=WEEKLY',
        'SUMMARY:Wochentermin',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    // 2026 has 52 Mondays; every occurrence must fall inside the window.
    expect(events.length).toBe(52);
    expect(events.every((event) => event.start >= new Date('2026-01-01T00:00:00.000Z'))).toBe(true);
  });

  it('expands a daily series that started years before the window', () => {
    const events = parseIcs(
      ics([
        ...VCAL_OPEN,
        'BEGIN:VEVENT',
        'UID:evt-daily-legacy',
        'DTSTAMP:20260301T120000Z',
        'DTSTART:20230101T080000Z',
        'DTEND:20230101T090000Z',
        'RRULE:FREQ=DAILY',
        'SUMMARY:Tagestermin',
        'END:VEVENT',
        ...VCAL_CLOSE,
      ]),
      baseOptions(),
    );
    expect(events.length).toBe(364);
  });

  it('still enforces the per-event limit on occurrences inside the window', () => {
    expect(() =>
      parseIcs(
        ics([
          ...VCAL_OPEN,
          'BEGIN:VEVENT',
          'UID:evt-daily-legacy-capped',
          'DTSTAMP:20260301T120000Z',
          'DTSTART:20230101T080000Z',
          'DTEND:20230101T090000Z',
          'RRULE:FREQ=DAILY',
          'SUMMARY:Tagestermin',
          'END:VEVENT',
          ...VCAL_CLOSE,
        ]),
        baseOptions({ maxOccurrencesPerEvent: 100 }),
      ),
    ).toThrow(IcsParseError);
  });

  it('throws recurrenceLimitExceeded when skipping past the window exhausts the scan budget', () => {
    // A high-frequency rule far BEFORE the window produces no in-window
    // occurrence for a very long time. The global scan budget is what stops it.
    expect(() =>
      parseIcs(
        ics([
          ...VCAL_OPEN,
          'BEGIN:VEVENT',
          'UID:evt-bomb-2',
          'DTSTAMP:20260301T120000Z',
          'DTSTART:20200101T000000Z',
          'DTEND:20200101T000100Z',
          'RRULE:FREQ=MINUTELY',
          'SUMMARY:Alte Bombe',
          'END:VEVENT',
          ...VCAL_CLOSE,
        ]),
        baseOptions({ maxScannedOccurrences: 5_000 }),
      ),
    ).toThrow(IcsParseError);
  });
});
