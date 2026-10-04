// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One of the exam-overview page's own fixed "Bescheinigungen" print
/// buttons — read from the real page, never assumed to exist. [buttonId] is
/// the button's own id/name on the currently loaded page; it is re-read
/// fresh before every submit rather than cached across page loads.
@immutable
class ExamReportOffer {
  const ExamReportOffer({required this.buttonId, required this.label});

  final String buttonId;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ExamReportOffer &&
      other.buttonId == buttonId &&
      other.label == label;

  @override
  int get hashCode => Object.hash(buttonId, label);
}

/// What came back from submitting one [ExamReportOffer].
sealed class ExamReportDownloadResult {
  const ExamReportDownloadResult();
}

class ExamReportDownloadLoaded extends ExamReportDownloadResult {
  const ExamReportDownloadLoaded({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// Larger than the in-app budget — never downloaded past the limit.
class ExamReportTooLarge extends ExamReportDownloadResult {
  const ExamReportTooLarge();
}

class ExamReportUnavailable extends ExamReportDownloadResult {
  const ExamReportUnavailable(this.reason);

  /// A short technical reason. Never a URL, a token or portal HTML.
  final String reason;
}
