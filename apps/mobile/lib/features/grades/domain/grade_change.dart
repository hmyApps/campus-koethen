// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

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

  // How many already graded results each identity had. A current graded
  // result is new unless it can be matched against one of them; counting
  // (rather than "any previous row with this identity was empty") keeps two
  // rows that happen to share an identity from announcing each other.
  final Map<String, int> gradedBefore = <String, int>{};
  for (final GradeEntry entry in previous.entries) {
    if (entry.grade.isEmpty) continue;
    final String id = _identityOf(entry);
    gradedBefore[id] = (gradedBefore[id] ?? 0) + 1;
  }

  final List<GradeEntry> changed = <GradeEntry>[];
  for (final GradeEntry entry in current.entries) {
    if (!entry.isLeaf || entry.grade.isEmpty) continue;
    final String id = _identityOf(entry);
    final int remaining = gradedBefore[id] ?? 0;
    if (remaining > 0) {
      gradedBefore[id] = remaining - 1;
    } else {
      changed.add(entry);
    }
  }
  return List<GradeEntry>.unmodifiable(changed);
}

/// What makes a result row "the same result" across two reports: exam number,
/// attempt, exam title and module title — all content of the row itself.
///
/// Deliberately NOT the HISinOne tree path (`1.2.1`): the portal numbers it
/// by position, so a module inserted above shifts every path below it and
/// announced all of those already graded results as "new". Not the exam date
/// either: HIS-QIS and HISinOne only fill it once a result is released. The
/// path is only a fallback for a row that carries neither number nor title.
///
/// Both reports are keyed by this same function at comparison time — the
/// cache stores raw rows, never keys — so changing it needs no migration of
/// already stored baselines.
String _identityOf(GradeEntry entry) {
  final String number = entry.examNumber.trim();
  final String title = entry.title.trim();
  final String? path = entry.path?.trim();
  if (number.isEmpty && title.isEmpty && path != null && path.isNotEmpty) {
    return jsonEncode(<String>['path', path]);
  }
  return jsonEncode(<String>[
    'exam',
    number,
    entry.attempt?.trim() ?? '',
    title,
    entry.module?.trim() ?? '',
  ]);
}
