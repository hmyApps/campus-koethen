// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

/// One label/value pair of the "Personendaten" block — Matrikelnummer,
/// Hörerstatus, Geburtsdatum and the like. Kept generic rather than one field
/// per label: the portal adds and removes fields between cohorts, and a
/// generic pair survives that without a parser change.
@immutable
class PersonalDataField {
  const PersonalDataField({required this.label, required this.value});

  final String label;
  final String value;
}

/// One address/contact tile of the "Kontaktdaten" tab (e.g.
/// "Semesteranschrift", "E-Mail-Adresse").
@immutable
class ContactTile {
  const ContactTile({required this.heading, required this.lines});

  final String heading;

  /// The tile's content lines, already whitespace-normalised. Empty when the
  /// portal shows this tile with nothing filled in — that is a real, valid
  /// state, not a parse failure.
  final List<String> lines;
}

/// One row of "Meine Studiengänge": Fach, Fachsemester, Fachkennzeichen,
/// Prüfungsordnungsversion — read literally, never reinterpreted.
@immutable
class ProgrammeEntry {
  const ProgrammeEntry({
    required this.subject,
    required this.subjectSemester,
    required this.subjectIndicator,
    required this.examinationVersion,
  });

  final String subject;
  final String subjectSemester;
  final String subjectIndicator;
  final String examinationVersion;
}

/// One certificate type offered on the "Bescheinigungen" tab — its
/// availability only, never a generated document.
@immutable
class CertificateOffer {
  const CertificateOffer({required this.name, required this.jobButtonId});

  /// The exact label shown, e.g. "Gebührenbescheinigung".
  final String name;

  /// The exact element id of the button that starts this certificate's AJAX
  /// generation job. Read fresh from the loaded page every time — never
  /// hard-coded, because it is scoped to the current `_flowExecutionKey`.
  final String jobButtonId;
}

/// There is no dedicated "Rückmeldestatus" field anywhere on the portal — it
/// is inferable only from the "Zahlungen" tab's open-items state. [openItems]
/// is therefore a HINT, presented to the reader as one, never as an
/// authoritative status value.
enum PaymentHintKind {
  /// The portal's own "Sie haben keine offenen Zahlungen!" text.
  noneOpen,

  /// At least one row in the open-items table.
  open,

  /// Neither the empty-state text nor the table was recognised.
  unrecognised,
}

@immutable
class PaymentHint {
  const PaymentHint({required this.kind, this.openItemCount});

  final PaymentHintKind kind;

  /// Row count when [kind] is [PaymentHintKind.open]; null otherwise.
  final int? openItemCount;
}

/// Everything read from the "Studienservice" page's tabs in one pass.
///
/// A field being an empty list is a real, valid state (e.g. no certificates
/// configured for this account) — it is [StudentServiceOverview] existing at
/// all, versus a thrown, classified failure, that distinguishes "nothing
/// here" from "the portal changed and this could not be read".
@immutable
class StudentServiceOverview {
  const StudentServiceOverview({
    required this.personalData,
    required this.hoererstatus,
    required this.contactTiles,
    required this.programmes,
    required this.certificates,
    required this.paymentHint,
    required this.fetchedAt,
  });

  final List<PersonalDataField> personalData;

  /// Convenience pull-out of the "Hörerstatus" row of [personalData] — the
  /// closest the portal has to an enrolment-status field. Null when that
  /// label was not present among the fields actually read.
  final String? hoererstatus;

  final List<ContactTile> contactTiles;
  final List<ProgrammeEntry> programmes;
  final List<CertificateOffer> certificates;
  final PaymentHint paymentHint;
  final DateTime fetchedAt;
}
