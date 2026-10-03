export interface TimetableGroupEvidence {
  id: string;
  shortName: string;
  longName: string;
  department: string | null;
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
 */
export function resolveTimetableGroupVisibility(
  groups: readonly TimetableGroupEvidence[],
): Map<string, boolean> {
  const byPublicIdentity = new Map<string, TimetableGroupEvidence[]>();
  for (const group of groups) {
    const key = JSON.stringify([group.shortName, group.longName, group.department]);
    const matches = byPublicIdentity.get(key) ?? [];
    matches.push(group);
    byPublicIdentity.set(key, matches);
  }

  const visibility = new Map<string, boolean>();
  for (const matches of byPublicIdentity.values()) {
    if (matches.length === 1) {
      visibility.set(matches[0]!.id, true);
      continue;
    }

    const populated = matches.filter((group) => group.entryIds.length > 0);
    const fingerprints = new Set(
      populated.map((group) => [...new Set(group.entryIds)].sort().join('\u0000')),
    );
    if (populated.length > 1 && fingerprints.size > 1) {
      for (const group of matches) visibility.set(group.id, true);
      continue;
    }

    const candidates = populated.length > 0 ? populated : matches;
    const representative = [...candidates].sort((a, b) => a.id.localeCompare(b.id))[0]!;
    for (const group of matches) {
      visibility.set(group.id, group.id === representative.id);
    }
  }
  return visibility;
}
