// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The personal, sign-in-based direct services (architecture doc §1.2 / §3.6).
///
/// Deliberately excludes `requests`: that integration is not user-authenticated
/// (architecture.md §1.2), so it has nothing to sign out of.
enum DirectService { mail, moodle, grades }

/// Whether one [DirectService] could be signed out and, if not, why not — never
/// the credential or any response detail.
class DirectServiceSignOutOutcome {
  const DirectServiceSignOutOutcome({
    required this.service,
    required this.success,
  });

  final DirectService service;
  final bool success;
}

/// The result of attempting to sign out of every currently connected direct
/// service. Partial failure is a first-class case: successful sign-outs stay
/// in effect and failed ones are reported so the user can retry just those.
class SignOutEverywhereResult {
  const SignOutEverywhereResult(
    this.outcomes, {
    required this.identityDeleted,
    required this.identityDeletionAttempted,
  });

  final List<DirectServiceSignOutOutcome> outcomes;
  final bool identityDeleted;
  final bool identityDeletionAttempted;

  bool get attemptedAny => outcomes.isNotEmpty || identityDeletionAttempted;

  bool get isFullSuccess => outcomes.every((o) => o.success) && identityDeleted;

  List<DirectService> get failedServices => outcomes
      .where((DirectServiceSignOutOutcome o) => !o.success)
      .map((DirectServiceSignOutOutcome o) => o.service)
      .toList(growable: false);
}
