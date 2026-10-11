// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import { validateCatalog } from './public-calendar.strapi';

/** Synthetic entries only — a made-up calendar id inside a valid share link. */
const CID = Buffer.from('beispielkalender-a@group.calendar.google.com', 'utf8').toString(
  'base64url',
);
const SHARE = `https://calendar.google.com/calendar/u/0?cid=${CID}`;

function deEntry(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    slug: 'beispielkalender-a',
    name: 'Beispielkalender A',
    googleShareUrl: SHARE,
    colorHex: '#5B3FD0',
    sortOrder: 1,
    isActive: true,
    defaultSubscribed: true,
    includeEventDescription: true,
    includeEventLocation: false,
    channel: { slug: 'campus-events' },
    ...overrides,
  };
}

describe('validateCatalog', () => {
  it('accepts a valid entry and overlays the English translation by slug, extracting channelSlug', () => {
    const result = validateCatalog([deEntry()], [{ ...deEntry(), name: 'Sample calendar A' }]);
    expect(result.definitions).toHaveLength(1);
    const def = result.definitions[0];
    expect(def?.slug).toBe('beispielkalender-a');
    expect(def?.channelSlug).toBe('campus-events');
    expect(def?.googleCalendarId).toBe('beispielkalender-a@group.calendar.google.com');
    expect(def?.nameDe).toBe('Beispielkalender A');
    expect(def?.nameEn).toBe('Sample calendar A');
    expect(def?.colorHex).toBe('#5B3FD0');
    expect(def?.defaultSubscribed).toBe(true);
  });

  it('handles missing channel relation by setting channelSlug to null', () => {
    const result = validateCatalog([deEntry({ channel: null })], []);
    expect(result.definitions[0]?.channelSlug).toBeNull();
  });

  it('rejects an entry with an invalid share URL but keeps the others', () => {
    const result = validateCatalog(
      [
        deEntry(),
        deEntry({
          slug: 'boese',
          googleShareUrl: 'https://evil.example.com/calendar/render?cid=' + CID,
        }),
        deEntry({
          slug: 'privat',
          googleShareUrl: 'https://calendar.google.com/calendar/ical/x/private-abc/basic.ics',
        }),
      ],
      [],
    );
    expect(result.received).toBe(3);
    expect(result.rejected).toBe(2);
    expect(result.definitions.map((d) => d.slug)).toEqual(['beispielkalender-a']);
    // Rejected, not withdrawn: the sync must not retire these calendars.
    expect(result.rejectedSlugs).toEqual(['boese', 'privat']);
    expect(result.rejectedWithoutSlug).toBe(false);
  });

  it('flags a rejected entry that does not name a slug', () => {
    const result = validateCatalog([deEntry(), { name: 'Ohne Slug' }, null], []);
    expect(result.rejected).toBe(2);
    expect(result.rejectedSlugs).toEqual([]);
    expect(result.rejectedWithoutSlug).toBe(true);
  });

  it('rejects a bad slug and a bad colour', () => {
    const result = validateCatalog(
      [deEntry({ slug: 'Bad Slug' }), deEntry({ slug: 'x', colorHex: 'red' })],
      [],
    );
    expect(result.definitions).toHaveLength(0);
    expect(result.rejected).toBe(2);
  });

  it('maps the clearly named event inclusion switches', () => {
    const result = validateCatalog([deEntry()], []);
    expect(result.definitions[0]?.includeEventDescription).toBe(true);
    expect(result.definitions[0]?.includeEventLocation).toBe(false);
  });
});
