// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { loadCanonical, SITE_KEYS, validate } from '../src/validate.mjs';

/** A tiny self-contained world: one building, one floor, two rooms. */
function fixture() {
  const catalog = {
    schemaVersion: 1,
    mapVersion: 'test-1',
    notice: 'schematic',
    buildings: [
      {
        buildingKey: 'b',
        buildingNumber: '23',
        nameDe: 'B',
        nameEn: 'B',
        planKind: 'schematic',
        siteKey: 'koethen',
        sortOrder: 10,
      },
    ],
    floors: [
      {
        floorKey: 'b-l1',
        buildingKey: 'b',
        level: 1,
        nameDe: 'EG',
        nameEn: 'Ground floor',
        svgPath: 'b/l1.svg',
        viewBox: { minX: 0, minY: 0, width: 100, height: 100 },
        expectedRoomCount: 2,
        sortOrder: 10,
      },
    ],
    rooms: [room('r1', 'R.1', 10), room('r2', 'R.2', 20)],
  };
  return { catalog, svgs: { 'b/l1.svg': svgFor(catalog.rooms) } };
}

function room(key, number, sortOrder) {
  return {
    roomKey: key,
    roomNumber: number,
    buildingKey: 'b',
    floorKey: 'b-l1',
    roomType: 'office',
    svgElementId: `room-${key}`,
    focus: { x: 10, y: 10 },
    bounds: { x: 5, y: 5, width: 10, height: 10 },
    sortOrder,
  };
}

function svgFor(rooms, overrides = {}) {
  const rects = rooms
    .map((r) => {
      const id = overrides[r.roomKey]?.id ?? r.svgElementId;
      const dataKey = overrides[r.roomKey]?.dataKey ?? r.roomKey;
      return `<rect id="${id}" class="room office" x="${r.bounds.x}" y="${r.bounds.y}" width="${r.bounds.width}" height="${r.bounds.height}" data-room-key="${dataKey}" data-room-number="${r.roomNumber}" data-building-key="${r.buildingKey}" data-floor-key="${r.floorKey}" data-focus-x="${r.focus.x}" data-focus-y="${r.focus.y}" />`;
    })
    .join('\n');
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g id="floor-plan">\n${rects}\n</g></svg>`;
}

const run = ({ catalog, svgs }) => validate(catalog, (path) => svgs[path]);

test('a consistent catalogue and SVG produce no problems', () => {
  assert.deepEqual(run(fixture()).problems, []);
});

test('rejects a duplicated roomKey', () => {
  const f = fixture();
  f.catalog.rooms[1].roomKey = 'r1';
  f.svgs['b/l1.svg'] = svgFor(f.catalog.rooms);
  assert.match(run(f).problems.join('\n'), /duplicate roomKey/i);
});

test('rejects a catalogue room that has no SVG element', () => {
  const f = fixture();
  f.catalog.rooms.push(room('r3', 'R.3', 30));
  f.catalog.floors[0].expectedRoomCount = 3;
  assert.match(run(f).problems.join('\n'), /no SVG element/i);
});

test('rejects an SVG room that is missing from the catalogue', () => {
  const f = fixture();
  f.svgs['b/l1.svg'] = svgFor([...f.catalog.rooms, room('ghost', 'R.9', 90)]);
  assert.match(run(f).problems.join('\n'), /not in the catalogue/i);
});

test('rejects a mismatch between roomKey and the SVG element id', () => {
  const f = fixture();
  f.svgs['b/l1.svg'] = svgFor(f.catalog.rooms, { r1: { id: 'room-somethingelse' } });
  assert.match(run(f).problems.join('\n'), /svgElementId/i);
});

test('rejects a mismatch between roomKey and data-room-key', () => {
  const f = fixture();
  f.svgs['b/l1.svg'] = svgFor(f.catalog.rooms, { r1: { dataKey: 'r9' } });
  assert.match(run(f).problems.join('\n'), /not in the catalogue|data-room-key/i);
});

test('rejects an unknown building reference', () => {
  const f = fixture();
  f.catalog.rooms[0].buildingKey = 'nope';
  assert.match(run(f).problems.join('\n'), /unknown buildingKey/i);
});

test('rejects a room building without a building number', () => {
  const f = fixture();
  delete f.catalog.buildings[0].buildingNumber;
  assert.match(run(f).problems.join('\n'), /buildingNumber/i);
});

test('rejects a duplicated building number', () => {
  const f = fixture();
  f.catalog.buildings.push({
    buildingKey: 'second-building',
    buildingNumber: '23',
    nameDe: 'Zweites Gebäude',
    nameEn: 'Second Building',
    planKind: 'schematic',
    siteKey: 'koethen',
    sortOrder: 20,
  });
  assert.match(run(f).problems.join('\n'), /duplicate buildingNumber/i);
});

test('rejects an unknown floor reference', () => {
  const f = fixture();
  f.catalog.rooms[0].floorKey = 'nope';
  assert.match(run(f).problems.join('\n'), /unknown floorKey/i);
});

test('rejects a focus point outside the viewBox', () => {
  const f = fixture();
  f.catalog.rooms[0].focus = { x: 500, y: 10 };
  f.svgs['b/l1.svg'] = svgFor(f.catalog.rooms);
  assert.match(run(f).problems.join('\n'), /focus/i);
});

test('rejects bounds that leave the viewBox', () => {
  const f = fixture();
  f.catalog.rooms[0].bounds = { x: 95, y: 95, width: 50, height: 50 };
  f.svgs['b/l1.svg'] = svgFor(f.catalog.rooms);
  assert.match(run(f).problems.join('\n'), /bounds/i);
});

test('rejects a room count that differs from the declared expectation', () => {
  const f = fixture();
  f.catalog.floors[0].expectedRoomCount = 3;
  assert.match(run(f).problems.join('\n'), /expected 3 rooms/i);
});

test('rejects unsafe SVG content', () => {
  const f = fixture();
  f.svgs['b/l1.svg'] = f.svgs['b/l1.svg'].replace(
    '<g id="floor-plan">',
    '<script>alert(1)</script><g id="floor-plan">',
  );
  assert.match(run(f).problems.join('\n'), /forbidden element/i);
});

test('rejects an unreadable SVG instead of skipping it', () => {
  const f = fixture();
  f.svgs['b/l1.svg'] = '<svg><g></svg>';
  assert.ok(run(f).problems.length > 0);
});

test('rejects an unknown roomType', () => {
  const f = fixture();
  f.catalog.rooms[0].roomType = 'wellness-area';
  assert.match(run(f).problems.join('\n'), /roomType/i);
});

test('rejects a viewBox that disagrees with the SVG', () => {
  const f = fixture();
  f.catalog.floors[0].viewBox = { minX: 0, minY: 0, width: 999, height: 100 };
  assert.match(run(f).problems.join('\n'), /viewBox/i);
});

// --- the real, committed asset ----------------------------------------------

test('the committed catalogue and its SVGs are consistent', () => {
  const { catalog, problems } = loadCanonical();
  assert.deepEqual(problems, [], problems.join('\n'));

  // Every approved real floor is part of one catalogue. Counting the keys as
  // well is the point: repeated room numbers across buildings and storeys must
  // remain distinguishable instead of colliding in the app.
  assert.equal(catalog.rooms.length, 292);
  assert.equal(new Set(catalog.rooms.map((r) => r.roomKey)).size, 292);

  const expectedFloors = [
    ['ratke-gebaeude-ground-floor', 28],
    ['ratke-gebaeude-first-floor', 30],
    ['koethen-01-basement', 21],
    ['koethen-01-first-floor', 11],
    ['koethen-01-second-floor', 22],
    ['koethen-01-third-floor', 13],
    ['koethen-01-roof', 25],
    ['koethen-02-basement', 31],
    ['koethen-02-ground-floor', 20],
    ['koethen-02-first-floor', 16],
    ['koethen-02-second-floor', 20],
    ['koethen-03-ground-floor', 14],
    ['koethen-03-first-floor', 19],
    ['koethen-03-second-floor', 22],
  ];
  for (const [floorKey, count] of expectedFloors) {
    const floor = catalog.floors.find((f) => f.floorKey === floorKey);
    assert.ok(floor, `${floorKey} is missing`);
    assert.equal(floor.expectedRoomCount, count);
    assert.equal(catalog.rooms.filter((r) => r.floorKey === floorKey).length, count);
  }

  const hall = catalog.rooms.find((room) => room.roomKey === 'ratke-gebaeude-first-floor-216');
  assert.equal(hall?.roomType, 'lecture');
  assert.ok(
    catalog.rooms
      .filter((room) => room.buildingKey === 'ratke-gebaeude' && room.roomNumber !== '216')
      .every((room) => room.roomType === 'room'),
  );

  const ratke = catalog.buildings.find((building) => building.buildingKey === 'ratke-gebaeude');
  assert.equal(ratke?.buildingNumber, '23');
  assert.equal(ratke?.sourceAttributionDe, 'Hochschule Anhalt');
  assert.equal(ratke?.sourceAttributionEn, 'Hochschule Anhalt');

  const redBuilding = catalog.buildings.find((building) => building.buildingKey === 'koethen-01');
  assert.equal(redBuilding?.buildingNumber, '01');
  assert.equal(redBuilding?.nameDe, 'Rotes Gebäude');
  assert.equal(redBuilding?.nameEn, 'Red Building');
  assert.equal(redBuilding?.sourceAttributionDe, 'Hochschule Anhalt');
  assert.equal(redBuilding?.sourceAttributionEn, 'Hochschule Anhalt');

  const greenBuilding = catalog.buildings.find((building) => building.buildingKey === 'koethen-02');
  assert.equal(greenBuilding?.buildingNumber, '02');
  assert.equal(greenBuilding?.nameDe, 'Grünes Gebäude');
  assert.equal(greenBuilding?.nameEn, 'Green Building');
  assert.equal(greenBuilding?.sourceAttributionDe, 'Hochschule Anhalt');
  assert.equal(greenBuilding?.sourceAttributionEn, 'Hochschule Anhalt');

  const whiteBuilding = catalog.buildings.find((building) => building.buildingKey === 'koethen-03');
  assert.equal(whiteBuilding?.buildingNumber, '03');
  assert.equal(whiteBuilding?.nameDe, 'Weißes Gebäude');
  assert.equal(whiteBuilding?.nameEn, 'White Building');
  assert.equal(whiteBuilding?.sourceAttributionDe, 'Hochschule Anhalt');
  assert.equal(whiteBuilding?.sourceAttributionEn, 'Hochschule Anhalt');
});

test('a building needs a supported planKind', () => {
  const { catalog, readSvg } = loadCanonical();
  const broken = structuredClone(catalog);
  broken.buildings[0].planKind = 'photograph';
  const { problems } = validate(broken, readSvg);
  assert.ok(
    problems.some((p) => p.includes('unsupported planKind')),
    'an unknown planKind must be rejected',
  );
});

test('a building needs a supported site', () => {
  const { catalog, readSvg } = loadCanonical();
  for (const bad of [undefined, 'halle', 'Koethen', '']) {
    const broken = structuredClone(catalog);
    broken.buildings[0].siteKey = bad;
    const { problems } = validate(broken, readSvg);
    assert.ok(
      problems.some((p) => p.includes('unsupported siteKey')),
      `siteKey ${JSON.stringify(bad)} must be rejected`,
    );
  }
});

test('Köthen, Bernburg and Dessau are the supported sites', () => {
  assert.deepEqual([...SITE_KEYS], ['koethen', 'bernburg', 'dessau']);
});

test('a building source attribution must be complete in both locales', () => {
  const f = fixture();
  f.catalog.buildings[0].sourceAttributionDe = 'Hochschule Anhalt';
  assert.match(run(f).problems.join('\n'), /sourceAttributionEn/i);
});

test('a floor without rooms is valid', () => {
  const f = fixture();
  f.catalog.floors[0].expectedRoomCount = 0;
  f.catalog.rooms = [];
  f.svgs['b/l1.svg'] = svgFor([]);
  const { problems } = run(f);
  assert.deepEqual(problems, [], 'a room-less floor must not be an error');
});

test('a room-less floor still rejects stray room elements', () => {
  const f = fixture();
  f.catalog.floors[0].expectedRoomCount = 0;
  f.catalog.rooms = [];
  const { problems } = run(f);
  assert.ok(
    problems.some((p) => p.includes('expected 0 rooms, found 2')),
    'the zero expectation must still be enforced',
  );
});
