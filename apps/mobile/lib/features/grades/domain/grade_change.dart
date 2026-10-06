// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'grade.dart';

/// Returns result rows that changed from "no result" to a recorded grade.
///
/// A missing [previous] report is an initial baseline, never a change. Existing
/// numeric grades changing value are deliberately excluded: the reader-facing
/// message says "new grade", not "grade corrected". Aggregate HISinOne tree
/// nodes are excluded as well, because a recalculated average is not an exam
/// result.
List<GradeEntry> newlyGradedEntries({
  required GradeReport? previous,
  required GradeReport current,
}) {
  if (previous == null) return const <GradeEntry>[];

  final Map<String, List<GradeEntry>> before = <String, List<GradeEntry>>{};
  for (final GradeEntry entry in previous.entries) {
    (before[_identityOf(entry)] ??= <GradeEntry>[]).add(entry);
  }

  final List<GradeEntry> changed = <GradeEntry>[];
  for (final GradeEntry entry in current.entries) {
    if (!entry.isLeaf || entry.grade.isEmpty) continue;
    final List<GradeEntry> candidates =
        before[_identityOf(entry)] ?? const <GradeEntry>[];
    if (candidates.isEmpty ||
        candidates.any((GradeEntry old) => old.grade.isEmpty)) {
      changed.add(entry);
    }
  }
  return List<GradeEntry>.unmodifiable(changed);
}

String _identityOf(GradeEntry entry) {
  final String? path = entry.path?.trim();
  if (path != null && path.isNotEmpty) {
    return 'path:$path|exam:${entry.examNumber.trim()}';
  }
  return <String?>[
    entry.examNumber,
    entry.title,
    entry.attempt,
    entry.examDate?.toUtc().toIso8601String(),
    entry.module,
  ].map((String? value) => value?.trim() ?? '').join('|');
}
