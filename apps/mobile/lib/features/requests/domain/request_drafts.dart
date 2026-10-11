// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';

import 'application_files.dart';
import 'idempotency_key.dart';

/// The two kinds of submission this area handles.
///
/// They share almost nothing — different endpoint, different content type,
/// different fields, files on one side and none on the other — so they are
/// separate types below rather than one model with fields that are impossible
/// for half its instances.
enum RequestKind {
  financeApplication('finance-application'),
  feedback('feedback');

  const RequestKind(this.storageValue);

  /// Stable identifier written to local storage, never the enum index.
  final String storageValue;

  static RequestKind? fromStorage(String? value) {
    for (final RequestKind kind in RequestKind.values) {
      if (kind.storageValue == value) return kind;
    }
    return null;
  }
}

/// A file the user picked to send along.
///
/// Only a reference. The bytes live in the app's **encrypted** attachment
/// store, and [path] is the identifier inside it — not a plaintext file the
/// rest of the system could read.
@immutable
class RequestAttachment {
  const RequestAttachment({
    required this.fileName,
    required this.path,
    this.sizeBytes,
  });

  final String fileName;

  /// Identifier in the encrypted attachment store.
  final String path;

  final int? sizeBytes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fileName': fileName,
    'path': path,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
  };

  static RequestAttachment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final Object? name = json['fileName'];
    final Object? path = json['path'];
    if (name is! String || path is! String) return null;
    return RequestAttachment(
      fileName: name,
      path: path,
      sizeBytes: json['sizeBytes'] is int ? json['sizeBytes'] as int : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RequestAttachment &&
      other.fileName == fileName &&
      other.path == path;

  @override
  int get hashCode => Object.hash(fileName, path);

  /// Never the path — this is what ends up in a log line.
  @override
  String toString() => 'RequestAttachment($fileName)';
}

/// A send attempt whose outcome the device never learned.
///
/// A timeout, a dropped connection or an ambiguous 5xx leaves one question
/// open that the app cannot answer by itself: did the submission arrive? The
/// idempotency key answers it — resending the **same key with the same data**
/// replays the original answer instead of filing a second application.
///
/// That guarantee has two conditions, and this type exists to hold both:
///
/// * **The data must not change.** While this is set, its draft is frozen. The
///   editor refuses edits rather than letting somebody adjust a sentence and
///   resend under a key that now means something else — which the endpoint
///   answers with 409, and which would be a genuine second application if the
///   key had already expired.
/// * **The key must still exist server-side.** Keys are kept for 30 days.
///   After that a retry is an ordinary new submission and files a second case,
///   so past [expiresAt] the app stops promising duplicate-free retries and
///   asks the user to decide.
@immutable
class PendingSubmission {
  const PendingSubmission({
    required this.firstAttemptAt,
    required this.fingerprint,
  });

  /// When the payload first went out — the clock the 30-day window runs on.
  final DateTime firstAttemptAt;

  /// A digest of exactly what was sent.
  ///
  /// Belt and braces next to the freeze: a retry recomputes it and refuses to
  /// send under the same key if it no longer matches, so a bug that mutates a
  /// frozen draft cannot turn into a silent duplicate.
  final String fingerprint;

  /// How long the receiving system keeps an idempotency key.
  static const Duration keyRetention = Duration(days: 30);

  DateTime get expiresAt => firstAttemptAt.add(keyRetention);

  /// Whether a retry can still be promised to be duplicate-free.
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'firstAttemptAt': firstAttemptAt.toIso8601String(),
    'fingerprint': fingerprint,
  };

  static PendingSubmission? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final DateTime? at = DateTime.tryParse(
      json['firstAttemptAt'] is String ? json['firstAttemptAt'] as String : '',
    );
    final Object? fingerprint = json['fingerprint'];
    if (at == null || fingerprint is! String) return null;
    return PendingSubmission(firstAttemptAt: at, fingerprint: fingerprint);
  }
}

/// A locally stored, editable draft.
///
/// Drafts are user-authored data rather than a cache, so nothing here is ever
/// discarded to make room. They stay on the device until the user submits or
/// deletes one.
@immutable
sealed class RequestDraft {
  const RequestDraft({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.idempotencyKey,
    this.pending,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Generated once, when the draft is created, and kept for its whole life.
  ///
  /// This is what makes a retry safe: resending after a timeout carries the
  /// same key, so the receiving system replays its original answer instead of
  /// filing a second case. Generating it at send time would break exactly the
  /// case it exists for.
  final String idempotencyKey;

  /// Set once a send attempt ended without a verdict. See [PendingSubmission].
  final PendingSubmission? pending;

  RequestKind get kind;

  /// Whether this draft holds anything worth keeping.
  bool get isEmpty;

  /// A frozen draft is waiting on the outcome of a send attempt and must not
  /// be edited — see [PendingSubmission].
  bool get isFrozen => pending != null;

  /// What the retry guarantee is computed over: the exact normalised payload.
  ///
  /// Deliberately excludes ids, timestamps and the key itself — two drafts
  /// that would produce byte-identical requests must produce the same value.
  String get payloadFingerprint;

  Map<String, dynamic> toJson();

  /// Reads whatever version of a draft is on disk.
  ///
  /// Defensive by design: this is the migration path for drafts written before
  /// the real API was known. Fields that no longer exist are dropped, fields
  /// that still mean the same thing are carried over, and anything unreadable
  /// yields `null` rather than a half-restored draft.
  static RequestDraft? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final RequestKind? kind = RequestKind.fromStorage(
      json['kind'] is String ? json['kind'] as String : null,
    );
    return switch (kind) {
      RequestKind.financeApplication => FinanceApplicationDraft.fromJson(json),
      RequestKind.feedback => FeedbackDraft.fromJson(json),
      null => null,
    };
  }

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value is String ? value : '') ?? DateTime(2026);

  static String _string(Object? value) => value is String ? value : '';

  /// A stored key is untrusted input too — one written by an older version, or
  /// hand-edited, must not turn into a 400 that reads like a server fault.
  static String _key(Object? value) =>
      IdempotencyKey.isValid(value is String ? value : null)
      ? value! as String
      : IdempotencyKey.generate();
}

/// A request for money, submitted as `multipart/form-data`.
///
/// Exactly the five documented fields plus two optional annexes. There is no
/// amount, no category, no purpose and no contact address: the endpoint does
/// not take them, and the numbers live inside the attached PDF where the
/// committee expects them.
@immutable
class FinanceApplicationDraft extends RequestDraft {
  const FinanceApplicationDraft({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    required super.idempotencyKey,
    super.pending,
    this.locationId,
    this.title = '',
    this.applicant = '',
    this.files = const <ApplicationFileSlot, RequestAttachment>{},
  });

  /// Which board the application is addressed to. Comes from the endpoint's
  /// own list; never invented here.
  final int? locationId;

  /// Subject of the application — the wire field `title`.
  final String title;

  /// Name of the person applying — the wire field `applicant`.
  final String applicant;

  /// The picked file per multipart slot.
  final Map<ApplicationFileSlot, RequestAttachment> files;

  /// Both wire fields are capped at 200 characters by the endpoint.
  static const int textMaxLength = 200;

  @override
  RequestKind get kind => RequestKind.financeApplication;

  RequestAttachment? fileFor(ApplicationFileSlot slot) => files[slot];

  @override
  bool get isEmpty =>
      title.trim().isEmpty &&
      applicant.trim().isEmpty &&
      locationId == null &&
      files.isEmpty;

  @override
  String get payloadFingerprint => <String>[
    'application',
    '${locationId ?? ''}',
    title.trim(),
    applicant.trim(),
    for (final ApplicationFileSlot slot in ApplicationFileSlot.values)
      '${slot.field}=${files[slot]?.path ?? ''}:${files[slot]?.sizeBytes ?? ''}',
  ].join('\u0000');

  FinanceApplicationDraft copyWith({
    String? title,
    String? applicant,
    int? locationId,
    bool clearLocation = false,
    Map<ApplicationFileSlot, RequestAttachment>? files,
    DateTime? updatedAt,
    PendingSubmission? pending,
    bool clearPending = false,
  }) => FinanceApplicationDraft(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    // Never replaced: a new key would turn a retry into a second application.
    idempotencyKey: idempotencyKey,
    pending: clearPending ? null : (pending ?? this.pending),
    locationId: clearLocation ? null : (locationId ?? this.locationId),
    title: title ?? this.title,
    applicant: applicant ?? this.applicant,
    files: files ?? this.files,
  );

  /// This draft released from its pending attempt, under a **new** key.
  ///
  /// Only for the person's explicit decision to send it as a new case: the
  /// old key belongs to an attempt that may already have become a case, and
  /// an edited payload under it would only earn a 409.
  FinanceApplicationDraft asNewCase({required String idempotencyKey}) =>
      FinanceApplicationDraft(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        idempotencyKey: idempotencyKey,
        locationId: locationId,
        title: title,
        applicant: applicant,
        files: files,
      );

  /// Replaces or clears one slot.
  FinanceApplicationDraft withFile(
    ApplicationFileSlot slot,
    RequestAttachment? file,
  ) {
    final Map<ApplicationFileSlot, RequestAttachment> next =
        Map<ApplicationFileSlot, RequestAttachment>.of(files);
    if (file == null) {
      next.remove(slot);
    } else {
      next[slot] = file;
    }
    return copyWith(files: next);
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.storageValue,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'idempotencyKey': idempotencyKey,
    if (pending != null) 'pending': pending!.toJson(),
    if (locationId != null) 'locationId': locationId,
    'title': title,
    'applicant': applicant,
    'files': <String, dynamic>{
      for (final MapEntry<ApplicationFileSlot, RequestAttachment> entry
          in files.entries)
        entry.key.field: entry.value.toJson(),
    },
  };

  static FinanceApplicationDraft? fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String) return null;

    final Map<ApplicationFileSlot, RequestAttachment> files =
        <ApplicationFileSlot, RequestAttachment>{};
    if (json['files'] is Map) {
      (json['files'] as Map<Object?, Object?>).forEach((Object? k, Object? v) {
        final ApplicationFileSlot? slot = ApplicationFileSlot.fromStorage(
          k is String ? k : null,
        );
        final RequestAttachment? file = RequestAttachment.fromJson(v);
        if (slot != null && file != null) files[slot] = file;
      });
    }

    return FinanceApplicationDraft(
      id: id,
      createdAt: RequestDraft._date(json['createdAt']),
      updatedAt: RequestDraft._date(json['updatedAt']),
      idempotencyKey: RequestDraft._key(json['idempotencyKey']),
      pending: PendingSubmission.fromJson(json['pending']),
      // Carried over from older drafts unchanged — these three still mean
      // exactly what they used to. Everything else that version wrote
      // (category, amount, purpose, description, contact details) is dropped:
      // the endpoint has no such fields, so keeping them would only preserve
      // the illusion that they are going to be sent.
      locationId: json['locationId'] is int ? json['locationId'] as int : null,
      title: RequestDraft._string(json['title']),
      applicant: RequestDraft._string(json['applicant']),
      files: files,
    );
  }
}

/// Feedback for the committee, submitted as `application/json`.
///
/// No attachments — the endpoint takes none — and no title: the receiving
/// system derives the card title from the text itself.
@immutable
class FeedbackDraft extends RequestDraft {
  const FeedbackDraft({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    required super.idempotencyKey,
    super.pending,
    this.areaId,
    this.submitterName = '',
    this.feedback = '',
  });

  /// Which area the feedback goes to. From the endpoint's own list only.
  final int? areaId;

  /// Optional. Left blank, the committee records the feedback as anonymous —
  /// so the field is simply omitted rather than filled in with a word the
  /// user did not type.
  final String submitterName;

  final String feedback;

  static const int nameMaxLength = 200;
  static const int textMaxLength = 10000;

  @override
  RequestKind get kind => RequestKind.feedback;

  /// The value to send, or `null` when the field must be left out entirely.
  String? get wireSubmitterName {
    final String trimmed = submitterName.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool get isEmpty =>
      feedback.trim().isEmpty && submitterName.trim().isEmpty && areaId == null;

  @override
  String get payloadFingerprint => <String>[
    'feedback',
    '${areaId ?? ''}',
    wireSubmitterName ?? '',
    feedback.trim(),
  ].join('\u0000');

  FeedbackDraft copyWith({
    int? areaId,
    bool clearArea = false,
    String? submitterName,
    String? feedback,
    DateTime? updatedAt,
    PendingSubmission? pending,
    bool clearPending = false,
  }) => FeedbackDraft(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    idempotencyKey: idempotencyKey,
    pending: clearPending ? null : (pending ?? this.pending),
    areaId: clearArea ? null : (areaId ?? this.areaId),
    submitterName: submitterName ?? this.submitterName,
    feedback: feedback ?? this.feedback,
  );

  /// See [FinanceApplicationDraft.asNewCase].
  FeedbackDraft asNewCase({required String idempotencyKey}) => FeedbackDraft(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt,
    idempotencyKey: idempotencyKey,
    areaId: areaId,
    submitterName: submitterName,
    feedback: feedback,
  );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.storageValue,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'idempotencyKey': idempotencyKey,
    if (pending != null) 'pending': pending!.toJson(),
    if (areaId != null) 'areaId': areaId,
    'submitterName': submitterName,
    'feedback': feedback,
  };

  static FeedbackDraft? fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String) return null;

    // An older draft kept its text in `description`. That is the one field
    // worth carrying over — its `category` was an app-side label and must NOT
    // be read as an areaId: the numbers belong to different vocabularies, and
    // guessing would file the feedback with whichever board holds that id.
    final String text = json['feedback'] is String
        ? json['feedback'] as String
        : RequestDraft._string(json['description']);

    return FeedbackDraft(
      id: id,
      createdAt: RequestDraft._date(json['createdAt']),
      updatedAt: RequestDraft._date(json['updatedAt']),
      idempotencyKey: RequestDraft._key(json['idempotencyKey']),
      pending: PendingSubmission.fromJson(json['pending']),
      areaId: json['areaId'] is int ? json['areaId'] as int : null,
      submitterName: RequestDraft._string(json['submitterName']),
      feedback: text,
    );
  }
}
