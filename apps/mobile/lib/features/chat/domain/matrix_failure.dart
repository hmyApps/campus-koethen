// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

enum MatrixFailureKind {
  /// No usable `MATRIX_HOMESERVER_URL` in this build.
  notConfigured,

  /// The homeserver offers no login this app supports.
  unsupportedServer,
  invalidCredentials,
  networkUnavailable,
  timeout,

  /// TLS failed, or a request targeted any origin but the configured one.
  tlsOrHostRejected,
  serviceUnavailable,
  rateLimited,
  invalidResponse,
  secureStorageUnavailable,

  /// The encrypted local database could not be opened or written.
  databaseUnavailable,

  /// End-to-end encryption is not available on this device.
  encryptionUnavailable,
  notConnected,
  sendFailed,
  unknown,
}

/// Classified only: server bodies, IDs, tokens and message text never enter
/// errors.
@immutable
class MatrixFailure implements Exception {
  const MatrixFailure(this.kind);

  final MatrixFailureKind kind;

  @override
  String toString() => 'MatrixFailure(${kind.name})';

  @override
  bool operator ==(Object other) =>
      other is MatrixFailure && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}
