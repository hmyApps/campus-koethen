// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

enum NextcloudFailureKind {
  canceled,
  browserLaunchFailed,
  loginTimedOut,
  loginRejected,
  networkUnavailable,
  timeout,
  tlsOrHostRejected,
  serviceUnavailable,
  permissionDenied,
  invalidResponse,
  secureStorageUnavailable,
  notConnected,
  fileTooLarge,
  downloadFailed,
  unknown,
}

/// Classified only: URLs, tokens, paths and server bodies never enter errors.
@immutable
class NextcloudFailure implements Exception {
  const NextcloudFailure(this.kind);

  final NextcloudFailureKind kind;

  @override
  String toString() => 'NextcloudFailure(${kind.name})';

  @override
  bool operator ==(Object other) =>
      other is NextcloudFailure && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}
