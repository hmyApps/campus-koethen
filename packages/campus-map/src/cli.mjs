#!/usr/bin/env node
// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/**
 * Map catalogue tooling.
 *
 *   validate   check the canonical catalogue against the canonical SVG files
 *   generate   (re)write the committed Flutter assets
 *   check      validate AND fail when the committed assets have drifted, when
 *              an orphaned file sits in the asset folder, or when pubspec.yaml
 *              does not bundle every generated building folder
 *
 * `check` is what CI runs: it never writes, so a pull request that edits the
 * canonical sources without regenerating fails instead of shipping a mismatch.
 */

import {
  buildFromCanonical,
  generatedAssetLayoutProblems,
  generatedFileDrift,
  writeGenerated,
} from './generate.mjs';
import { loadCanonical } from './validate.mjs';

function fail(headline, details = []) {
  console.error(`✖ ${headline}`);
  for (const detail of details) console.error(`  - ${detail}`);
  process.exit(1);
}

function runValidate() {
  const { catalog, problems } = loadCanonical();
  if (problems.length > 0) {
    fail(`Map catalogue is invalid (${problems.length} problem(s))`, problems);
  }
  console.log(
    `✓ catalogue valid — ${catalog.buildings.length} building(s), ` +
      `${catalog.floors.length} floor(s), ${catalog.rooms.length} room(s), ` +
      `mapVersion ${catalog.mapVersion}`,
  );
}

function runGenerate() {
  runValidate();
  let written;
  try {
    written = writeGenerated();
  } catch (error) {
    fail('Generation aborted; nothing was written', [error.message]);
    return;
  }
  console.log(`✓ generated ${written.length} file(s):`);
  for (const path of written) console.log(`  ${path}`);
}

function runCheck() {
  runValidate();
  let drift;
  try {
    drift = generatedFileDrift();
  } catch (error) {
    fail('Could not build the expected assets', [error.message]);
    return;
  }
  if (drift.length > 0) {
    fail('Generated map assets do not match the canonical sources', drift);
  }
  let layout;
  try {
    layout = generatedAssetLayoutProblems();
  } catch (error) {
    fail('Could not check the asset layout', [error.message]);
    return;
  }
  if (layout.length > 0) {
    fail('Map asset folder or pubspec.yaml does not match the generated assets', layout);
  }
  // Touch the build once so an unreadable canonical source is caught here too.
  buildFromCanonical();
  console.log('✓ generated map assets are up to date');
}

const command = process.argv[2] ?? 'validate';
switch (command) {
  case 'validate':
    runValidate();
    break;
  case 'generate':
    runGenerate();
    break;
  case 'check':
    runCheck();
    break;
  default:
    fail(`Unknown command "${command}"`, ['Use: validate | generate | check']);
}
