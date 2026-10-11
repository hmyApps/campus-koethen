// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { runAsCatalogSync } from '../src/catalog/catalog-scope';
import {
  CATALOG_MANAGED_FIELDS,
  createRoomGuard,
  type GuardContext,
} from '../src/catalog/room-guard';

type Warning = string;

function guardWith() {
  const warnings: Warning[] = [];
  const guard = createRoomGuard({ warn: (message: string) => warnings.push(message) });
  return { guard, warnings };
}

function context(action: GuardContext['action'], data: Record<string, unknown>): GuardContext {
  return { uid: 'api::room.room', action, params: { documentId: 'abc', data } };
}

const FULL_PAYLOAD = {
  roomKey: 'ratke-gebaeude-first-floor-216',
  editorLabel: '216 · Ratke-Gebäude',
  catalogActive: false,
  displayNameDe: 'Großer Hörsaal',
  displayNameEn: 'Large lecture hall',
  descriptionDe: 'Beschreibung',
  isVisible: false,
  contactPersons: [1, 2],
  contactAreas: [3],
};

test('a normal editor update cannot change catalogue managed fields', async () => {
  const { guard } = guardWith();
  const ctx = context('update', { ...FULL_PAYLOAD });
  await guard(ctx, async () => 'done');

  for (const field of CATALOG_MANAGED_FIELDS) {
    assert.ok(
      !(field in (ctx.params.data as Record<string, unknown>)),
      `${field} must be stripped from an editorial update`,
    );
  }
});

test('a normal editor update keeps editorial fields and relations', async () => {
  const { guard } = guardWith();
  const ctx = context('update', { ...FULL_PAYLOAD });
  await guard(ctx, async () => 'done');

  const data = ctx.params.data as Record<string, unknown>;
  assert.equal(data.displayNameDe, 'Großer Hörsaal');
  assert.equal(data.displayNameEn, 'Large lecture hall');
  assert.equal(data.descriptionDe, 'Beschreibung');
  assert.equal(data.isVisible, false);
  assert.deepEqual(data.contactPersons, [1, 2]);
  assert.deepEqual(data.contactAreas, [3]);
});

test('the catalogue sync may write every managed field', async () => {
  const { guard } = guardWith();
  const ctx = context('update', { ...FULL_PAYLOAD });
  await runAsCatalogSync(async () => guard(ctx, async () => 'done'));

  const data = ctx.params.data as Record<string, unknown>;
  assert.equal(data.roomKey, 'ratke-gebaeude-first-floor-216');
  assert.equal(data.editorLabel, '216 · Ratke-Gebäude');
  assert.equal(data.catalogActive, false);
});

test('editors cannot create, clone (admin "Duplicate") or delete rooms', async () => {
  const { guard } = guardWith();
  for (const action of ['create', 'clone', 'delete'] as const) {
    await assert.rejects(
      () => guard(context(action, { roomKey: 'x' }), async () => 'done'),
      /catalogue/i,
      `${action} must be rejected outside the sync`,
    );
  }
});

test('the catalogue sync may create and delete rooms', async () => {
  const { guard } = guardWith();
  for (const action of ['create', 'delete'] as const) {
    const result = await runAsCatalogSync(async () =>
      guard(context(action, { roomKey: 'x' }), async () => 'done'),
    );
    assert.equal(result, 'done');
  }
});

test('other content types are not touched', async () => {
  const { guard } = guardWith();
  const ctx: GuardContext = {
    uid: 'api::contact-area.contact-area',
    action: 'update',
    params: { data: { slug: 'changed' } },
  };
  await guard(ctx, async () => 'done');
  assert.equal((ctx.params.data as Record<string, unknown>).slug, 'changed');
});

test('the warning names the fields but never dumps their values', async () => {
  const { guard, warnings } = guardWith();
  await guard(context('update', { ...FULL_PAYLOAD }), async () => 'done');

  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /roomKey/);
  assert.ok(!warnings[0].includes('216'), 'must not log field values');
  assert.ok(!warnings[0].includes('Großer Hörsaal'), 'must not log editorial content');
});

test('an update that touches nothing managed produces no warning', async () => {
  const { guard, warnings } = guardWith();
  await guard(context('update', { displayNameDe: 'nur redaktionell' }), async () => 'done');
  assert.deepEqual(warnings, []);
});

test('the scope does not leak to unrelated async work', async () => {
  const { guard } = guardWith();
  await runAsCatalogSync(async () => 'inside');

  // Once the scope is left, the guard must be strict again.
  await assert.rejects(
    () => guard(context('create', { roomKey: 'x' }), async () => 'done'),
    /catalogue/i,
  );
});
