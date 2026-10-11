// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { Core } from '@strapi/strapi';

import serverConfig from '../config/server';

type Env = Core.Config.Shared.ConfigParams['env'];

// Minimal stand-in for Strapi's `env` helper: only the accessors config/server.ts uses.
function fakeEnv(values: Record<string, string>): Env {
  const has = (key: string) => Object.prototype.hasOwnProperty.call(values, key);
  const read = (key: string, fallback?: unknown) => (has(key) ? values[key] : fallback);
  return Object.assign(read, {
    int: (key: string, fallback?: number) => (has(key) ? Number(values[key]) : fallback),
    bool: (key: string, fallback?: boolean) => (has(key) ? values[key] === 'true' : fallback),
    array: (key: string, fallback?: string[]) => (has(key) ? values[key].split(',') : fallback),
  }) as unknown as Env;
}

function load(values: Record<string, string>): Core.Config.Server {
  return serverConfig({ env: fakeEnv({ APP_KEYS: 'a,b', ...values }) });
}

test('behind the reverse proxy Strapi knows its public HTTPS URL and trusts X-Forwarded-*', () => {
  const config = load({ PUBLIC_URL: 'https://cms.example.org' });

  assert.equal(config.url, 'https://cms.example.org');
  // Strapi 5 reads `server.proxy.koa`; a bare `proxy: true` would be ignored.
  assert.deepEqual(config.proxy, { koa: true });
});

test('without PUBLIC_URL (local development) no proxy headers are trusted', () => {
  const config = load({});

  assert.equal(config.url, '');
  assert.deepEqual(config.proxy, { koa: false });
});

test('IS_PROXIED overrides the proxy default explicitly', () => {
  assert.deepEqual(load({ PUBLIC_URL: 'https://cms.example.org', IS_PROXIED: 'false' }).proxy, {
    koa: false,
  });
  assert.deepEqual(load({ IS_PROXIED: 'true' }).proxy, { koa: true });
});
