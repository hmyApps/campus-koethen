// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/** Public surface of the map package. */

export {
  buildFromCanonical,
  buildMobileCatalog,
  buildMobileSvg,
  buildOutputs,
  generatedAssetLayoutProblems,
  generatedFileDrift,
  writeGenerated,
} from './generate.mjs';

export { CATALOG_PATH, PACKAGE_ROOT, ROOM_TYPES, loadCanonical, validate } from './validate.mjs';

export { SvgParseError, findRooms, findUnsafe, parseSvgDocument } from './svg-reader.mjs';

/**
 * Builds the minimal technical references mirrored into Strapi. The canonical
 * catalogue remains the sole owner of every other map field.
 */
export function toFlatRooms(catalog) {
  const buildings = new Map(catalog.buildings.map((b) => [b.buildingKey, b]));
  const floors = new Map(catalog.floors.map((f) => [f.floorKey, f]));

  return catalog.rooms
    .map((room) => {
      const building = buildings.get(room.buildingKey);
      const floor = floors.get(room.floorKey);
      if (!building || !floor) {
        throw new Error(`room "${room.roomKey}" references an unknown building or floor`);
      }
      return {
        roomKey: room.roomKey,
        editorLabel: `${room.roomNumber} · ${building.nameDe}`,
      };
    })
    .sort((a, b) => a.roomKey.localeCompare(b.roomKey));
}
