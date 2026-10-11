// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/**
 * Type surface of the map package.
 *
 * The implementation is plain ESM JavaScript (see the package README for why),
 * so the types consumers rely on are declared here explicitly.
 */

export type RoomType = 'room' | 'lecture' | 'seminar' | 'office' | 'lab' | 'meeting' | 'service';

export interface ViewBox {
  minX: number;
  minY: number;
  width: number;
  height: number;
}

export interface CatalogBuilding {
  buildingKey: string;
  /** Official campus building number. Room-less overview entries may omit it. */
  buildingNumber?: string;
  nameDe: string;
  nameEn: string;
  planKind: 'schematic';
  sourceAttributionDe?: string;
  sourceAttributionEn?: string;
  sortOrder: number;
}

export interface CatalogFloor {
  floorKey: string;
  buildingKey: string;
  level: number;
  nameDe: string;
  nameEn: string;
  svgPath: string;
  viewBox: ViewBox;
  expectedRoomCount: number;
  sortOrder: number;
}

export interface CatalogRoomEntry {
  roomKey: string;
  roomNumber: string;
  buildingKey: string;
  floorKey: string;
  roomType: RoomType;
  svgElementId: string;
  focus: { x: number; y: number };
  bounds: { x: number; y: number; width: number; height: number };
  sortOrder: number;
}

export interface MapCatalog {
  schemaVersion: number;
  mapVersion: string;
  notice: string;
  buildings: CatalogBuilding[];
  floors: CatalogFloor[];
  rooms: CatalogRoomEntry[];
}

/** One room joined with its floor and building. */
export interface FlatRoom {
  roomKey: string;
  editorLabel: string;
}

export interface LoadResult {
  catalog: MapCatalog;
  problems: string[];
  documents: Map<string, unknown>;
  readSvg: (svgPath: string) => string | undefined;
}

export declare const ROOM_TYPES: readonly RoomType[];
export declare const CATALOG_PATH: string;
export declare const PACKAGE_ROOT: string;

export declare function loadCanonical(packageRoot?: string): LoadResult;
export declare function validate(
  catalog: MapCatalog,
  readSvg: (svgPath: string) => string | undefined,
): { problems: string[]; documents: Map<string, unknown> };

export declare function toFlatRooms(catalog: MapCatalog): FlatRoom[];

export declare function buildFromCanonical(packageRoot?: string): {
  catalog: MapCatalog;
  files: Map<string, string>;
};
export declare function buildMobileCatalog(catalog: MapCatalog): unknown;
export declare function buildMobileSvg(root: unknown): string;
export declare function buildOutputs(
  catalog: MapCatalog,
  documents: Map<string, unknown>,
): Map<string, string>;
export declare function writeGenerated(options?: {
  repoRoot?: string;
  packageRoot?: string;
}): string[];
export declare function generatedFileDrift(options?: {
  repoRoot?: string;
  packageRoot?: string;
  readFile?: (relativePath: string) => string | undefined;
}): string[];

export declare function generatedAssetLayoutProblems(options?: {
  repoRoot?: string;
  packageRoot?: string;
  listFiles?: () => string[];
  readPubspec?: () => string;
}): string[];

export declare class SvgParseError extends Error {}
export declare function parseSvgDocument(text: string): unknown;
export declare function findUnsafe(root: unknown): string[];
export declare function findRooms(root: unknown): unknown[];
