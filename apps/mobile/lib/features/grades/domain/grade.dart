// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'exam_report.dart';

/// What a grade cell means, kept type-safe instead of a raw string.
enum GradeKind {
  /// A real numeric grade (German 1.0 … 5.0).
  graded,

  /// Passed without a numeric grade ("unbenotet bestanden"). This is also how a
  /// QIS `0,0` together with "bestanden" is represented — NEVER as a 0.0 grade.
  passedUngraded,

  /// No grade recorded.
  none,
}

/// The grade of one exam.
@immutable
class Grade {
  const Grade._(this.kind, this.value);

  const Grade.graded(double value) : this._(GradeKind.graded, value);
  const Grade.passedUngraded() : this._(GradeKind.passedUngraded, null);
  const Grade.none() : this._(GradeKind.none, null);

  final GradeKind kind;

  /// The numeric value — only meaningful when [kind] is [GradeKind.graded].
  final double? value;

  bool get isGraded => kind == GradeKind.graded;
  bool get isPassedUngraded => kind == GradeKind.passedUngraded;
  bool get isEmpty => kind == GradeKind.none;

  @override
  bool operator ==(Object other) =>
      other is Grade && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => isGraded ? 'Grade($value)' : 'Grade(${kind.name})';
}

/// The pass/fail status of an exam row, type-safe with a raw fallback.
enum ExamStatus {
  passed,
  failed,

  /// "Prüfung vorhanden" — an exam exists but is not (yet) a result.
  present,

  /// An unrecognised status; the original text is kept for display.
  unknown,
}

/// One row of the Notenspiegel. Independent of the HTML the parser reads.
@immutable
class GradeEntry {
  const GradeEntry({
    required this.examNumber,
    required this.title,
    required this.grade,
    required this.status,
    required this.statusText,
    this.points,
    this.bonus,
    this.attempt,
    this.examDate,
    this.examiner,
    this.path,
    this.module,
    this.extras = const <String, String>{},
    this.isLeaf = true,
  });

  final String examNumber;
  final String title;
  final Grade grade;
  final ExamStatus status;

  /// The original status text, shown verbatim for [ExamStatus.unknown].
  final String statusText;

  final String? points;

  /// The "Bonus" column — kept as text; labelled factually in the UI.
  final String? bonus;
  final String? attempt;
  final DateTime? examDate;
  final String? examiner;

  /// The tree path of this row in a hierarchical portal (e.g. `1.1.1.1`), or
  /// `null` for a portal without a tree structure. [depth] is derived from it.
  final String? path;

  /// The title of the parent tree node ("Modulbezeichnung"), or `null` when the
  /// portal has no hierarchy or this is a root row.
  final String? module;

  /// Every portal column that has no dedicated field, keyed by the ORIGINAL
  /// header text so the UI can show it verbatim.
  final Map<String, String> extras;

  /// Whether this row is an actual exam result rather than an intermediate
  /// tree node (module, programme, degree). `true` for a portal without a
  /// tree structure (there every row already is a result). Purely a display
  /// concern: the projection still classifies EVERY row (e.g. `true` for a
  /// non-leaf "C-Sammelkonto" average row), so filtering to leaves belongs in
  /// the presentation layer, never in the parser.
  final bool isLeaf;

  /// The depth in the tree, derived from [path] (`"1.1.1"` → depth 3). `0` when
  /// there is no path.
  int get depth => path == null || path!.isEmpty ? 0 : path!.split('.').length;

  @override
  bool operator ==(Object other) =>
      other is GradeEntry &&
      other.examNumber == examNumber &&
      other.title == title &&
      other.grade == grade &&
      other.status == status &&
      other.statusText == statusText &&
      other.points == points &&
      other.bonus == bonus &&
      other.attempt == attempt &&
      other.examDate == examDate &&
      other.examiner == examiner &&
      other.path == path &&
      other.module == module &&
      other.isLeaf == isLeaf &&
      _mapEquals(other.extras, extras);

  @override
  int get hashCode => Object.hash(
    examNumber,
    title,
    grade,
    status,
    statusText,
    points,
    bonus,
    attempt,
    examDate,
    examiner,
    path,
    module,
    isLeaf,
    Object.hashAllUnordered(
      extras.entries.map(
        (MapEntry<String, String> e) => Object.hash(e.key, e.value),
      ),
    ),
  );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final MapEntry<String, String> entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// A whole Notenspiegel — the ordered exam rows, plus any of the exam
/// overview's own fixed "Bescheinigungen" print buttons (HISinOne only;
/// always empty on the legacy portal, which has no such section).
@immutable
class GradeReport {
  const GradeReport(
    this.entries, {
    this.examReports = const <ExamReportOffer>[],
  });

  final List<GradeEntry> entries;
  final List<ExamReportOffer> examReports;

  bool get isEmpty => entries.isEmpty;
}
