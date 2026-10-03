// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { test } from 'node:test';

type Braces = ((pattern: string) => string[]) & {
  expand(pattern: string): string[];
};

/** Resolve the copy Strapi actually reaches, not an unrelated hoisted copy. */
function strapiBraces(): Braces {
  const strapi = createRequire(createRequire(__filename).resolve('@strapi/strapi'));
  const utils = createRequire(strapi.resolve('@strapi/utils'));
  const preferredPm = createRequire(utils.resolve('preferred-pm'));
  const workspaceRoot = createRequire(preferredPm.resolve('find-yarn-workspace-root2'));
  const micromatch = createRequire(workspaceRoot.resolve('micromatch'));
  return micromatch('braces') as Braces;
}

test('Strapi braces rejects deep patterns before recursive walkers overflow', () => {
  const braces = strapiBraces();
  const nested = (open: string, close: string) => open.repeat(101) + 'x' + close.repeat(101);

  for (const [open, close] of [
    ['{', '}'],
    ['(', ')'],
  ]) {
    assert.throws(() => braces(nested(open, close)), SyntaxError);
    assert.throws(() => braces.expand(nested(open, close)), SyntaxError);
  }
  assert.deepEqual(braces.expand('a{b,c}'), ['ab', 'ac']);
});
