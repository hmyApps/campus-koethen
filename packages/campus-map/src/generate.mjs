// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/**
 * Turns the canonical catalogue + SVG into the committed Flutter assets.
 *
 * Two outputs per map:
 *
 *  1. `map_catalog.json` — the roomKey → geometry mapping. Flutter must NOT
 *     have to parse the canonical SVG at runtime to discover the structure.
 *
 *     ROOM prose stays out of this file: display names and descriptions are
 *     served per locale by the Campus API, so bundling them would bypass the
 *     DE/EN contract and freeze editorial text into a release.
 *
 *     BUILDING and FLOOR names are bundled in both languages because they name
 *     the map's own navigation rather than editorial content. Bundling both
 *     languages keeps the picker translated and works offline.
 *
 *  2. A cleaned SVG carrying geometry and the German labels from the approved
 *     source plan. The labels and legends are part of the drawing rather than
 *     Flutter UI copy and deliberately remain German in both app locales.
 *
 * Generation is pure: `buildOutputs` returns an in-memory map and throws on an
 * invalid catalogue, so a failed run can never leave half-written files behind.
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';

import { findRooms, findUnsafe, walkElements } from './svg-reader.mjs';
import { PACKAGE_ROOT, loadCanonical, validate } from './validate.mjs';

/** Repository root, derived from this package's location. */
export const REPO_ROOT = join(PACKAGE_ROOT, '..', '..');

const MOBILE_ASSET_DIR = 'apps/mobile/assets/maps';
const FLUTTER_ASSET_PREFIX = 'assets/maps';

const DROPPED_ELEMENTS = new Set(['title', 'desc']);

/**
 * Elements and attributes the Flutter renderer cannot handle.
 *
 * `flutter_svg` (via vector_graphics_compiler) reports `unhandled element
 * <style/>` and then drops the ENTIRE stylesheet — every room would render
 * unstyled. Markers are unsupported too. Both are therefore resolved or
 * removed here rather than shipped and silently ignored on the device.
 */
const UNSUPPORTED_ELEMENTS = new Set(['style', 'marker']);
const UNSUPPORTED_ATTR_PREFIXES = ['marker-'];

const XML_ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };

function escapeText(value) {
  return value.replace(/[&<>]/g, (char) => XML_ESCAPES[char]);
}

function escapeAttr(value) {
  return value.replace(/[&<>"]/g, (char) => XML_ESCAPES[char]);
}

function classesOf(element) {
  return new Set(
    String(element.attrs?.class ?? '')
      .split(/\s+/)
      .filter(Boolean),
  );
}

/**
 * Reads the inline stylesheet as an ordered list of simple class rules.
 *
 * Only single-class selectors are accepted; anything else throws rather than
 * being silently ignored, because a rule that fails to resolve here would
 * become an invisible styling bug on the device.
 */
export function parseClassRules(root) {
  const rules = [];

  for (const element of walkElements(root)) {
    if (element.name !== 'style') continue;
    const css = (element.children ?? [])
      .filter((child) => child.type === 'text')
      .map((child) => child.value)
      .join('');

    const withoutComments = css.replace(/\/\*[\s\S]*?\*\//g, '');
    for (const match of withoutComments.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const selectors = match[1]
        .split(',')
        .map((selector) => selector.trim())
        .filter(Boolean);
      const classes = [];
      for (const selector of selectors) {
        if (!/^\.[A-Za-z_][-\w]*$/.test(selector)) {
          throw new Error(
            `Unsupported CSS selector "${selector}" — only simple class selectors can be inlined`,
          );
        }
        classes.push(selector.slice(1));
      }

      const declarations = {};
      for (const declaration of match[2].split(';')) {
        const separator = declaration.indexOf(':');
        if (separator === -1) continue;
        const property = declaration.slice(0, separator).trim();
        const value = declaration.slice(separator + 1).trim();
        if (property.length > 0 && value.length > 0) {
          declarations[property] = value;
        }
      }
      if (Object.keys(declarations).length > 0) {
        rules.push({ classes, declarations });
      }
    }
  }

  return rules;
}

/**
 * Resolves the class rules that apply to one element.
 * Later rules win, which mirrors the CSS cascade for equal specificity.
 */
function resolvedStyle(element, rules) {
  const classes = classesOf(element);
  if (classes.size === 0) return {};
  const resolved = {};
  for (const rule of rules) {
    if (rule.classes.some((name) => classes.has(name))) {
      Object.assign(resolved, rule.declarations);
    }
  }
  return resolved;
}

/** True when a node is unsupported or carries redundant SVG metadata. */
function isDropped(node) {
  if (node.type === 'comment') return true;
  if (node.type !== 'element' && !node.name) return false;
  if (DROPPED_ELEMENTS.has(node.name)) return true;
  if (UNSUPPORTED_ELEMENTS.has(node.name)) return true;
  return false;
}

/**
 * Serialises a node tree back to XML, preserving visible map text.
 * Attribute order follows the source, so the output is reproducible.
 */
function serialise(node, rules, indent = 0) {
  if (node.type === 'text') {
    const value = node.value.trim();
    return value.length > 0 ? escapeText(value) : '';
  }

  // Presentation attributes first, then the resolved class rules on top: in
  // CSS a stylesheet beats a presentation attribute, and inlining must not
  // silently invert that precedence.
  const merged = {};
  for (const [name, value] of Object.entries(node.attrs ?? {})) {
    if (UNSUPPORTED_ATTR_PREFIXES.some((prefix) => name.startsWith(prefix))) continue;
    merged[name] = value;
  }
  Object.assign(merged, resolvedStyle(node, rules));

  const attrs = Object.entries(merged)
    .map(([name, value]) => ` ${name}="${escapeAttr(String(value))}"`)
    .join('');

  const children = (node.children ?? []).filter((child) => !isDropped(child));
  const rendered = children
    .map((child) => serialise(child, rules, indent + 1))
    .filter((chunk) => chunk.length > 0);

  if (rendered.length === 0) {
    return `${'  '.repeat(indent)}<${node.name}${attrs} />`;
  }

  // Elements whose children are pure text stay on one line; everything else is
  // indented, which keeps diffs of the generated asset readable.
  const onlyText = children.every((child) => child.type === 'text');
  if (onlyText) {
    return `${'  '.repeat(indent)}<${node.name}${attrs}>${rendered.join('')}</${node.name}>`;
  }
  return [
    `${'  '.repeat(indent)}<${node.name}${attrs}>`,
    ...rendered,
    `${'  '.repeat(indent)}</${node.name}>`,
  ].join('\n');
}

/**
 * Attributes on the root that only make sense together with the metadata nodes
 * this generator strips. Accessibility text comes from Flutter Semantics, so a
 * reference to a removed `<title>`/`<desc>` would just dangle.
 */
const DROPPED_ROOT_ATTRS = ['aria-labelledby', 'aria-describedby'];

/** The cleaned SVG that ships with the app. */
export function buildMobileSvg(root) {
  const cleanedRoot = {
    ...root,
    attrs: Object.fromEntries(
      Object.entries(root.attrs ?? {}).filter(([name]) => !DROPPED_ROOT_ATTRS.includes(name)),
    ),
  };
  const rules = parseClassRules(root);
  const body = serialise(cleanedRoot, rules, 0);
  const header = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!-- GENERATED by packages/campus-map — do not edit by hand. -->',
    '<!-- The per-building plan claim is carried by planKind in map_catalog.json. -->',
    '<!-- Styles are inlined as presentation attributes: the Flutter renderer -->',
    '<!-- ignores <style> blocks, which would leave every room unstyled.      -->',
  ].join('\n');
  return `${header}\n${body}\n`;
}

/** The language-neutral roomKey → geometry mapping that ships with the app. */
export function buildMobileCatalog(catalog) {
  return {
    schemaVersion: catalog.schemaVersion,
    mapVersion: catalog.mapVersion,
    generator: '@campus/map',
    buildings: catalog.buildings
      .map((building) => ({
        buildingKey: building.buildingKey,
        ...(building.buildingNumber ? { buildingNumber: building.buildingNumber } : {}),
        nameDe: building.nameDe,
        nameEn: building.nameEn,
        planKind: building.planKind,
        ...(building.sourceAttributionDe
          ? {
              sourceAttributionDe: building.sourceAttributionDe,
              sourceAttributionEn: building.sourceAttributionEn,
            }
          : {}),
        sortOrder: building.sortOrder ?? 0,
      }))
      .sort((a, b) => a.sortOrder - b.sortOrder || a.buildingKey.localeCompare(b.buildingKey)),
    floors: catalog.floors
      .map((floor) => ({
        floorKey: floor.floorKey,
        buildingKey: floor.buildingKey,
        level: floor.level,
        nameDe: floor.nameDe,
        nameEn: floor.nameEn,
        svgAsset: `${FLUTTER_ASSET_PREFIX}/${floor.svgPath.replace(/^buildings\//, '')}`,
        viewBox: {
          minX: floor.viewBox.minX,
          minY: floor.viewBox.minY,
          width: floor.viewBox.width,
          height: floor.viewBox.height,
        },
        sortOrder: floor.sortOrder ?? 0,
      }))
      .sort((a, b) => a.sortOrder - b.sortOrder || a.floorKey.localeCompare(b.floorKey)),
    rooms: catalog.rooms
      .map((room) => ({
        roomKey: room.roomKey,
        roomNumber: room.roomNumber,
        buildingKey: room.buildingKey,
        floorKey: room.floorKey,
        roomType: room.roomType,
        svgElementId: room.svgElementId,
        focus: { x: room.focus.x, y: room.focus.y },
        bounds: {
          x: room.bounds.x,
          y: room.bounds.y,
          width: room.bounds.width,
          height: room.bounds.height,
        },
        sortOrder: room.sortOrder ?? 0,
      }))
      .sort((a, b) => a.sortOrder - b.sortOrder || a.roomKey.localeCompare(b.roomKey)),
  };
}

/**
 * Builds every generated file in memory.
 *
 * Throws when the catalogue does not validate against the supplied documents,
 * so callers cannot write a partial result.
 */
export function buildOutputs(catalog, documents) {
  const problems = [];
  for (const floor of catalog.floors) {
    const root = documents.get(floor.floorKey);
    if (!root) {
      problems.push(`floor "${floor.floorKey}" has no parsed SVG document`);
      continue;
    }
    const svgKeys = new Set(findRooms(root).map((element) => element.attrs['data-room-key']));
    for (const room of catalog.rooms.filter((r) => r.floorKey === floor.floorKey)) {
      if (!svgKeys.has(room.roomKey)) {
        problems.push(`room "${room.roomKey}" has no SVG element on floor "${floor.floorKey}"`);
      }
    }
  }
  if (problems.length > 0) {
    throw new Error(`Refusing to generate from an invalid catalogue:\n${problems.join('\n')}`);
  }

  const files = new Map();
  files.set(
    `${MOBILE_ASSET_DIR}/map_catalog.json`,
    `${JSON.stringify(buildMobileCatalog(catalog), null, 2)}\n`,
  );

  for (const floor of catalog.floors) {
    const svg = buildMobileSvg(documents.get(floor.floorKey));
    const unsafe = findUnsafe(documents.get(floor.floorKey));
    if (unsafe.length > 0) {
      throw new Error(`Refusing to generate an unsafe asset:\n${unsafe.join('\n')}`);
    }
    files.set(`${MOBILE_ASSET_DIR}/${floor.svgPath.replace(/^buildings\//, '')}`, svg);
  }

  return files;
}

/** Generates everything from the committed canonical sources. */
export function buildFromCanonical(packageRoot = PACKAGE_ROOT) {
  const { catalog, documents, problems } = loadCanonical(packageRoot);
  if (problems.length > 0) {
    throw new Error(`Canonical catalogue is invalid:\n${problems.join('\n')}`);
  }
  return { catalog, files: buildOutputs(catalog, documents) };
}

/** Writes the generated files. Only ever called after a fully successful build. */
export function writeGenerated({ repoRoot = REPO_ROOT, packageRoot = PACKAGE_ROOT } = {}) {
  const { files } = buildFromCanonical(packageRoot);
  const written = [];
  for (const [relativePath, content] of files) {
    const target = join(repoRoot, relativePath);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, content, 'utf8');
    written.push(relativePath);
  }
  return written.sort();
}

/** Normalises checkout-only EOL differences before generated-content comparison. */
function normaliseLineEndings(value) {
  return value.replace(/\r\n?/g, '\n');
}

/**
 * Compares the committed generated assets with a fresh build.
 * Returns a list of drifted paths; empty means the assets are current.
 */
export function generatedFileDrift({
  repoRoot = REPO_ROOT,
  packageRoot = PACKAGE_ROOT,
  readFile,
} = {}) {
  const read =
    readFile ??
    ((relativePath) => {
      try {
        return readFileSync(join(repoRoot, relativePath), 'utf8');
      } catch {
        return undefined;
      }
    });

  const { files } = buildFromCanonical(packageRoot);
  const drift = [];
  for (const [relativePath, expected] of files) {
    const actual = read(relativePath);
    if (actual === undefined) {
      drift.push(`${relativePath}: missing — run 'pnpm --filter @campus/map generate'`);
    } else if (normaliseLineEndings(actual) !== normaliseLineEndings(expected)) {
      drift.push(`${relativePath}: out of date — run 'pnpm --filter @campus/map generate'`);
    }
  }
  return drift;
}

export { validate };
