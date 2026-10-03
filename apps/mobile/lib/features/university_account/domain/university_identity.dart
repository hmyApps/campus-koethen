// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

/// The shared local university identity entered by the user.
///
/// The university's own login accepts either the account's username or its
/// email address interchangeably, for every direct service (mail, Moodle,
/// HISinOne/HIS-QIS) — there are not two separate secrets to collect. This
/// holds exactly the one string the user typed, in whichever form they had
/// it, plus the one password that goes with it. Moodle and grades receive
/// [identifier] unchanged. Mail requires a complete sender address as well as
/// a login, so only its adapter expands a bare identifier to
/// `<identifier>@hs-anhalt.de`; an already complete address remains unchanged.
///
/// This is a credential convenience, not an SSO session. Each connected
/// service still creates and deletes its own protocol-specific credentials.
/// Instances may only cross the application/storage boundary and must never be
/// put into public Riverpod state, logs, analytics or error messages.
@immutable
class UniversityIdentity {
  const UniversityIdentity({required this.identifier, required this.password});

  /// The account's username or email address, exactly as entered.
  final String identifier;
  final String password;

  UniversityIdentity get normalized =>
      UniversityIdentity(identifier: identifier.trim(), password: password);

  bool get isValid {
    final UniversityIdentity value = normalized;
    return value.identifier.isNotEmpty && value.password.isNotEmpty;
  }

  @override
  bool operator ==(Object other) =>
      other is UniversityIdentity &&
      other.identifier == identifier &&
      other.password == password;

  @override
  int get hashCode => Object.hash(identifier, password);

  @override
  String toString() => 'UniversityIdentity(<redacted>)';
}

enum UniversityAccountFailureKind {
  invalidIdentity,
  identityMissing,
  secureStorageUnavailable,
  operationBlocked,
  connectionRollbackIncomplete,
  accountChangeCleanupIncomplete,
  accountChangeRollbackIncomplete,
}

/// Safe, deliberately detail-free failure at the university identity boundary.
@immutable
class UniversityAccountFailure implements Exception {
  const UniversityAccountFailure(this.kind);

  final UniversityAccountFailureKind kind;

  @override
  bool operator ==(Object other) =>
      other is UniversityAccountFailure && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'UniversityAccountFailure(${kind.name})';
}
