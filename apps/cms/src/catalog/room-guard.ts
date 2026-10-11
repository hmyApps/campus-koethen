// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import { isCatalogSync } from './catalog-scope';

/**
 * Server-side protection for catalogue-managed room fields.
 *
 * Marking the fields read-only in the admin UI would only be cosmetic — the
 * content API and the document service are still reachable. This guard sits in
 * the document-service middleware chain, so EVERY normal editing path goes
 * through it, whichever client produced the write.
 *
 * Deliberate behaviour on `update`: managed fields are STRIPPED rather than
 * rejected. The admin panel submits the whole document on save, including the
 * untouched technical fields, so throwing would make every legitimate
 * editorial save fail. Stripping keeps editorial work flowing while making the
 * technical identity impossible to change from outside the sync.
 */

export const ROOM_UID = 'api::room.room';

/** Owned by packages/campus-map. Only the sync may write these. */
export const CATALOG_MANAGED_FIELDS = ['roomKey', 'editorLabel', 'catalogActive'] as const;

/** Owned by the editorial team. The sync never writes these. */
export const EDITORIAL_FIELDS = [
  'displayNameDe',
  'displayNameEn',
  'descriptionDe',
  'descriptionEn',
  'isVisible',
  'contactPersons',
  'contactAreas',
] as const;

export type CatalogManagedField = (typeof CATALOG_MANAGED_FIELDS)[number];

export interface GuardContext {
  uid: string;
  action: string;
  params: { documentId?: string; data?: unknown };
}

export interface GuardLogger {
  warn: (message: string) => void;
}

export class CatalogManagedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CatalogManagedError';
  }
}

/**
 * Removes catalogue-managed keys from `data`, in place.
 * Returns the names that were removed — never their values.
 */
export function stripCatalogManagedFields(data: unknown): string[] {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    return [];
  }
  const record = data as Record<string, unknown>;
  const removed: string[] = [];
  for (const field of CATALOG_MANAGED_FIELDS) {
    if (field in record) {
      delete record[field];
      removed.push(field);
    }
  }
  return removed;
}

/**
 * Builds the document-service middleware.
 *
 * `next` is called for everything this guard does not own, so unrelated
 * content types and the sync's own writes pass through untouched.
 */
export function createRoomGuard(logger: GuardLogger) {
  return async function roomGuard<T>(context: GuardContext, next: () => Promise<T>): Promise<T> {
    if (context.uid !== ROOM_UID || isCatalogSync()) {
      return next();
    }

    // `clone` (admin "Duplicate") creates a new room through the entries
    // layer and never passes the `create` action, so it is refused as well.
    if (context.action === 'create' || context.action === 'clone' || context.action === 'delete') {
      throw new CatalogManagedError(
        'Rooms are catalogue managed. Use "pnpm --filter @campus/cms rooms:sync" to create or ' +
          'deactivate rooms; editorial fields and contact relations stay editable here.',
      );
    }

    if (context.action === 'update') {
      const removed = stripCatalogManagedFields(context.params.data);
      if (removed.length > 0) {
        // Field NAMES only: values could carry editorial content, and logs
        // must stay free of content dumps.
        logger.warn(
          `Ignored catalogue-managed field(s) on a room update: ${removed.join(', ')}. ` +
            'These are owned by packages/campus-map and are only written by rooms:sync.',
        );
      }
    }

    return next();
  };
}
