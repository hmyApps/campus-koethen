// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';

import 'request_drafts.dart';

/// One publicly visible file of a case.
///
/// Exactly the documents the public web view offers. The student card is never
/// among them — the receiving system processes it internally and does not
/// expose it — so the app neither shows nor expects one.
@immutable
class StatusDocument {
  const StatusDocument({
    required this.kind,
    required this.label,
    required this.filename,
    required this.mimeType,
    required this.downloadUrl,
  });

  /// `finance_request`, `annex_a`, `annex_b` or `other`. Kept as the server's
  /// own string: a new kind must show up as a document, not disappear because
  /// an enum did not know it.
  final String kind;

  final String label;

  /// The server's file name, or `null` when it sent none — the presentation
  /// layer then names it from the string table (AGENTS.md §6).
  final String? filename;
  final String mimeType;

  /// Token-protected link. Carries the same secret as the status link and is
  /// treated the same way — never logged, never shared, never opened anywhere
  /// but against the configured origin.
  final String downloadUrl;

  static StatusDocument? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final Object? kind = json['kind'];
    final Object? label = json['label'];
    final Object? filename = json['filename'];
    final Object? mimeType = json['mimeType'];
    final Object? downloadUrl = json['downloadUrl'];
    if (kind is! String || downloadUrl is! String) return null;
    if (downloadUrl.trim().isEmpty) return null;
    return StatusDocument(
      kind: kind,
      label: label is String && label.trim().isNotEmpty
          ? label
          : (filename is String ? filename : kind),
      filename: filename is String && filename.trim().isNotEmpty
          ? filename
          : null,
      mimeType: mimeType is String && mimeType.trim().isNotEmpty
          ? mimeType
          : 'application/octet-stream',
      downloadUrl: downloadUrl,
    );
  }

  static List<StatusDocument> listFrom(Object? json) {
    if (json is! List) return const <StatusDocument>[];
    return json
        .map(StatusDocument.fromJson)
        .whereType<StatusDocument>()
        .toList(growable: false);
  }

  /// Never the download URL — it is a credential.
  @override
  String toString() => 'StatusDocument($kind)';
}

/// What the public web view currently offers.
///
/// This endpoint only *reports* the actions; performing them happens on the
/// web. There is no public API for uploading a resubmission or a receipt, so
/// the app states what is possible and does not pretend to be able to do it.
@immutable
class StatusActions {
  const StatusActions({
    required this.canUploadDocuments,
    required this.submitMode,
  });

  final bool canUploadDocuments;

  /// `resubmission`, `receipt`, or `null` for no submit button. Kept as the
  /// server's string for the same reason as [StatusDocument.kind].
  final String? submitMode;

  static const StatusActions none = StatusActions(
    canUploadDocuments: false,
    submitMode: null,
  );

  static StatusActions fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return none;
    final Object? canUpload = json['canUploadDocuments'];
    final Object? mode = json['submitMode'];
    return StatusActions(
      canUploadDocuments: canUpload is bool && canUpload,
      submitMode: mode is String && mode.trim().isNotEmpty ? mode : null,
    );
  }
}

/// The current state of a case, as the public status endpoint describes it.
///
/// Sealed over the two discriminated response types. The **status name is the
/// server's own string** and is never forced into a fixed enum: the committee
/// names its board columns, those names change, and an app-side
/// accepted/rejected vocabulary would report something the committee never
/// said. For applications, `archived` is the reliable completion signal.
@immutable
sealed class CaseStatus {
  const CaseStatus({
    required this.statusUrl,
    required this.receiptPdfUrl,
    required this.number,
    required this.submittedAt,
    required this.updatedAt,
    required this.statusName,
    required this.publicNote,
    required this.documents,
    required this.actions,
  });

  /// Canonical status link, rebuilt by the server. Secret.
  final String statusUrl;

  /// Receipt PDF. Carries the same token and is equally secret.
  final String receiptPdfUrl;

  final String? number;
  final DateTime submittedAt;
  final DateTime updatedAt;

  /// Public name of the current column, or `null` when the board gives none.
  final String? statusName;

  /// A note the committee deliberately made public. Internal notes never
  /// appear here.
  final String? publicNote;

  final List<StatusDocument> documents;
  final StatusActions actions;

  RequestKind get kind;

  /// Parses either response type.
  ///
  /// Defensive throughout: an unknown `type`, a missing required field or a
  /// malformed timestamp yields `null` rather than a half-built status that
  /// would be shown as if it were current. Unknown *extra* fields are ignored,
  /// so the server can grow without breaking older builds.
  static CaseStatus? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return switch (json['type']) {
      'application' => ApplicationCaseStatus.fromJson(json),
      'feedback' => FeedbackCaseStatus.fromJson(json),
      _ => null,
    };
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  /// Never the links — this is what ends up in a log line.
  @override
  String toString() => '$runtimeType(number: $number, status: $statusName)';
}

/// Status of a finance application.
@immutable
class ApplicationCaseStatus extends CaseStatus {
  const ApplicationCaseStatus({
    required super.statusUrl,
    required super.receiptPdfUrl,
    required super.number,
    required super.submittedAt,
    required super.updatedAt,
    required super.statusName,
    required super.publicNote,
    required super.documents,
    required super.actions,
    required this.title,
    required this.applicant,
    required this.resubmittedAt,
    required this.archived,
  });

  /// Subject of the application.
  final String title;

  final String? applicant;

  /// When a public resubmission was filed, if one was.
  final DateTime? resubmittedAt;

  /// The case sits in the archive column and is publicly finished. This is the
  /// reliable completion flag — the column *name* is free text.
  final bool archived;

  @override
  RequestKind get kind => RequestKind.financeApplication;

  static ApplicationCaseStatus? fromJson(Map<String, dynamic> json) {
    final String? statusUrl = CaseStatus._text(json['statusUrl']);
    final String? receipt = CaseStatus._text(json['receiptPdfUrl']);
    final DateTime? submittedAt = CaseStatus._date(json['submittedAt']);
    final DateTime? updatedAt = CaseStatus._date(json['updatedAt']);
    if (statusUrl == null || receipt == null) return null;
    if (submittedAt == null || updatedAt == null) return null;

    final Object? application = json['application'];
    final Map<String, dynamic> app = application is Map<String, dynamic>
        ? application
        : const <String, dynamic>{};
    final Object? status = json['status'];
    final Map<String, dynamic> st = status is Map<String, dynamic>
        ? status
        : const <String, dynamic>{};

    return ApplicationCaseStatus(
      statusUrl: statusUrl,
      receiptPdfUrl: receipt,
      number: CaseStatus._text(json['number']),
      submittedAt: submittedAt,
      updatedAt: updatedAt,
      statusName: CaseStatus._text(st['name']),
      publicNote: CaseStatus._text(json['publicNote']),
      documents: StatusDocument.listFrom(json['documents']),
      actions: StatusActions.fromJson(json['availableActions']),
      title: CaseStatus._text(app['title']) ?? '',
      applicant: CaseStatus._text(app['applicant']),
      resubmittedAt: CaseStatus._date(st['resubmittedAt']),
      archived: st['archived'] is bool && st['archived'] as bool,
    );
  }
}

/// Status of a feedback submission.
///
/// Area, name and text come from an immutable snapshot taken at submission
/// time — later internal edits do not change what the submitter sees.
@immutable
class FeedbackCaseStatus extends CaseStatus {
  const FeedbackCaseStatus({
    required super.statusUrl,
    required super.receiptPdfUrl,
    required super.number,
    required super.submittedAt,
    required super.updatedAt,
    required super.statusName,
    required super.publicNote,
    required super.documents,
    required super.actions,
    required this.area,
    required this.submitterName,
    required this.text,
  });

  final String area;

  /// The name as recorded, which is the committee's word for "anonymous" when
  /// none was given — not something the app substitutes.
  final String submitterName;

  final String text;

  @override
  RequestKind get kind => RequestKind.feedback;

  static FeedbackCaseStatus? fromJson(Map<String, dynamic> json) {
    final String? statusUrl = CaseStatus._text(json['statusUrl']);
    final String? receipt = CaseStatus._text(json['receiptPdfUrl']);
    final DateTime? submittedAt = CaseStatus._date(json['submittedAt']);
    final DateTime? updatedAt = CaseStatus._date(json['updatedAt']);
    if (statusUrl == null || receipt == null) return null;
    if (submittedAt == null || updatedAt == null) return null;

    final Object? feedback = json['feedback'];
    final Map<String, dynamic> fb = feedback is Map<String, dynamic>
        ? feedback
        : const <String, dynamic>{};
    final Object? status = json['status'];
    final Map<String, dynamic> st = status is Map<String, dynamic>
        ? status
        : const <String, dynamic>{};

    return FeedbackCaseStatus(
      statusUrl: statusUrl,
      receiptPdfUrl: receipt,
      number: CaseStatus._text(json['number']),
      submittedAt: submittedAt,
      updatedAt: updatedAt,
      statusName: CaseStatus._text(st['name']),
      publicNote: CaseStatus._text(json['publicNote']),
      documents: StatusDocument.listFrom(json['documents']),
      actions: StatusActions.fromJson(json['availableActions']),
      area: CaseStatus._text(fb['area']) ?? '',
      submitterName: CaseStatus._text(fb['submitterName']) ?? '',
      text: fb['text'] is String ? fb['text'] as String : '',
    );
  }
}
