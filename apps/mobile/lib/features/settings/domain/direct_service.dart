// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The personal, sign-in-based direct services (architecture doc §1.2 / §3.6).
///
/// Deliberately excludes `requests`: that integration is not user-authenticated
/// (architecture.md §1.2), so it has nothing to sign out of.
enum DirectService {
  mail,
  moodle,
  grades,
  nextcloud,
  hsaKi;

  /// Nextcloud intentionally uses Login Flow v2 instead of receiving the
  /// centrally retained university password.
  bool get usesUniversityIdentity => this != DirectService.nextcloud;

  static List<DirectService> get universityIdentityServices => values
      .where((DirectService service) => service.usesUniversityIdentity)
      .toList(growable: false);

  /// The services offered in the first-run, bulk-connect onboarding step.
  ///
  /// HSA-GPT deliberately has its own dedicated consent screen (what it is,
  /// that it is a direct connection to Hochschule Anhalt's own AI service,
  /// what is stored) rather than a plain checkbox in a list of unrelated
  /// services — so it is never offered here, only from its own module.
  static List<DirectService> get onboardingWizardServices => values
      .where((DirectService service) => service != DirectService.hsaKi)
      .toList(growable: false);
}

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

/// The result of attempting the canonical wipe for every direct service,
/// regardless of its currently observable connection state. Partial failure
/// is a first-class case: successful wipes stay in effect and failed ones are
/// reported so the user can retry.
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
