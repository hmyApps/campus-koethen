// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildOutputs, generatedFileDrift } from '../src/generate.mjs';
import { findRooms, findUnsafe, parseSvgDocument, walkElements } from '../src/svg-reader.mjs';
import { loadCanonical } from '../src/validate.mjs';

function outputs() {
  const { catalog, documents, problems } = loadCanonical();
  assert.deepEqual(problems, [], problems.join('\n'));
  return { files: buildOutputs(catalog, documents), catalog };
}

const MOBILE_CATALOG = 'apps/mobile/assets/maps/map_catalog.json';
const MOBILE_RATKE_GROUND = 'apps/mobile/assets/maps/ratke-gebaeude/ground-floor.svg';
const MOBILE_RATKE_FIRST = 'apps/mobile/assets/maps/ratke-gebaeude/first-floor.svg';
const MOBILE_NEW_BUILDING_FLOORS = [
  'apps/mobile/assets/maps/koethen-01/basement.svg',
  'apps/mobile/assets/maps/koethen-01/first-floor.svg',
  'apps/mobile/assets/maps/koethen-01/second-floor.svg',
  'apps/mobile/assets/maps/koethen-01/third-floor.svg',
  'apps/mobile/assets/maps/koethen-01/roof.svg',
  'apps/mobile/assets/maps/koethen-02/basement.svg',
  'apps/mobile/assets/maps/koethen-02/ground-floor.svg',
  'apps/mobile/assets/maps/koethen-02/first-floor.svg',
  'apps/mobile/assets/maps/koethen-02/second-floor.svg',
  'apps/mobile/assets/maps/koethen-03/ground-floor.svg',
  'apps/mobile/assets/maps/koethen-03/first-floor.svg',
  'apps/mobile/assets/maps/koethen-03/second-floor.svg',
];
const MOBILE_SVG = MOBILE_RATKE_FIRST;

function roomPresentation(root) {
  const byKey = new Map();
  function visit(node, inherited = {}) {
    if (node?.type !== 'element') return;
    const presentation = {
      fill: node.attrs?.fill ?? inherited.fill,
      stroke: node.attrs?.stroke ?? inherited.stroke,
    };
    const roomKey = node.attrs?.['data-room-key'];
    if (roomKey) byKey.set(roomKey, presentation);
    for (const child of node.children ?? []) visit(child, presentation);
  }
  visit(root);
  return byKey;
}

test('emits exactly the expected generated files', () => {
  const { files } = outputs();
  assert.deepEqual(
    [...files.keys()].sort(),
    [MOBILE_CATALOG, MOBILE_RATKE_GROUND, MOBILE_RATKE_FIRST, ...MOBILE_NEW_BUILDING_FLOORS].sort(),
  );
});

test('generation is deterministic', () => {
  const a = outputs().files;
  const b = outputs().files;
  for (const [path, content] of a) {
    assert.equal(content, b.get(path), `${path} is not reproducible`);
  }
});

test('the mobile catalogue carries the mapping Flutter needs', () => {
  const { files, catalog } = outputs();
  const mobile = JSON.parse(files.get(MOBILE_CATALOG));

  assert.equal(mobile.mapVersion, catalog.mapVersion);
  assert.equal(mobile.schemaVersion, catalog.schemaVersion);
  assert.equal(mobile.rooms.length, 292);
  assert.equal(mobile.floors.length, 14);
  assert.equal(mobile.buildings.length, 4);

  const ratke = mobile.buildings.find((building) => building.buildingKey === 'ratke-gebaeude');
  assert.equal(ratke.buildingNumber, '23');
  assert.equal(ratke.nameDe, 'Ratke-Gebäude');
  assert.equal(ratke.nameEn, 'Ratke Building');
  assert.equal(ratke.planKind, 'schematic');
  assert.equal(ratke.sourceAttributionDe, 'Hochschule Anhalt');
  assert.equal(ratke.sourceAttributionEn, 'Hochschule Anhalt');

  for (const [key, number, nameDe, nameEn] of [
    ['koethen-01', '01', 'Rotes Gebäude', 'Red Building'],
    ['koethen-02', '02', 'Grünes Gebäude', 'Green Building'],
    ['koethen-03', '03', 'Weißes Gebäude', 'White Building'],
  ]) {
    const building = mobile.buildings.find((candidate) => candidate.buildingKey === key);
    assert.ok(building, `${key} must be present`);
    assert.equal(building.buildingNumber, number);
    assert.equal(building.nameDe, nameDe);
    assert.equal(building.nameEn, nameEn);
    assert.equal(building.planKind, 'schematic');
    assert.equal(building.sourceAttributionDe, 'Hochschule Anhalt');
    assert.equal(building.sourceAttributionEn, 'Hochschule Anhalt');
  }

  const ratkeRoom = mobile.rooms.find(
    (candidate) => candidate.roomKey === 'ratke-gebaeude-ground-floor-101',
  );
  assert.ok(ratkeRoom, 'Ratke room 101 must be present');
  assert.equal(ratkeRoom.roomType, 'room');
  assert.equal(ratkeRoom.floorKey, 'ratke-gebaeude-ground-floor');

  const room = mobile.rooms.find((r) => r.roomNumber === '216');
  assert.ok(room, 'Ratke room 216 must be present');
  assert.equal(room.roomKey, 'ratke-gebaeude-first-floor-216');
  assert.equal(room.floorKey, 'ratke-gebaeude-first-floor');
  assert.equal(room.roomType, 'lecture');
  assert.ok(Number.isFinite(room.focus.x) && Number.isFinite(room.focus.y));
  assert.ok(room.bounds.width > 0 && room.bounds.height > 0);

  const basementRoom = mobile.rooms.find(
    (candidate) => candidate.roomKey === 'koethen-02-basement-minus-1-01',
  );
  assert.ok(basementRoom, 'Green Building basement room -1.01 must be present');
  assert.equal(basementRoom.roomNumber, '-1.01');
  assert.equal(basementRoom.floorKey, 'koethen-02-basement');
  assert.ok(basementRoom.bounds.width > 0 && basementRoom.bounds.height > 0);
});

test('the new buildings keep their approved floor order and names', () => {
  const { files } = outputs();
  const mobile = JSON.parse(files.get(MOBILE_CATALOG));

  assert.deepEqual(
    mobile.floors
      .filter((floor) => floor.buildingKey === 'koethen-01')
      .map((floor) => [floor.floorKey, floor.nameDe]),
    [
      ['koethen-01-basement', 'Kellergeschoss'],
      ['koethen-01-first-floor', '1. Obergeschoss'],
      ['koethen-01-second-floor', '2. Obergeschoss'],
      ['koethen-01-third-floor', '3. Obergeschoss'],
      ['koethen-01-roof', 'Dachgeschoss'],
    ],
  );
  assert.deepEqual(
    mobile.floors
      .filter((floor) => floor.buildingKey === 'koethen-03')
      .map((floor) => [floor.floorKey, floor.nameDe]),
    [
      ['koethen-03-ground-floor', 'Erdgeschoss'],
      ['koethen-03-first-floor', '1. Obergeschoss'],
      ['koethen-03-second-floor', '2. Obergeschoss'],
    ],
  );
  assert.deepEqual(
    mobile.floors
      .filter((floor) => floor.buildingKey === 'koethen-02')
      .map((floor) => [floor.floorKey, floor.nameDe]),
    [
      ['koethen-02-basement', 'Kellergeschoss'],
      ['koethen-02-ground-floor', 'Erdgeschoss'],
      ['koethen-02-first-floor', '1. Obergeschoss'],
      ['koethen-02-second-floor', '2. Obergeschoss'],
    ],
  );
});

test('the Ratke building lists ground floor before first floor', () => {
  const { files } = outputs();
  const mobile = JSON.parse(files.get(MOBILE_CATALOG));
  const floors = mobile.floors.filter((floor) => floor.buildingKey === 'ratke-gebaeude');
  assert.deepEqual(
    floors.map((floor) => floor.floorKey),
    ['ratke-gebaeude-ground-floor', 'ratke-gebaeude-first-floor'],
  );
  assert.deepEqual(
    floors.map((floor) => floor.svgAsset),
    ['assets/maps/ratke-gebaeude/ground-floor.svg', 'assets/maps/ratke-gebaeude/first-floor.svg'],
  );
});

test('the mobile catalogue carries building and floor names, but no room prose', () => {
  const { files } = outputs();
  const mobile = JSON.parse(files.get(MOBILE_CATALOG));

  // Building and floor names are bundled on purpose. They name the map's own
  // navigation and keep the picker translated without a network round-trip.
  for (const building of mobile.buildings) {
    assert.ok(building.nameDe.length > 0, `${building.buildingKey} is missing nameDe`);
    assert.ok(building.nameEn.length > 0, `${building.buildingKey} is missing nameEn`);
  }
  for (const floor of mobile.floors) {
    assert.ok(floor.nameDe.length > 0, `${floor.floorKey} is missing nameDe`);
    assert.ok(floor.nameEn.length > 0, `${floor.floorKey} is missing nameEn`);
  }

  assert.equal(
    mobile.buildings.find((b) => b.buildingKey === 'ratke-gebaeude').planKind,
    'schematic',
  );

  // Room-level prose stays with the Campus API, which serves it per locale and
  // lets the editorial team change it without an app release.
  for (const room of mobile.rooms) {
    for (const forbidden of ['displayName', 'description', 'nameDe', 'nameEn']) {
      assert.ok(!(forbidden in room), `room ${room.roomKey} must not carry ${forbidden}`);
    }
  }
});

test('the mobile SVG keeps every room element and its geometry', () => {
  const { files } = outputs();
  const root = parseSvgDocument(files.get(MOBILE_SVG));
  const rooms = findRooms(root);
  assert.equal(rooms.length, 30);
  assert.equal(new Set(rooms.map((r) => r.attrs['data-room-key'])).size, 30);
  for (const room of rooms) {
    assert.ok(room.attrs.id.startsWith('room-'));
    assert.ok(Number.isFinite(Number(room.attrs.width)));
  }
});

test('the mobile floor plans keep their German labels and legends', () => {
  const { files } = outputs();
  const ratkeGround = files.get(MOBILE_RATKE_GROUND);
  const redBasement = files.get('apps/mobile/assets/maps/koethen-01/basement.svg');

  for (const label of ['Erdgeschoss', 'Mensa', 'Haupteingang', 'Raum', 'Sanitär']) {
    assert.ok(ratkeGround.includes(`>${label}<`), `Ratke plan is missing "${label}"`);
  }
  for (const label of ['Kellergeschoss', 'Innenhof', 'Werkstatt', 'Treppe / Technik']) {
    assert.ok(redBasement.includes(`>${label}<`), `Building 01 plan is missing "${label}"`);
  }
});

test('the Ratke assets keep every approved room', () => {
  const { files, catalog } = outputs();
  const cases = [
    [MOBILE_RATKE_GROUND, 'ratke-gebaeude-ground-floor', 28],
    [MOBILE_RATKE_FIRST, 'ratke-gebaeude-first-floor', 30],
  ];
  for (const [asset, floorKey, count] of cases) {
    const root = parseSvgDocument(files.get(asset));
    const rooms = findRooms(root);
    assert.equal(rooms.length, count);
    assert.equal(new Set(rooms.map((room) => room.attrs['data-room-key'])).size, count);
    assert.equal(catalog.rooms.filter((room) => room.floorKey === floorKey).length, count);
  }
});

test('the new building assets keep every approved room and supported SVG constructs', () => {
  const { files, catalog } = outputs();
  const floors = catalog.floors.filter(
    (floor) =>
      floor.buildingKey === 'koethen-01' ||
      floor.buildingKey === 'koethen-02' ||
      floor.buildingKey === 'koethen-03',
  );

  for (const floor of floors) {
    const asset = `apps/mobile/assets/maps/${floor.svgPath.replace(/^buildings\//, '')}`;
    const root = parseSvgDocument(files.get(asset));
    const rooms = findRooms(root);
    assert.equal(rooms.length, floor.expectedRoomCount, `${floor.floorKey} room count`);
    assert.equal(
      new Set(rooms.map((room) => room.attrs['data-room-key'])).size,
      floor.expectedRoomCount,
      `${floor.floorKey} room keys`,
    );

    for (const element of walkElements(root)) {
      assert.ok(!['title', 'desc', 'style'].includes(element.name));
    }
  }
});

test('the mobile SVG has no dangling references to stripped prose nodes', () => {
  const { files } = outputs();
  const root = parseSvgDocument(files.get(MOBILE_SVG));
  const ids = new Set();
  for (const element of walkElements(root)) {
    if (element.attrs?.id) ids.add(element.attrs.id);
  }
  for (const element of walkElements(root)) {
    for (const attr of ['aria-labelledby', 'aria-describedby']) {
      const value = element.attrs?.[attr];
      if (!value) continue;
      for (const reference of String(value).split(/\s+/).filter(Boolean)) {
        assert.ok(ids.has(reference), `${attr} points at removed node "${reference}"`);
      }
    }
  }
});

test('the mobile SVG carries no construct the Flutter renderer ignores', () => {
  // flutter_svg's compiler reports "unhandled element <style/>" and drops the
  // whole stylesheet, which would leave every room unstyled. Styles are
  // therefore resolved into presentation attributes at generation time, and
  // markers — also unsupported — are removed with their references.
  const { files } = outputs();
  const root = parseSvgDocument(files.get(MOBILE_SVG));

  for (const element of walkElements(root)) {
    assert.notEqual(element.name, 'style', '<style> is not supported by the renderer');
    assert.notEqual(element.name, 'marker', '<marker> is not supported by the renderer');
    for (const attr of Object.keys(element.attrs ?? {})) {
      assert.ok(!attr.startsWith('marker-'), `${attr} references an unsupported marker`);
    }
  }
});

test('every room rectangle has an effective fill and stroke', () => {
  const { files } = outputs();
  const root = parseSvgDocument(files.get(MOBILE_SVG));
  const presentation = roomPresentation(root);
  for (const room of findRooms(root)) {
    const effective = presentation.get(room.attrs['data-room-key']);
    assert.match(
      String(effective?.fill ?? ''),
      /^#[0-9a-f]{6}$/i,
      `room ${room.attrs['data-room-key']} must have an effective fill`,
    );
    assert.ok(
      effective?.stroke,
      `room ${room.attrs['data-room-key']} must have an effective stroke`,
    );
  }
});

test('room types keep their distinct inlined colours', () => {
  const { files, catalog } = outputs();
  const root = parseSvgDocument(files.get(MOBILE_SVG));
  const byKey = new Map(catalog.rooms.map((r) => [r.roomKey, r]));
  const presentation = roomPresentation(root);

  const fillByType = new Map();
  for (const element of findRooms(root)) {
    const type = byKey.get(element.attrs['data-room-key']).roomType;
    fillByType.set(type, presentation.get(element.attrs['data-room-key']).fill);
  }

  // lecture and neutral rooms are visibly different in the canonical stylesheet; if
  // the cascade were applied wrongly they would collapse onto one colour.
  assert.equal(fillByType.get('lecture').toLowerCase(), '#f8e3bf');
  assert.equal(fillByType.get('room').toLowerCase(), '#e5def5');
  assert.notEqual(fillByType.get('lecture'), fillByType.get('room'));
});

test('the mobile SVG is safe and self-contained', () => {
  const { files } = outputs();
  const svg = files.get(MOBILE_SVG);
  assert.deepEqual(findUnsafe(parseSvgDocument(svg)), []);
  assert.ok(!/https?:\/\//.test(svg.replace(/xmlns="[^"]*"/g, '')));
});

test('an invalid catalogue produces no files at all', () => {
  const { catalog, documents } = loadCanonical();
  const broken = structuredClone(catalog);
  broken.rooms[0].roomKey = 'not-in-any-svg';
  assert.throws(() => buildOutputs(broken, documents), /roomKey|SVG element/i);
});

// --- drift ------------------------------------------------------------------

test('drift check passes for the committed generated assets', () => {
  const drift = generatedFileDrift();
  assert.deepEqual(drift, [], `generated assets are stale:\n${drift.join('\n')}`);
});

test('drift check ignores checkout-only CRLF conversion', () => {
  const { files } = outputs();
  const drift = generatedFileDrift({
    readFile: (path) => files.get(path)?.replaceAll('\n', '\r\n'),
  });
  assert.deepEqual(drift, []);
});

test('drift check reports a tampered generated asset', () => {
  const drift = generatedFileDrift({
    readFile: (path) => (path.endsWith('.svg') ? '<svg/>' : undefined),
  });
  assert.ok(drift.length > 0);
});
