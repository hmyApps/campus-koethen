// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

enum HsaKiFailureKind {
  invalidCredentials,

  /// The credentials were correct and HAWKI's own login endpoint answered
  /// `success: true`, but with `redirectUri: "/register"` instead of
  /// `"/handshake"` — confirmed from HAWKI's own `AuthenticationController
  /// ::handleLogin` source: that branch is taken precisely when no HAWKI
  /// user row exists yet for this account, and it never calls `Auth::
  /// login()`. The account is real, but this is its first-ever HAWKI
  /// contact; it must complete the one-time registration in a browser at
  /// ki.hs-anhalt.de before a token can be minted here.
  notRegistered,
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

  /// A token mint was requested outside the dedicated HSA-GPT consent flow.
  consentRequired,
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
