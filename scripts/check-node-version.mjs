// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const versionFile = fileURLToPath(new URL('../.node-version', import.meta.url));
const expected = readFileSync(versionFile, 'utf8').trim();
const actual = process.versions.node;

if (actual !== expected) {
  console.error(
    `Unsupported Node.js version: expected v${expected} from .node-version, got v${actual}.`,
  );
  console.error('Switch Node.js before installing dependencies or running repository gates.');
  process.exitCode = 1;
} else {
  console.log(`Node.js v${actual} matches the repository pin.`);
}
