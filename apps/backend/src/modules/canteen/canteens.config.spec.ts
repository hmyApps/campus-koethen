import { CANTEENS, CAMPUS_SITES } from './canteens.config';

describe('canteen registry', () => {
  it('assigns every canteen to a known campus site', () => {
    for (const canteen of CANTEENS) {
      expect(CAMPUS_SITES).toContain(canteen.siteKey);
    }
  });

  it('puts the two Köthen canteens in Köthen and the others at their own site', () => {
    const siteOf = (slug: string) => CANTEENS.find((c) => c.slug === slug)?.siteKey;

    expect(siteOf('koethen-fasanerieallee')).toBe('koethen');
    expect(siteOf('koethen-lohmannstrasse')).toBe('koethen');
    expect(siteOf('dessau')).toBe('dessau');
    expect(siteOf('bernburg')).toBe('bernburg');
  });

  it('keeps slugs and upstream locations unique', () => {
    expect(new Set(CANTEENS.map((c) => c.slug)).size).toBe(CANTEENS.length);
    expect(new Set(CANTEENS.map((c) => c.sourceLocationId)).size).toBe(CANTEENS.length);
  });
});
