// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:meta/meta.dart';

import '../../../core/documents/app_document.dart';

/// Progress callback for a running download (0.0–1.0, or null when the total
/// size is unknown).
typedef MoodleDownloadProgress = void Function(double? fraction);

/// A cancellation handle passed into a download.
///
/// [whenCancelled] lets the transport abort the request itself. A flag alone
/// was only looked at between body chunks, so a connection that hung before
/// the headers or mid-body could not be cancelled at all.
class MoodleDownloadCancel {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Thrown when a download ends because [MoodleDownloadCancel.cancel] was
/// called. A deliberate stop, not a failure: callers show no error for it.
class MoodleDownloadCancelled implements Exception {
  const MoodleDownloadCancelled();

  @override
  String toString() => 'MoodleDownloadCancelled';
}

/// Port: on-demand download of a single Moodle file.
///
/// The file is fetched only when the user opens it (never preloaded), only from
/// an HTTPS URL on `moodle.hs-anhalt.de`, and the token is attached only for
/// that host. Downloads exceeding [kMaxInMemoryPreviewBytes] fail with
/// [MoodleFailureKind.fileTooLarge]; a cancelled or failed transfer keeps no
/// partial bytes.
abstract interface class MoodleFileDownloader {
  Future<AppDocument> download({
    required String token,
    required String fileUrl,
    required String fileName,
    String? declaredMimeType,
    int? declaredSize,
    MoodleDownloadProgress? onProgress,
    MoodleDownloadCancel? cancel,
  });
}

@immutable
class MoodleDownloadRequest {
  const MoodleDownloadRequest({
    required this.fileUrl,
    required this.fileName,
    this.declaredMimeType,
    this.declaredSize,
  });

  final String fileUrl;
  final String fileName;
  final String? declaredMimeType;
  final int? declaredSize;
}
