// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';

import apiConfig from '../config/api';

const cmsRoot = path.resolve(__dirname, '..');

function source(relativePath: string): string {
  return readFileSync(path.join(cmsRoot, relativePath), 'utf8');
}

test('CMS REST and document queries stay strict and bounded', () => {
  assert.equal(apiConfig.rest?.strictParams, true);
  assert.equal(apiConfig.documents?.strictParams, true);
  assert.equal(apiConfig.rest?.defaultLimit, 25);
  assert.equal(apiConfig.rest?.maxLimit, 100);
});

test('admin secrets come only from the environment', () => {
  const admin = source('config/admin.ts');

  for (const key of [
    'ADMIN_JWT_SECRET',
    'API_TOKEN_SALT',
    'TRANSFER_TOKEN_SALT',
    'ENCRYPTION_KEY',
  ]) {
    assert.match(admin, new RegExp(`env\\('${key}'\\)`));
  }
  assert.doesNotMatch(admin, /(?:secret|salt|encryptionKey):\s*['"][^'"]+['"]/);
});

test('every editorial API keeps Strapi core authentication and serialization', () => {
  const apiRoot = path.join(cmsRoot, 'src', 'api');
  const apiNames = readdirSync(apiRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);

  assert.ok(apiNames.length > 0);
  for (const apiName of apiNames) {
    const uid = `api::${apiName}.${apiName}`;
    const files = {
      controllers: source(`src/api/${apiName}/controllers/${apiName}.ts`),
      routes: source(`src/api/${apiName}/routes/${apiName}.ts`),
      services: source(`src/api/${apiName}/services/${apiName}.ts`),
    };

    assert.match(files.controllers, /factories\.createCoreController\(/, apiName);
    assert.match(files.routes, /factories\.createCoreRouter\(/, apiName);
    assert.match(files.services, /factories\.createCoreService\(/, apiName);
    for (const contents of Object.values(files)) {
      assert.match(contents, new RegExp(uid.split('.').join('\\.')));
      assert.doesNotMatch(contents, /auth\s*:\s*false/, apiName);
    }
  }
});
