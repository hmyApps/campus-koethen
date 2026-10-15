/**
 * Canteen registry.
 *
 * This is the ONLY place that knows the upstream `location_id`. The value is
 * never exposed through the API and never reaches the app, so adding a canteen
 * costs a backend config change and a deployment — never an app release.
 *
 * Display names are API-owned bilingual strings, unlike the dish text, which
 * comes from a German-only source and is never translated.
 */

/** The campus sites of Hochschule Anhalt this app covers. */
export const CAMPUS_SITES = ['koethen', 'bernburg', 'dessau'] as const;
export type CampusSite = (typeof CAMPUS_SITES)[number];

export interface CanteenDefinition {
  slug: string;
  sourceLocationId: number;
  displayNameDe: string;
  displayNameEn: string;
  campusLabelDe: string;
  campusLabelEn: string;
  /** The campus site the canteen belongs to; the app lists its own site first. */
  siteKey: CampusSite;
  sortOrder: number;
  active: boolean;
}

export const CANTEENS: readonly CanteenDefinition[] = [
  {
    slug: 'koethen-fasanerieallee',
    sourceLocationId: 7,
    displayNameDe: 'Mensa Köthen',
    displayNameEn: 'Köthen Canteen',
    campusLabelDe: 'Fasanerieallee',
    campusLabelEn: 'Fasanerieallee',
    siteKey: 'koethen',
    sortOrder: 10,
    active: true,
  },
  {
    slug: 'koethen-lohmannstrasse',
    sourceLocationId: 22,
    displayNameDe: 'Mensa Lohmannstraße',
    displayNameEn: 'Lohmannstraße Canteen',
    campusLabelDe: 'Lohmannstraße',
    campusLabelEn: 'Lohmannstraße',
    siteKey: 'koethen',
    sortOrder: 20,
    active: true,
  },
  {
    slug: 'dessau',
    sourceLocationId: 13,
    displayNameDe: 'Mensa Dessau',
    displayNameEn: 'Dessau Canteen',
    campusLabelDe: 'Dessau',
    campusLabelEn: 'Dessau',
    siteKey: 'dessau',
    sortOrder: 30,
    active: true,
  },
  {
    slug: 'bernburg',
    sourceLocationId: 8,
    displayNameDe: 'Mensa Bernburg',
    displayNameEn: 'Bernburg Canteen',
    campusLabelDe: 'Bernburg',
    campusLabelEn: 'Bernburg',
    siteKey: 'bernburg',
    sortOrder: 40,
    active: true,
  },
] as const;
