export interface TimetableGroupEvidence {
  id: string;
  shortName: string;
  longName: string;
  department: string | null;
  /**
   * Semester catalogues (timetable contexts) that list this group. Aliases are
   * only ever consolidated inside one of them; an empty list is its own scope.
   */
  contextIds: readonly string[];
  entryIds: readonly string[];
}

/**
 * Decides which active source rows belong in the public catalogue.
 *
 * Names alone never prove that two groups are aliases. Exact public metadata
 * is only consolidated when at most one row has timetable data, or when every
 * populated row points at the exact same set of lessons. Divergent non-empty
 * plans stay visible: they are different groups even if upstream labelled them
 * identically, and hiding either one would lose a real timetable.
 *
 * Consolidation happens per semester catalogue. Around a semester change the
 * sync window covers two catalogues, and the next semester's same-named group
 * — typically still without lessons — is a different cohort, not an alias of
 * the current one. A group listed in several catalogues stays visible as long
 * as it represents at least one of them.
 */
export function resolveTimetableGroupVisibility(
  groups: readonly TimetableGroupEvidence[],
): Map<string, boolean> {
  const byPublicIdentity = new Map<string, TimetableGroupEvidence[]>();
  for (const group of groups) {
    const scopes: Array<string | null> =
      group.contextIds.length > 0 ? [...new Set(group.contextIds)] : [null];
    for (const scope of scopes) {
      const key = JSON.stringify([scope, group.shortName, group.longName, group.department]);
      const matches = byPublicIdentity.get(key) ?? [];
      matches.push(group);
      byPublicIdentity.set(key, matches);
    }
  }

  const visibility = new Map<string, boolean>();
  const mark = (id: string, visible: boolean): void => {
    visibility.set(id, (visibility.get(id) ?? false) || visible);
  };
  for (const matches of byPublicIdentity.values()) {
    if (matches.length === 1) {
      mark(matches[0]!.id, true);
      continue;
    }

    const populated = matches.filter((group) => group.entryIds.length > 0);
    const fingerprints = new Set(
      populated.map((group) => [...new Set(group.entryIds)].sort().join('\u0000')),
    );
    if (populated.length > 1 && fingerprints.size > 1) {
      for (const group of matches) mark(group.id, true);
      continue;
    }

    const candidates = populated.length > 0 ? populated : matches;
    const representative = [...candidates].sort((a, b) => a.id.localeCompare(b.id))[0]!;
    for (const group of matches) {
      mark(group.id, group.id === representative.id);
    }
  }
  return visibility;
}
