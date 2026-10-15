// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/**
 * Cross-checks the canonical catalogue against the canonical SVG files.
 *
 * The SVG is the GEOMETRY source, the catalogue is the STRUCTURED technical
 * source, and neither is allowed to drift from the other. Every rule here
 * exists because the failure it prevents would otherwise only show up in the
 * app: a room that cannot be focused, a highlight that lands on the wrong
 * shape, or an asset carrying something that must never be bundled.
 *
 * Everything is a pure function over data so it is testable without any disk
 * access; only `loadCanonical` touches the file system.
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { SvgParseError, findRooms, findUnsafe, parseSvgDocument } from './svg-reader.mjs';

export const PACKAGE_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const CATALOG_PATH = join(PACKAGE_ROOT, 'catalog', 'campus-map.catalog.json');

/** Stable technical vocabulary. Localisation happens in Flutter, never here. */
export const ROOM_TYPES = Object.freeze([
  'room',
  'lecture',
  'seminar',
  'office',
  'lab',
  'meeting',
  'service',
]);

/**
 * What kind of drawing a building's plan is — a claim the app makes VISIBLE, so
 * it belongs in the catalogue rather than in a widget.
 *
 * `schematic`: a simplified, not-to-scale overview of a real site. It is not a
 *              fire, escape or rescue plan and must never be labelled as one.
 *
 * The app picks its notice from this value, so a new building can never
 * silently inherit the wrong claim.
 */
export const PLAN_KINDS = Object.freeze(['schematic']);

/** The campus sites of Hochschule Anhalt this app covers. */
export const SITE_KEYS = Object.freeze(['koethen', 'bernburg', 'dessau']);

const SUPPORTED_SCHEMA_VERSION = 1;
const KEY_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function checkStructure(catalog, problems) {
  if (catalog?.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
    problems.push(
      `schemaVersion must be ${SUPPORTED_SCHEMA_VERSION}, found ${String(catalog?.schemaVersion)}`,
    );
    return false;
  }
  if (typeof catalog.mapVersion !== 'string' || catalog.mapVersion.length === 0) {
    problems.push('mapVersion must be a non-empty string');
  }
  for (const collection of ['buildings', 'floors', 'rooms']) {
    if (!Array.isArray(catalog[collection])) {
      problems.push(`${collection} must be an array`);
      return false;
    }
  }
  return true;
}

function checkKeys(catalog, problems) {
  const seen = { buildings: new Set(), floors: new Set(), rooms: new Set() };
  const seenBuildingNumbers = new Set();
  const roomBuildingKeys = new Set(catalog.rooms.map((room) => room.buildingKey));

  for (const building of catalog.buildings) {
    if (!KEY_PATTERN.test(building.buildingKey ?? '')) {
      problems.push(`invalid buildingKey "${building.buildingKey}"`);
    }
    if (seen.buildings.has(building.buildingKey)) {
      problems.push(`duplicate buildingKey "${building.buildingKey}"`);
    }
    seen.buildings.add(building.buildingKey);
    if (
      roomBuildingKeys.has(building.buildingKey) &&
      (typeof building.buildingNumber !== 'string' || building.buildingNumber.trim().length === 0)
    ) {
      problems.push(`building "${building.buildingKey}" with rooms is missing buildingNumber`);
    } else if (
      'buildingNumber' in building &&
      (typeof building.buildingNumber !== 'string' || building.buildingNumber.trim().length === 0)
    ) {
      problems.push(`building "${building.buildingKey}" has an invalid buildingNumber`);
    }
    if (typeof building.buildingNumber === 'string' && building.buildingNumber.trim().length > 0) {
      const buildingNumber = building.buildingNumber.trim();
      if (seenBuildingNumbers.has(buildingNumber)) {
        problems.push(`duplicate buildingNumber "${buildingNumber}"`);
      }
      seenBuildingNumbers.add(buildingNumber);
    }
    for (const field of ['nameDe', 'nameEn']) {
      if (typeof building[field] !== 'string' || building[field].length === 0) {
        problems.push(`building "${building.buildingKey}" is missing ${field}`);
      }
    }
    const hasSourceDe = typeof building.sourceAttributionDe === 'string';
    const hasSourceEn = typeof building.sourceAttributionEn === 'string';
    if (hasSourceDe !== hasSourceEn) {
      problems.push(
        `building "${building.buildingKey}" must provide both sourceAttributionDe and sourceAttributionEn`,
      );
    }
    for (const field of ['sourceAttributionDe', 'sourceAttributionEn']) {
      if (
        field in building &&
        (typeof building[field] !== 'string' || building[field].length === 0)
      ) {
        problems.push(`building "${building.buildingKey}" has an invalid ${field}`);
      }
    }
    if (!SITE_KEYS.includes(building.siteKey)) {
      problems.push(
        `building "${building.buildingKey}" has an unsupported siteKey "${building.siteKey}"`,
      );
    }
    if (!PLAN_KINDS.includes(building.planKind)) {
      problems.push(
        `building "${building.buildingKey}" has an unsupported planKind "${building.planKind}"`,
      );
    }
  }

  for (const floor of catalog.floors) {
    if (!KEY_PATTERN.test(floor.floorKey ?? '')) {
      problems.push(`invalid floorKey "${floor.floorKey}"`);
    }
    if (seen.floors.has(floor.floorKey)) {
      problems.push(`duplicate floorKey "${floor.floorKey}"`);
    }
    seen.floors.add(floor.floorKey);
    if (!seen.buildings.has(floor.buildingKey)) {
      problems.push(
        `floor "${floor.floorKey}" references unknown buildingKey "${floor.buildingKey}"`,
      );
    }
    if (!Number.isInteger(floor.level)) {
      problems.push(`floor "${floor.floorKey}" needs an integer level`);
    }
    for (const field of ['nameDe', 'nameEn', 'svgPath']) {
      if (typeof floor[field] !== 'string' || floor[field].length === 0) {
        problems.push(`floor "${floor.floorKey}" is missing ${field}`);
      }
    }
    const box = floor.viewBox;
    if (
      !box ||
      !isFiniteNumber(box.minX) ||
      !isFiniteNumber(box.minY) ||
      !(box.width > 0) ||
      !(box.height > 0)
    ) {
      problems.push(`floor "${floor.floorKey}" has an invalid viewBox`);
    }
    if (!Number.isInteger(floor.expectedRoomCount) || floor.expectedRoomCount < 0) {
      problems.push(`floor "${floor.floorKey}" needs an integer expectedRoomCount`);
    }
  }

  for (const room of catalog.rooms) {
    if (!KEY_PATTERN.test(room.roomKey ?? '')) {
      problems.push(`invalid roomKey "${room.roomKey}"`);
    }
    if (seen.rooms.has(room.roomKey)) {
      problems.push(`duplicate roomKey "${room.roomKey}"`);
    }
    seen.rooms.add(room.roomKey);
    if (!seen.buildings.has(room.buildingKey)) {
      problems.push(`room "${room.roomKey}" references unknown buildingKey "${room.buildingKey}"`);
    }
    if (!seen.floors.has(room.floorKey)) {
      problems.push(`room "${room.roomKey}" references unknown floorKey "${room.floorKey}"`);
    }
    if (!ROOM_TYPES.includes(room.roomType)) {
      problems.push(`room "${room.roomKey}" has an unsupported roomType "${room.roomType}"`);
    }
    if (typeof room.roomNumber !== 'string' || room.roomNumber.length === 0) {
      problems.push(`room "${room.roomKey}" is missing roomNumber`);
    }
    if (typeof room.svgElementId !== 'string' || room.svgElementId.length === 0) {
      problems.push(`room "${room.roomKey}" is missing svgElementId`);
    }
    if (!isFiniteNumber(room.focus?.x) || !isFiniteNumber(room.focus?.y)) {
      problems.push(`room "${room.roomKey}" has invalid focus coordinates`);
    }
    const b = room.bounds;
    if (!b || !isFiniteNumber(b.x) || !isFiniteNumber(b.y) || !(b.width > 0) || !(b.height > 0)) {
      problems.push(`room "${room.roomKey}" has invalid bounds`);
    }
    if (!Number.isInteger(room.sortOrder)) {
      problems.push(`room "${room.roomKey}" needs an integer sortOrder`);
    }
  }
}

/** A focus point or a room rectangle outside the plan can never be shown. */
function checkGeometry(floor, rooms, problems) {
  const box = floor.viewBox;
  if (!box) return;
  const maxX = box.minX + box.width;
  const maxY = box.minY + box.height;

  for (const room of rooms) {
    const { focus, bounds } = room;
    if (
      isFiniteNumber(focus?.x) &&
      isFiniteNumber(focus?.y) &&
      (focus.x < box.minX || focus.x > maxX || focus.y < box.minY || focus.y > maxY)
    ) {
      problems.push(
        `room "${room.roomKey}" has a focus point outside the viewBox of floor "${floor.floorKey}"`,
      );
    }
    if (
      bounds &&
      isFiniteNumber(bounds.x) &&
      isFiniteNumber(bounds.y) &&
      bounds.width > 0 &&
      bounds.height > 0 &&
      (bounds.x < box.minX ||
        bounds.y < box.minY ||
        bounds.x + bounds.width > maxX ||
        bounds.y + bounds.height > maxY)
    ) {
      problems.push(
        `room "${room.roomKey}" has bounds outside the viewBox of floor "${floor.floorKey}"`,
      );
    }
  }
}

function checkFloorSvg(floor, rooms, svgText, problems) {
  if (typeof svgText !== 'string' || svgText.length === 0) {
    problems.push(`floor "${floor.floorKey}": SVG "${floor.svgPath}" could not be read`);
    return null;
  }

  let root;
  try {
    root = parseSvgDocument(svgText);
  } catch (error) {
    const detail = error instanceof SvgParseError ? error.message : 'unreadable';
    problems.push(`floor "${floor.floorKey}": ${floor.svgPath} is not valid XML — ${detail}`);
    return null;
  }

  for (const problem of findUnsafe(root)) {
    problems.push(`floor "${floor.floorKey}": ${problem}`);
  }

  const declared = String(root.attrs?.viewBox ?? '')
    .trim()
    .split(/\s+/)
    .map(Number);
  const box = floor.viewBox;
  if (
    box &&
    (declared.length !== 4 ||
      declared[0] !== box.minX ||
      declared[1] !== box.minY ||
      declared[2] !== box.width ||
      declared[3] !== box.height)
  ) {
    problems.push(
      `floor "${floor.floorKey}": catalogue viewBox does not match the viewBox in ${floor.svgPath}`,
    );
  }

  const svgRooms = findRooms(root);
  const byKey = new Map(rooms.map((room) => [room.roomKey, room]));
  const svgKeys = new Set();

  for (const element of svgRooms) {
    const key = element.attrs['data-room-key'];
    if (svgKeys.has(key)) {
      problems.push(`floor "${floor.floorKey}": duplicate roomKey "${key}" in ${floor.svgPath}`);
    }
    svgKeys.add(key);

    const room = byKey.get(key);
    if (!room) {
      problems.push(`floor "${floor.floorKey}": SVG room "${key}" is not in the catalogue`);
      continue;
    }
    if (element.attrs.id !== room.svgElementId) {
      problems.push(
        `room "${key}": svgElementId "${room.svgElementId}" does not match SVG id "${element.attrs.id}"`,
      );
    }
    if (element.attrs['data-building-key'] !== room.buildingKey) {
      problems.push(`room "${key}": data-building-key does not match the catalogue`);
    }
    if (element.attrs['data-floor-key'] !== room.floorKey) {
      problems.push(`room "${key}": data-floor-key does not match the catalogue`);
    }
    if (element.attrs['data-room-number'] !== room.roomNumber) {
      problems.push(`room "${key}": data-room-number does not match the catalogue`);
    }
    if (Number(element.attrs['data-focus-x']) !== room.focus?.x) {
      problems.push(`room "${key}": data-focus-x does not match the catalogue`);
    }
    if (Number(element.attrs['data-focus-y']) !== room.focus?.y) {
      problems.push(`room "${key}": data-focus-y does not match the catalogue`);
    }
  }

  for (const room of rooms) {
    if (!svgKeys.has(room.roomKey)) {
      problems.push(`room "${room.roomKey}" has no SVG element in ${floor.svgPath}`);
    }
  }

  if (Number.isInteger(floor.expectedRoomCount) && svgKeys.size !== floor.expectedRoomCount) {
    problems.push(
      `floor "${floor.floorKey}": expected ${floor.expectedRoomCount} rooms, found ${svgKeys.size}`,
    );
  }

  return root;
}

/**
 * Validates a catalogue against its SVG files.
 *
 * `readSvg(svgPath)` returns the file contents, so callers decide whether that
 * comes from disk or from memory.
 */
export function validate(catalog, readSvg) {
  const problems = [];
  const documents = new Map();

  if (!checkStructure(catalog, problems)) {
    return { problems, documents };
  }
  checkKeys(catalog, problems);

  for (const floor of catalog.floors) {
    const rooms = catalog.rooms.filter((room) => room.floorKey === floor.floorKey);
    checkGeometry(floor, rooms, problems);
    const root = checkFloorSvg(floor, rooms, readSvg(floor.svgPath), problems);
    if (root) documents.set(floor.floorKey, root);
  }

  return { problems, documents };
}

/** Loads and validates the committed canonical catalogue from disk. */
export function loadCanonical(packageRoot = PACKAGE_ROOT) {
  const catalogPath = join(packageRoot, 'catalog', 'campus-map.catalog.json');
  const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
  const readSvg = (svgPath) => {
    try {
      return readFileSync(join(packageRoot, svgPath), 'utf8');
    } catch {
      return undefined;
    }
  };
  const { problems, documents } = validate(catalog, readSvg);
  return { catalog, problems, documents, readSvg };
}
