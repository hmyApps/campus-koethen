// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../grades/application/grade_account_controller.dart';
import '../../mail/application/mail_account_controller.dart';
import '../../moodle/application/moodle_account_controller.dart';
import '../../nextcloud/application/nextcloud_account_controller.dart';
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
      if (ref.watch(nextcloudAccountControllerProvider).value != null) {
        connected.add(DirectService.nextcloud);
      }
      return connected;
    });

/// Signs out of every direct service through that service's own canonical
/// logout/credential-removal path — never a shortcut that touches its secure
/// storage or cache directly.
///
/// The connection snapshot is display-only and deliberately not trusted here:
/// a controller can be loading or in error while credentials still exist. A
/// failure signing out of one service never blocks another, and every outcome
/// is reported so a partial result never reads as a full success.
class SignOutEverywhereService {
  SignOutEverywhereService(this._ref);

  final Ref _ref;

  Future<SignOutEverywhereResult> signOutAll() async {
    // A Login Flow may otherwise keep the gate active for up to 20 minutes.
    // Cancel it before waiting, and let its generation guard reject any late
    // poll callback before the credential store can be written.
    _ref.read(nextcloudAccountControllerProvider.notifier).cancelPendingLogin();
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
    for (final DirectService service in DirectService.values) {
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
      await _ref.read(universityServiceAdapterProvider(service)).disconnect();
      return true;
    } catch (_) {
      // Only the classification is useful here. Every wipe is attempted on
      // every run, so a retry also catches credentials a loading/error state
      // could not advertise to the settings UI.
      return false;
    }
  }
}

final Provider<SignOutEverywhereService> signOutEverywhereServiceProvider =
    Provider<SignOutEverywhereService>(
      (Ref ref) => SignOutEverywhereService(ref),
    );
