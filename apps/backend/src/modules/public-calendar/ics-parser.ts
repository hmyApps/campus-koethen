import ICAL from 'ical.js';

/**
 * RFC-5545 parsing + normalisation for public Google calendars.
 *
 * This is NOT a naive line splitter — it delegates the hard RFC-5545 work
 * (content-line folding, escaping, parameters, VTIMEZONE, RRULE/RDATE/EXDATE,
 * RECURRENCE-ID) to Mozilla's `ical.js` (the Thunderbird calendar engine,
 * MPL-2.0, zero runtime dependencies). `ical.js` never touches the network;
 * this module only ever receives the already-downloaded, size-bounded text.
 *
 * On top of ical.js this module:
 *  - expands recurrences ONLY inside the requested window, with two hard caps
 *    that stop a "recurrence bomb" from exhausting CPU/memory: how many
 *    occurrences of one event may REACH the window, and how many iterator
 *    steps the whole feed may cost while getting there,
 *  - normalises every occurrence to absolute instants, with correct all-day
 *    (VALUE=DATE, exclusive DTEND) and time-zone (VTIMEZONE / UTC / floating)
 *    semantics,
 *  - drops every privacy-sensitive property (ATTENDEE, ORGANIZER, CONTACT,
 *    ATTACH, conferencing, alarms, X-*) by simply never reading them,
 *  - keeps DESCRIPTION/LOCATION only when the calendar allows it, as plain text.
 */

export type IcsParseErrorKind =
  'invalidCalendar' | 'unsupportedTimeZone' | 'recurrenceLimitExceeded' | 'eventLimitExceeded';

export class IcsParseError extends Error {
  constructor(
    public readonly kind: IcsParseErrorKind,
    message: string,
  ) {
    super(message);
    this.name = 'IcsParseError';
  }
}

export type EventStatus = 'confirmed' | 'tentative' | 'cancelled';

export interface ParsedEvent {
  uid: string;
  /** ISO of the occurrence's RECURRENCE-ID slot, or null for a single event. */
  recurrenceId: string | null;
  sequence: number | null;
  title: string;
  description: string | null;
  location: string | null;
  /** Absolute instant. For all-day events, the UTC midnight of the local date. */
  start: Date;
  /** Absolute instant, EXCLUSIVE for all-day events. */
  end: Date;
  allDay: boolean;
  status: EventStatus;
  sourceUpdatedAt: Date | null;
  /** Stable identity of this occurrence WITHIN one calendar. */
  occurrenceKey: string;
}

export interface ParseOptions {
  windowStart: Date;
  windowEnd: Date;
  fallbackTimeZone: string;
  includeDescription: boolean;
  includeLocation: boolean;
  maxEvents: number;
  maxOccurrences: number;
  /**
   * Cap on the occurrences of ONE event that actually reach the window.
   * Occurrences that end before `windowStart` are skipped, not charged — the
   * iterator has no choice but to start at DTSTART, so charging them would make
   * an ordinary long-running weekly series indistinguishable from a bomb.
   */
  maxOccurrencesPerEvent: number;
  /**
   * Cap on the TOTAL iterator steps across the whole feed, skipped ones
   * included. This is what bounds the CPU cost of fast-forwarding to the
   * window, and therefore what stops a high-frequency rule that starts long
   * before it.
   */
  maxScannedOccurrences: number;
  maxTextLength: number;
}

const dtfCache = new Map<string, Intl.DateTimeFormat>();

function getDateTimeFormat(tz: string): Intl.DateTimeFormat {
  let dtf = dtfCache.get(tz);
  if (!dtf) {
    dtf = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      hour12: false,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    dtfCache.set(tz, dtf);
  }
  return dtf;
}

/** Removes control characters (keeping tab/newline), trims and truncates. */
function sanitizeText(value: string | null | undefined, maxLength: number): string | null {
  if (value === null || value === undefined) return null;
  // eslint-disable-next-line no-control-regex
  const cleaned = value.replace(/[\x00-\x08\x0B-\x1F\x7F]/g, '');
  let cut = cleaned.slice(0, maxLength);
  // The limit counts UTF-16 code units and an emoji occupies two of them, so
  // the cut can land between the halves of one character. What is left is a
  // lone high surrogate: not valid text, stored by PostgreSQL as the
  // replacement character and escaped into the JSON response as a code unit no
  // client can render. Dropping the orphaned half is the only truncation that
  // yields a string.
  const last = cut.charCodeAt(cut.length - 1);
  if (cut.length > 0 && last >= 0xd800 && last <= 0xdbff) {
    cut = cut.slice(0, -1);
  }
  const trimmed = cut.trimEnd();
  return trimmed.length > 0 ? trimmed : null;
}

/** Milliseconds to add to a UTC instant to obtain the wall clock in `tz`. */
function tzOffsetMs(instant: Date, tz: string): number {
  const dtf = getDateTimeFormat(tz);
  const parts = dtf.formatToParts(instant);
  let year = 0;
  let month = 0;
  let day = 0;
  let hour = 0;
  let minute = 0;
  let second = 0;
  for (const part of parts) {
    switch (part.type) {
      case 'year':
        year = Number(part.value);
        break;
      case 'month':
        month = Number(part.value);
        break;
      case 'day':
        day = Number(part.value);
        break;
      case 'hour':
        hour = Number(part.value);
        break;
      case 'minute':
        minute = Number(part.value);
        break;
      case 'second':
        second = Number(part.value);
        break;
    }
  }
  if (hour === 24) hour = 0;
  const asUtc = Date.UTC(year, month - 1, day, hour, minute, second);
  return asUtc - instant.getTime();
}

const DAY_MS = 86_400_000;

/**
 * Interprets a wall-clock time in `tz` as an absolute instant (DST-correct).
 *
 * A single offset lookup at "the wall clock read as UTC" is wrong whenever the
 * zone changes its offset between that reading and the real instant — in
 * Europe/Berlin 01:00–01:59 local on both change days. Instead the offsets in
 * force a day before and a day after are both tried, and an offset only counts
 * if the instant it yields really carries it. Per RFC 5545 §3.3.5 a wall clock
 * that occurs twice means the FIRST occurrence, and one inside a gap is read
 * with the offset from before the gap.
 */
function zonedWallClockToUtc(
  y: number,
  month1: number,
  d: number,
  h: number,
  mi: number,
  s: number,
  tz: string,
): Date {
  const wall = Date.UTC(y, month1 - 1, d, h, mi, s);
  const before = tzOffsetMs(new Date(wall - DAY_MS), tz);
  const after = tzOffsetMs(new Date(wall + DAY_MS), tz);
  // No change around this day: the one offset is the answer.
  if (before === after) return new Date(wall - before);

  let earliest: number | null = null;
  for (const offset of [before, after]) {
    const instant = wall - offset;
    if (tzOffsetMs(new Date(instant), tz) === offset) {
      earliest = earliest === null ? instant : Math.min(earliest, instant);
    }
  }
  // Neither offset fits: the wall clock falls into the gap.
  return new Date(earliest ?? wall - before);
}

interface AbsoluteTime {
  date: Date;
  allDay: boolean;
}

function toAbsolute(time: ICAL.Time, fallbackTimeZone: string): AbsoluteTime {
  if (time.isDate) {
    // VALUE=DATE is a local calendar date, never a UTC instant. Represent it as
    // the UTC midnight of that date so no device/UTC-midnight shift is possible.
    return { date: new Date(Date.UTC(time.year, time.month - 1, time.day)), allDay: true };
  }
  const zoneId: string | undefined = time.zone?.tzid;
  if (zoneId && zoneId !== 'floating') {
    // UTC or a registered VTIMEZONE: ical.js applies the offset for us.
    return { date: time.toJSDate(), allDay: false };
  }
  // Floating date-time: interpret the wall clock in the configured fallback.
  return {
    date: zonedWallClockToUtc(
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute,
      time.second,
      fallbackTimeZone,
    ),
    allDay: false,
  };
}

function normalizeStatus(raw: unknown): EventStatus {
  const value = typeof raw === 'string' ? raw.toUpperCase() : '';
  if (value === 'CANCELLED') return 'cancelled';
  if (value === 'TENTATIVE') return 'tentative';
  return 'confirmed';
}

/**
 * Every property that may carry a `TZID`, and therefore every property whose
 * zone the feed has to have defined.
 *
 * `DTSTART`/`DTEND` decide when an event is. The other three decide WHICH
 * occurrence of a series a line is about, and that is the part a missing zone
 * breaks silently: ical.js reads the value in another zone, the exception no
 * longer lands on its slot, and the occurrence is published with the master's
 * time and status. A cancelled or moved single date then still shows up as an
 * ordinary event — a false statement about a campus event rather than a
 * visible failure.
 *
 * `EXDATE` and `RDATE` may appear more than once in one VEVENT, so every
 * occurrence of the property is checked, not just the first.
 */
const TZID_BEARING_PROPERTIES = ['dtstart', 'dtend', 'recurrence-id', 'exdate', 'rdate'] as const;

function assertTimeZonesResolvable(vevent: ICAL.Component): void {
  for (const name of TZID_BEARING_PROPERTIES) {
    for (const prop of vevent.getAllProperties(name)) {
      const tzid = prop.getParameter('tzid');
      if (typeof tzid === 'string' && tzid !== 'UTC' && !ICAL.TimezoneService.has(tzid)) {
        throw new IcsParseError(
          'unsupportedTimeZone',
          'A referenced time zone is not defined by the feed.',
        );
      }
    }
  }
}

export function parseIcs(raw: string, options: ParseOptions): ParsedEvent[] {
  // Validate the fallback zone up front; an invalid one is a config error.
  try {
    getDateTimeFormat(options.fallbackTimeZone);
  } catch {
    throw new IcsParseError('unsupportedTimeZone', 'The fallback time zone is invalid.');
  }

  let root: ICAL.Component;
  try {
    // ical.js `parse` is typed as `any`; the jCal result is fed straight into
    // Component, which is the intended, documented usage.
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    const jcal = ICAL.parse(raw);
    // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
    root = new ICAL.Component(jcal);
  } catch {
    throw new IcsParseError('invalidCalendar', 'The body is not a valid iCalendar object.');
  }
  if (root.name !== 'vcalendar') {
    throw new IcsParseError('invalidCalendar', 'The body is not a VCALENDAR.');
  }

  // Register the feed's own VTIMEZONEs in an isolated, per-call registry so one
  // calendar's zones can never bleed into another's.
  ICAL.TimezoneService.reset();
  for (const vtz of root.getAllSubcomponents('vtimezone')) {
    try {
      ICAL.TimezoneService.register(vtz);
    } catch {
      // A malformed VTIMEZONE is ignored; a referencing event is caught below.
    }
  }

  const vevents = root.getAllSubcomponents('vevent');
  if (vevents.length > options.maxEvents) {
    throw new IcsParseError('eventLimitExceeded', 'The feed contains too many events.');
  }

  // Group by UID: the component without a RECURRENCE-ID is the master; the rest
  // are overrides of individual occurrences.
  const masters = new Map<string, ICAL.Component>();
  const overrides = new Map<string, ICAL.Component[]>();
  const orphanOverrides: ICAL.Component[] = [];

  for (const vevent of vevents) {
    const uid = vevent.getFirstPropertyValue('uid');
    if (typeof uid !== 'string' || uid.length === 0) continue;
    assertTimeZonesResolvable(vevent);
    if (vevent.getFirstProperty('recurrence-id')) {
      const list = overrides.get(uid) ?? [];
      list.push(vevent);
      overrides.set(uid, list);
    } else {
      masters.set(uid, vevent);
    }
  }
  for (const [uid, list] of overrides) {
    if (!masters.has(uid)) orphanOverrides.push(...list);
  }

  const windowStart = options.windowStart.getTime();
  const windowEnd = options.windowEnd.getTime();
  const result: ParsedEvent[] = [];
  /** Iterator steps across the whole feed, including those skipped before the window. */
  let scanned = 0;

  /**
   * Appends one occurrence, given its already-resolved absolute bounds.
   *
   * The bounds are passed IN rather than derived here because the recurrence
   * loop below has to resolve them anyway to decide whether an occurrence
   * reaches the window at all. Deriving them a second time meant four
   * conversions per delivered occurrence where two suffice — and for a floating
   * (zone-less) time each conversion goes through
   * `Intl.DateTimeFormat.formatToParts()`, the expensive path, up to
   * `maxOccurrences` times per feed.
   */
  /**
   * Everything an occurrence inherits unchanged from its source component.
   *
   * `sourceUpdatedAt` is held as epoch milliseconds rather than as a `Date`: a
   * cached `Date` would be one mutable object shared by every occurrence of the
   * same series.
   */
  interface ComponentText {
    uid: string;
    title: string;
    description: string | null;
    location: string | null;
    sequence: number | null;
    status: EventStatus;
    sourceUpdatedAtMs: number | null;
  }

  /**
   * Per-component derivation, resolved once per `parseIcs()` call.
   *
   * Title, description, location, SEQUENCE, STATUS and LAST-MODIFIED are
   * properties of the VEVENT, not of the individual occurrence: a series
   * without an override hands `emit()` the very same component for every one of
   * its occurrences. Deriving them there meant running the sanitiser over the
   * same description — up to `maxTextLength` characters — and scanning the
   * component's property list again for every occurrence of a series that can
   * span a 430-day window.
   *
   * An override IS its own component (`details.item` is the exception's event
   * when one exists), so a moved, renamed or cancelled single occurrence keeps
   * its own entry and its own text.
   *
   * The map lives and dies with this call, so nothing is ever carried between
   * two feeds.
   */
  const componentTexts = new Map<ICAL.Component, ComponentText>();

  const textsFor = (event: ICAL.Event): ComponentText => {
    const comp = event.component;
    const cached = componentTexts.get(comp);
    if (cached !== undefined) {
      return cached;
    }

    const sequenceRaw = comp.getFirstPropertyValue('sequence');
    const lastModified = comp.getFirstPropertyValue('last-modified');
    const derived: ComponentText = {
      uid: String(event.uid),
      title: sanitizeText(stringOrNull(event.summary), options.maxTextLength) ?? '',
      description: options.includeDescription
        ? sanitizeText(stringOrNull(event.description), options.maxTextLength)
        : null,
      location: options.includeLocation
        ? sanitizeText(stringOrNull(event.location), options.maxTextLength)
        : null,
      sequence: typeof sequenceRaw === 'number' ? sequenceRaw : null,
      status: normalizeStatus(comp.getFirstPropertyValue('status')),
      sourceUpdatedAtMs:
        lastModified instanceof ICAL.Time ? lastModified.toJSDate().getTime() : null,
    };
    componentTexts.set(comp, derived);
    return derived;
  };

  const emit = (
    event: ICAL.Event,
    abs: AbsoluteTime,
    absEnd: AbsoluteTime,
    recurrenceId: ICAL.Time | null,
  ): void => {
    if (absEnd.date.getTime() <= windowStart || abs.date.getTime() >= windowEnd) return;

    const texts = textsFor(event);
    const uid = texts.uid;
    const recurrenceIso = recurrenceId
      ? toAbsolute(recurrenceId, options.fallbackTimeZone).date.toISOString()
      : null;

    result.push({
      uid,
      recurrenceId: recurrenceIso,
      sequence: texts.sequence,
      title: texts.title,
      description: texts.description,
      location: texts.location,
      start: abs.date,
      end: absEnd.date,
      allDay: abs.allDay,
      status: texts.status,
      sourceUpdatedAt: texts.sourceUpdatedAtMs === null ? null : new Date(texts.sourceUpdatedAtMs),
      occurrenceKey: recurrenceIso ? `${uid}::${recurrenceIso}` : uid,
    });

    if (result.length > options.maxOccurrences) {
      throw new IcsParseError('recurrenceLimitExceeded', 'Too many expanded occurrences in total.');
    }
  };

  for (const [uid, masterComp] of masters) {
    // The overrides are handed over explicitly. Without the option ical.js
    // relates EVERY RECURRENCE-ID component of the calendar to this master,
    // whatever its UID, so two series sharing a slot time would both pick up
    // the one override — a foreign move or cancellation, under a duplicate
    // occurrence key.
    const event = new ICAL.Event(masterComp, { exceptions: overrides.get(uid) ?? [] });

    if (!event.isRecurring()) {
      emit(
        event,
        toAbsolute(event.startDate, options.fallbackTimeZone),
        toAbsolute(event.endDate, options.fallbackTimeZone),
        null,
      );
      continue;
    }

    // The iterator ALWAYS starts at DTSTART; it cannot be seeked, because the
    // rule is anchored there (INTERVAL, BYDAY and friends are relative to it).
    // A series that began years ago therefore has to be walked up to the
    // window, and those steps must not count against the per-event budget.
    const iterator = event.iterator();
    let relevant = 0;
    const countRelevant = (): void => {
      relevant += 1;
      if (relevant > options.maxOccurrencesPerEvent) {
        throw new IcsParseError(
          'recurrenceLimitExceeded',
          'A recurrence rule expanded past the per-event limit.',
        );
      }
    };
    let next: ICAL.Time | null;
    while ((next = iterator.next())) {
      scanned += 1;
      if (scanned > options.maxScannedOccurrences) {
        throw new IcsParseError(
          'recurrenceLimitExceeded',
          'Expanding the recurrences of this feed passed the total scan limit.',
        );
      }
      const details = event.getOccurrenceDetails(next);
      const abs = toAbsolute(details.startDate, options.fallbackTimeZone);
      // The iteration is monotonic in the ORIGINAL slot, not in the start an
      // override may have moved it to. Only the slot may end the walk; a
      // single occurrence moved past the window must not take every later
      // regular one with it. A regular occurrence starts on its slot, so the
      // conversion is only repeated for a moved one.
      const slot =
        details.startDate === next
          ? abs.date.getTime()
          : toAbsolute(next, options.fallbackTimeZone).date.getTime();
      if (slot >= windowEnd) break;
      if (abs.date.getTime() >= windowEnd) continue; // moved past the window
      const absEnd = toAbsolute(details.endDate, options.fallbackTimeZone);
      if (absEnd.date.getTime() <= windowStart) continue; // entirely before the window
      countRelevant();
      // `details.item` is the override for this slot when one exists (moved or
      // cancelled), otherwise the master — so title/status reflect the override.
      emit(details.item, abs, absEnd, details.recurrenceId);
    }

    // The walk above stops at the first slot past the window, so an override
    // whose slot lies there but which was moved INTO the window is never
    // reached. Those are checked against the window on their own. Overrides
    // with an earlier slot were already handled by the walk.
    for (const override of Object.values(event.exceptions)) {
      const slotTime = override.recurrenceId;
      if (toAbsolute(slotTime, options.fallbackTimeZone).date.getTime() < windowEnd) continue;
      const abs = toAbsolute(override.startDate, options.fallbackTimeZone);
      const absEnd = toAbsolute(override.endDate, options.fallbackTimeZone);
      if (abs.date.getTime() >= windowEnd || absEnd.date.getTime() <= windowStart) continue;
      countRelevant();
      emit(override, abs, absEnd, slotTime);
    }
  }

  // Overrides whose master is not in the feed: emit them as standalone events.
  for (const override of orphanOverrides) {
    const event = new ICAL.Event(override);
    emit(
      event,
      toAbsolute(event.startDate, options.fallbackTimeZone),
      toAbsolute(event.endDate, options.fallbackTimeZone),
      event.recurrenceId ?? null,
    );
  }

  return result;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}
