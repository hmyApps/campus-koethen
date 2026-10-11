// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { Core } from '@strapi/strapi';

import { ensureTags, seedDemoContent } from '../src/bootstrap/seed';

type Record_ = { documentId: string; locale: string; slug?: string } & Record<string, unknown>;

function createFakeStrapi() {
  const store = new Map<string, Record_[]>();
  let nextId = 0;

  function documents(uid: string) {
    if (!store.has(uid)) store.set(uid, []);
    const records = store.get(uid) as Record_[];

    return {
      findMany: async ({
        filters,
        locale,
      }: {
        filters: { slug: { $eq: string } };
        locale: string;
      }) => records.filter((r) => r.locale === locale && r.slug === filters.slug.$eq),
      create: async ({ data, locale }: { data: Record<string, unknown>; locale: string }) => {
        nextId += 1;
        const record: Record_ = { ...data, documentId: `doc-${nextId}`, locale } as Record_;
        records.push(record);
        return record;
      },
      update: async ({
        documentId,
        locale,
        data,
      }: {
        documentId: string;
        locale: string;
        data: Record<string, unknown>;
      }) => {
        let record = records.find((r) => r.documentId === documentId && r.locale === locale);
        if (!record) {
          record = { documentId, locale } as Record_;
          records.push(record);
        }
        Object.assign(record, data);
        return record;
      },
    };
  }

  const strapi = {
    documents,
    log: { info: () => {} },
  } as unknown as Core.Strapi;

  return { strapi, store };
}

test('ensureTags creates exactly the two start tags, in de and en, active by default', async () => {
  const { strapi, store } = createFakeStrapi();

  await ensureTags(strapi);

  const tags = store.get('api::tag.tag') ?? [];
  const deSlugs = new Set(tags.filter((t) => t.locale === 'de').map((t) => t.slug));

  assert.deepEqual([...deSlugs].sort(), ['event', 'news']);
  assert.equal(tags.length, 4, 'two tags × two locales (de, en)');
  for (const tag of tags.filter((t) => t.locale === 'de')) {
    assert.equal(tag.isActive, true);
  }
});

test('seeding twice is idempotent: same slugs are updated, not duplicated', async () => {
  const { strapi, store } = createFakeStrapi();

  await seedDemoContent({ strapi });
  const afterFirst = [...(store.get('api::tag.tag') ?? [])];

  await seedDemoContent({ strapi });
  const afterSecond = store.get('api::tag.tag') ?? [];

  assert.equal(afterSecond.length, afterFirst.length, 'a second run must not duplicate tags');
  assert.deepEqual(
    afterSecond.map((t) => t.documentId).sort(),
    afterFirst.map((t) => t.documentId).sort(),
    'the same documentIds are reused, i.e. updated in place',
  );
});

test('re-seeding does not touch unrelated channels or contact areas destructively', async () => {
  const { strapi, store } = createFakeStrapi();

  await seedDemoContent({ strapi });
  await seedDemoContent({ strapi });

  const channels = store.get('api::channel.channel') ?? [];
  const areas = store.get('api::contact-area.contact-area') ?? [];

  assert.equal(channels.length, 4, 'two channels × two locales, unaffected by tag seeding');
  assert.equal(areas.length, 6, 'three areas × two locales, unaffected by tag seeding');
});

test('ensureTags never overwrites or republishes an existing, editorially changed tag', async () => {
  const { strapi, store } = createFakeStrapi();

  await ensureTags(strapi);
  const tags = store.get('api::tag.tag') ?? [];
  for (const tag of tags) {
    tag.name = `edited-${tag.locale}`;
    tag.isActive = false;
  }
  const snapshot = tags.map((t) => ({ ...t }));

  let writes = 0;
  const originalDocuments = strapi.documents;
  (strapi as unknown as { documents: unknown }).documents = (uid: string) => {
    const api = (originalDocuments as unknown as (u: string) => Record<string, unknown>)(uid);
    return {
      ...api,
      create: async (...args: unknown[]) => {
        writes += 1;
        return (api.create as (...a: unknown[]) => unknown)(...args);
      },
      update: async (...args: unknown[]) => {
        writes += 1;
        return (api.update as (...a: unknown[]) => unknown)(...args);
      },
    };
  };

  await ensureTags(strapi);

  assert.equal(writes, 0, 'a boot must not write to tags that already exist');
  assert.deepEqual(store.get('api::tag.tag'), snapshot);
});
