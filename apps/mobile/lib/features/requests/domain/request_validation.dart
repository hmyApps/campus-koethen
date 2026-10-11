// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

// `characters` is re-exported by the widgets library; only the extension is
// used, nothing that touches the widget tree.
import 'package:flutter/widgets.dart' show StringCharacters;

import 'application_files.dart';
import 'request_drafts.dart';

/// Which field failed, and why.
///
/// A typed enum rather than a message: the reason belongs to the domain, the
/// wording belongs to `gen_l10n`. That also keeps validation testable without
/// pulling a BuildContext into it.
enum RequestFieldError {
  locationMissing,
  titleMissing,
  titleTooLong,
  applicantMissing,
  applicantTooLong,
  requiredFileMissing,
  fileWrongType,
  fileTooLarge,
  areaMissing,
  submitterNameTooLong,
  feedbackMissing,
  feedbackTooLong,
}

/// Which field an error belongs to.
///
/// Exactly the fields the two forms actually have. The wire names are kept
/// next to them so a server-side `issues[].field` can be mapped onto the form
/// without a second table that could drift apart from this one.
enum RequestField {
  location(wire: 'locationId'),
  title(wire: 'title'),
  applicant(wire: 'applicant'),
  financeRequestFile(wire: 'finance_request'),
  studentCardFile(wire: 'student_card'),
  annexAFile(wire: 'annex_a'),
  annexBFile(wire: 'annex_b'),
  area(wire: 'areaId'),
  submitterName(wire: 'submitterName'),
  feedback(wire: 'feedback');

  const RequestField({required this.wire});

  /// The name the endpoint uses for this field.
  final String wire;

  /// The form field a server-side issue refers to, or `null` when the endpoint
  /// named something this build does not know — that one is shown as a general
  /// message rather than silently dropped.
  static RequestField? fromWire(String? field) {
    for (final RequestField value in RequestField.values) {
      if (value.wire == field) return value;
    }
    return null;
  }

  /// The form field belonging to a file slot.
  static RequestField forSlot(ApplicationFileSlot slot) => switch (slot) {
    ApplicationFileSlot.financeRequest => RequestField.financeRequestFile,
    ApplicationFileSlot.studentCard => RequestField.studentCardFile,
    ApplicationFileSlot.annexA => RequestField.annexAFile,
    ApplicationFileSlot.annexB => RequestField.annexBFile,
  };
}

/// The result of validating a draft.
class RequestValidation {
  const RequestValidation(this.errors);

  final Map<RequestField, RequestFieldError> errors;

  bool get isValid => errors.isEmpty;

  RequestFieldError? errorFor(RequestField field) => errors[field];

  /// Validates a draft for **submission**.
  ///
  /// Saving deliberately does not go through this: a half-written application
  /// is exactly what a draft is for. Only the attempt to send has to be
  /// complete. The server remains the authority — this exists so the form can
  /// point at a field instead of relaying a message with no anchor.
  static RequestValidation validate(RequestDraft draft) => switch (draft) {
    FinanceApplicationDraft() => _application(draft),
    FeedbackDraft() => _feedback(draft),
  };

  static RequestValidation _application(FinanceApplicationDraft draft) {
    final Map<RequestField, RequestFieldError> errors =
        <RequestField, RequestFieldError>{};

    if (draft.locationId == null) {
      errors[RequestField.location] = RequestFieldError.locationMissing;
    }

    final String title = draft.title.trim();
    if (title.isEmpty) {
      errors[RequestField.title] = RequestFieldError.titleMissing;
    } else if (_length(title) > FinanceApplicationDraft.textMaxLength) {
      errors[RequestField.title] = RequestFieldError.titleTooLong;
    }

    final String applicant = draft.applicant.trim();
    if (applicant.isEmpty) {
      errors[RequestField.applicant] = RequestFieldError.applicantMissing;
    } else if (_length(applicant) > FinanceApplicationDraft.textMaxLength) {
      errors[RequestField.applicant] = RequestFieldError.applicantTooLong;
    }

    for (final ApplicationFileSlot slot in ApplicationFileSlot.values) {
      final RequestField field = RequestField.forSlot(slot);
      final RequestAttachment? file = draft.fileFor(slot);
      if (file == null) {
        if (slot.isRequired) {
          errors[field] = RequestFieldError.requiredFileMissing;
        }
        continue;
      }
      if (!slot.accepts(file.fileName)) {
        errors[field] = RequestFieldError.fileWrongType;
        continue;
      }
      final int? size = file.sizeBytes;
      if (size != null && !slot.acceptsSize(size)) {
        errors[field] = RequestFieldError.fileTooLarge;
      }
    }

    return RequestValidation(errors);
  }

  /// User-perceived characters, the unit `TextField.maxLength` counts in.
  ///
  /// Counting UTF-16 units here flagged an emoji title as too long that the
  /// field itself had accepted, leaving no way to tell what to shorten.
  static int _length(String value) => value.characters.length;

  static RequestValidation _feedback(FeedbackDraft draft) {
    final Map<RequestField, RequestFieldError> errors =
        <RequestField, RequestFieldError>{};

    if (draft.areaId == null) {
      errors[RequestField.area] = RequestFieldError.areaMissing;
    }

    // Optional by design — only a *given* name has to fit.
    if (_length(draft.submitterName.trim()) > FeedbackDraft.nameMaxLength) {
      errors[RequestField.submitterName] =
          RequestFieldError.submitterNameTooLong;
    }

    final String text = draft.feedback.trim();
    if (text.isEmpty) {
      errors[RequestField.feedback] = RequestFieldError.feedbackMissing;
    } else if (_length(text) > FeedbackDraft.textMaxLength) {
      errors[RequestField.feedback] = RequestFieldError.feedbackTooLong;
    }

    return RequestValidation(errors);
  }
}
