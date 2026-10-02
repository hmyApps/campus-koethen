// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../domain/student_service_overview.dart';

/// JSON mappers for the encrypted student-service cache. A malformed field
/// decodes to a safe default rather than throwing — the same contract as
/// `GradeCacheCodec`.
abstract final class StudentServiceCacheCodec {
  static Map<String, dynamic> overview(StudentServiceOverview o) =>
      <String, dynamic>{
        'personalData': o.personalData
            .map(
              (PersonalDataField f) => <String, String>{
                'label': f.label,
                'value': f.value,
              },
            )
            .toList(),
        'hoererstatus': o.hoererstatus,
        'contactTiles': o.contactTiles
            .map(
              (ContactTile t) => <String, dynamic>{
                'heading': t.heading,
                'lines': t.lines,
              },
            )
            .toList(),
        'programmes': o.programmes
            .map(
              (ProgrammeEntry p) => <String, String>{
                'subject': p.subject,
                'subjectSemester': p.subjectSemester,
                'subjectIndicator': p.subjectIndicator,
                'examinationVersion': p.examinationVersion,
              },
            )
            .toList(),
        'certificates': o.certificates
            .map(
              (CertificateOffer c) => <String, String>{
                'name': c.name,
                'jobButtonId': c.jobButtonId,
              },
            )
            .toList(),
        'paymentHintKind': o.paymentHint.kind.name,
        'paymentHintOpenItemCount': o.paymentHint.openItemCount,
        'fetchedAt': o.fetchedAt.toIso8601String(),
      };

  static StudentServiceOverview overviewFrom(Map<String, dynamic> j) {
    final List<Object?> personalDataRaw =
        (j['personalData'] as List?) ?? const [];
    final List<PersonalDataField> personalData = personalDataRaw
        .map((Object? e) => _asMap(e))
        .map(
          (Map<String, dynamic> m) => PersonalDataField(
            label: (m['label'] as String?) ?? '',
            value: (m['value'] as String?) ?? '',
          ),
        )
        .toList();

    final List<Object?> tilesRaw = (j['contactTiles'] as List?) ?? const [];
    final List<ContactTile> tiles = tilesRaw
        .map((Object? e) => _asMap(e))
        .map(
          (Map<String, dynamic> m) => ContactTile(
            heading: (m['heading'] as String?) ?? '',
            lines: (m['lines'] as List?)?.cast<String>() ?? const [],
          ),
        )
        .toList();

    final List<Object?> programmesRaw = (j['programmes'] as List?) ?? const [];
    final List<ProgrammeEntry> programmes = programmesRaw
        .map((Object? e) => _asMap(e))
        .map(
          (Map<String, dynamic> m) => ProgrammeEntry(
            subject: (m['subject'] as String?) ?? '',
            subjectSemester: (m['subjectSemester'] as String?) ?? '',
            subjectIndicator: (m['subjectIndicator'] as String?) ?? '',
            examinationVersion: (m['examinationVersion'] as String?) ?? '',
          ),
        )
        .toList();

    final List<Object?> certificatesRaw =
        (j['certificates'] as List?) ?? const [];
    final List<CertificateOffer> certificates = certificatesRaw
        .map((Object? e) => _asMap(e))
        .map(
          (Map<String, dynamic> m) => CertificateOffer(
            name: (m['name'] as String?) ?? '',
            jobButtonId: (m['jobButtonId'] as String?) ?? '',
          ),
        )
        .toList();

    return StudentServiceOverview(
      personalData: personalData,
      hoererstatus: j['hoererstatus'] as String?,
      contactTiles: tiles,
      programmes: programmes,
      certificates: certificates,
      paymentHint: PaymentHint(
        kind: _paymentHintKind(j['paymentHintKind'] as String?),
        openItemCount: j['paymentHintOpenItemCount'] as int?,
      ),
      fetchedAt:
          DateTime.tryParse(j['fetchedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static Map<String, dynamic> _asMap(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static PaymentHintKind _paymentHintKind(String? raw) =>
      PaymentHintKind.values.firstWhere(
        (PaymentHintKind k) => k.name == raw,
        orElse: () => PaymentHintKind.unrecognised,
      );
}
