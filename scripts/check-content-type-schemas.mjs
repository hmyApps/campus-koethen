#!/usr/bin/env node
// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/**
 * Content-type schemas are valid JSON and keep slugs non-localised.
 *
 * A slug that becomes localised would let the stable identifier diverge per
 * locale and silently break the app's channel subscriptions, so it must stay
 * `i18n.localized = false` and `unique`.
 *
 * Node rather than Python: the CI image ships no python3, and this keeps the
 * check runnable with `node scripts/check-content-type-schemas.mjs` on any
 * machine that can already run the repo's tooling.
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const API_ROOT = 'apps/cms/src/api';

/** Every schema.json under <api>/content-types/<name>/ below the API root. */
function schemaFiles(root) {
  const found = [];
  for (const api of readdirSync(root)) {
    const contentTypes = join(root, api, 'content-types');
    let entries;
    try {
      entries = readdirSync(contentTypes);
    } catch {
      continue; // an api folder without content types is fine
    }
    for (const name of entries) {
      const schema = join(contentTypes, name, 'schema.json');
      try {
        if (statSync(schema).isFile()) found.push(schema);
      } catch {
        // no schema.json here
      }
    }
  }
  return found.sort();
}

const failures = [];

for (const file of schemaFiles(API_ROOT)) {
  let data;
  try {
    data = JSON.parse(readFileSync(file, 'utf8'));
  } catch (error) {
    failures.push(`${file}: not valid JSON (${error.message})`);
    continue;
  }

  const slug = data?.attributes?.slug;
  if (slug === undefined || slug === null) continue;

  if (slug?.pluginOptions?.i18n?.localized !== false) {
    failures.push(`${file}: slug must set i18n.localized = false`);
  }
  if (!slug?.unique) {
    failures.push(`${file}: slug must be unique`);
  }
}

// In GitHub Actions each failure becomes an inline error annotation.
const prefix = process.env.GITHUB_ACTIONS === 'true' ? '::error::' : '';
for (const line of failures) console.error(`${prefix}${line}`);
process.exit(failures.length > 0 ? 1 : 0);
