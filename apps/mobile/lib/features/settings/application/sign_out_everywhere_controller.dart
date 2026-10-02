// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../grades/application/grade_account_controller.dart';
import '../../mail/application/mail_account_controller.dart';
import '../../moodle/application/moodle_account_controller.dart';
import '../../university_account/application/university_account_controller.dart';
import '../../university_account/application/university_service_connector.dart';
import '../domain/direct_service.dart';

/// The direct services that are currently signed in, in a fixed display order.
///
/// Reads the same account controllers the individual feature screens use —
/// there is no separate source of truth to drift out of sync with them.
final Provider<List<DirectService>> connectedDirectServicesProvider =
    Provider<List<DirectService>>((Ref ref) {
      final List<DirectService> connected = <DirectService>[];
      if (ref.watch(mailAccountControllerProvider).value?.isSignedIn ?? false) {
        connected.add(DirectService.mail);
      }
      if (ref.watch(moodleAccountControllerProvider).value != null) {
        connected.add(DirectService.moodle);
      }
      if (ref.watch(gradeAccountControllerProvider).value?.isSignedIn ??
          false) {
        connected.add(DirectService.grades);
      }
      return connected;
    });

/// Signs out of every currently connected direct service through that
/// service's own canonical logout/credential-removal path — never a shortcut
/// that touches its secure storage or cache directly.
///
/// A failure signing out of one service never rolls back or blocks another:
/// each is attempted independently and reported on its own, so a partial
/// result never reads as a full success.
class SignOutEverywhereService {
  SignOutEverywhereService(this._ref);

  final Ref _ref;

  Future<SignOutEverywhereResult> signOutAll() async {
    final UniversityServiceOperationGate gate = _ref.read(
      universityServiceOperationGateProvider,
    );
    await gate.beginCompleteDeletion();
    try {
      return await _signOutAllAfterPendingOperations();
    } finally {
      gate.finishCompleteDeletion();
    }
  }

  Future<SignOutEverywhereResult> _signOutAllAfterPendingOperations() async {
    final List<DirectServiceSignOutOutcome> outcomes =
        <DirectServiceSignOutOutcome>[];
    for (final DirectService service in _ref.read(
      connectedDirectServicesProvider,
    )) {
      final bool success = await _signOut(service);
      outcomes.add(
        DirectServiceSignOutOutcome(service: service, success: success),
      );
    }
    if (outcomes.any(
      (DirectServiceSignOutOutcome outcome) => !outcome.success,
    )) {
      // The central identity is deliberately last. Keeping it makes the failed
      // services retryable and prevents a partial wipe from stranding the user.
      return SignOutEverywhereResult(
        outcomes,
        identityDeleted: false,
        identityDeletionAttempted: false,
      );
    }

    try {
      await _ref
          .read(universityAccountControllerProvider.notifier)
          .deleteIdentity();
      return SignOutEverywhereResult(
        outcomes,
        identityDeleted: true,
        identityDeletionAttempted: true,
      );
    } catch (_) {
      return SignOutEverywhereResult(
        outcomes,
        identityDeleted: false,
        identityDeletionAttempted: true,
      );
    }
  }

  Future<bool> _signOut(DirectService service) async {
    try {
      switch (service) {
        case DirectService.mail:
          await _ref.read(mailAccountControllerProvider.notifier).signOut();
        case DirectService.moodle:
          await _ref
              .read(moodleAccountControllerProvider.notifier)
              .disconnect();
        case DirectService.grades:
          await _ref
              .read(gradeAccountControllerProvider.notifier)
              .deleteEverything();
      }
      return true;
    } catch (_) {
      // Only the classification would ever be useful here, and each
      // controller already keeps its own state signed-in on failure — that is
      // exactly what lets a retry target just the services still connected.
      return false;
    }
  }
}

final Provider<SignOutEverywhereService> signOutEverywhereServiceProvider =
    Provider<SignOutEverywhereService>(
      (Ref ref) => SignOutEverywhereService(ref),
    );
