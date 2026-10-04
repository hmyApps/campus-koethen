// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

enum HsaKiFailureKind {
  invalidCredentials,
  portalUnavailable,
  portalStructureChanged,
  tlsOrHostRejected,
  timeout,
  networkUnavailable,

  /// The instance's own `ExtAppConfig` has external-app/API-token access
  /// turned off — an organisational setting on HSA's side, not a bug here.
  externalAccessDisabled,
  secureStorageUnavailable,
  notConnected,
  unknown,
}

/// Classified only: credentials, tokens, prompts and server bodies never
/// enter errors.
@immutable
class HsaKiFailure implements Exception {
  const HsaKiFailure(this.kind);

  final HsaKiFailureKind kind;

  @override
  String toString() => 'HsaKiFailure(${kind.name})';

  @override
  bool operator ==(Object other) => other is HsaKiFailure && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}
