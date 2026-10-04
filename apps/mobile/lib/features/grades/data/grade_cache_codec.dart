// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../domain/exam_report.dart';
import '../domain/grade.dart';

/// JSON mappers for the encrypted grade cache. Kept out of the domain so the
/// models stay pure; a malformed field decodes to a safe default rather than
/// throwing.
abstract final class GradeCacheCodec {
  static Map<String, dynamic> entry(GradeEntry e) => <String, dynamic>{
    'examNumber': e.examNumber,
    'title': e.title,
    'gradeKind': e.grade.kind.name,
    'gradeValue': e.grade.value,
    'status': e.status.name,
    'statusText': e.statusText,
    'points': e.points,
    'bonus': e.bonus,
    'attempt': e.attempt,
    'examDate': e.examDate?.toIso8601String(),
    'examiner': e.examiner,
    'path': e.path,
    'module': e.module,
    'extras': e.extras,
    'isLeaf': e.isLeaf,
  };

  static GradeEntry entryFrom(Map<String, dynamic> j) => GradeEntry(
    examNumber: (j['examNumber'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    grade: _grade(j['gradeKind'] as String?, j['gradeValue']),
    status: _status(j['status'] as String?),
    statusText: (j['statusText'] as String?) ?? '',
    points: j['points'] as String?,
    bonus: j['bonus'] as String?,
    attempt: j['attempt'] as String?,
    examDate: _date(j['examDate']),
    examiner: j['examiner'] as String?,
    path: j['path'] as String?,
    module: j['module'] as String?,
    extras: _extras(j['extras']),
    isLeaf: (j['isLeaf'] as bool?) ?? true,
  );

  static Map<String, dynamic> examReportOffer(ExamReportOffer o) =>
      <String, dynamic>{'buttonId': o.buttonId, 'label': o.label};

  static ExamReportOffer examReportOfferFrom(Map<String, dynamic> j) =>
      ExamReportOffer(
        buttonId: (j['buttonId'] as String?) ?? '',
        label: (j['label'] as String?) ?? '',
      );

  /// A wrapper object, not a bare array: [reportFrom] still reads the
  /// earlier bare-array shape (cached before exam-report offers existed) as
  /// entries with no offers, never throwing on old content.
  static Map<String, dynamic> report(GradeReport r) => <String, dynamic>{
    'entries': r.entries.map(entry).toList(),
    'examReports': r.examReports.map(examReportOffer).toList(),
  };

  static GradeReport reportFrom(Object? decoded) {
    if (decoded is List) {
      return GradeReport(_entriesFrom(decoded));
    }
    if (decoded is! Map) return const GradeReport(<GradeEntry>[]);
    return GradeReport(
      _entriesFrom(decoded['entries']),
      examReports: _examReportsFrom(decoded['examReports']),
    );
  }

  static List<GradeEntry> _entriesFrom(Object? decoded) {
    if (decoded is! List) return <GradeEntry>[];
    return decoded
        .whereType<Map>()
        .map((Map m) => entryFrom(Map<String, dynamic>.from(m)))
        .toList();
  }

  static List<ExamReportOffer> _examReportsFrom(Object? decoded) {
    if (decoded is! List) return <ExamReportOffer>[];
    return decoded
        .whereType<Map>()
        .map((Map m) => examReportOfferFrom(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Grade _grade(String? kind, Object? value) {
    final double? numeric = value is num ? value.toDouble() : null;
    return switch (kind) {
      'graded' => Grade.graded(numeric ?? 0),
      'passedUngraded' => const Grade.passedUngraded(),
      _ => const Grade.none(),
    };
  }

  static ExamStatus _status(String? name) {
    for (final ExamStatus s in ExamStatus.values) {
      if (s.name == name) return s;
    }
    return ExamStatus.unknown;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static Map<String, String> _extras(Object? value) {
    if (value is! Map) return const <String, String>{};
    return <String, String>{
      for (final MapEntry<Object?, Object?> e in value.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  }
}
