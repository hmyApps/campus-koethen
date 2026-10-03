// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../grades/application/grade_account_controller.dart';
import '../../mail/application/mail_account_controller.dart';
import '../../moodle/application/moodle_account_controller.dart';
import '../../settings/domain/direct_service.dart';
import '../domain/university_identity.dart';
import 'university_account_controller.dart';

/// One protocol-specific session boundary behind the account widget.
abstract interface class UniversityServiceAdapter {
  /// [displayName] is a purely cosmetic, mail-specific hint (the friendly
  /// sender name). Every other adapter ignores it.
  Future<void> connect(UniversityIdentity identity, {String? displayName});
  Future<void> disconnect();
}

/// Prevents a late `+` result from recreating credentials after a reported
/// complete deletion.
class UniversityServiceOperationGate {
  int _activeOperations = 0;
  bool _deleting = false;
  Completer<void>? _idle;
  Completer<void>? _deletionFinished;

  Future<T> run<T>(Future<T> Function() operation) async {
    if (_deleting) {
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.operationBlocked,
      );
    }
    _activeOperations++;
    _idle ??= Completer<void>();
    try {
      return await operation();
    } finally {
      _activeOperations--;
      if (_activeOperations == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Blocks new connector work and waits for already-started work. The caller
  /// can then run every canonical service wipe without a late connection
  /// recreating credentials afterwards.
  Future<void> beginCompleteDeletion() async {
    while (_deleting) {
      await _deletionFinished?.future;
    }
    _deleting = true;
    _deletionFinished = Completer<void>();
    if (_activeOperations > 0) await _idle?.future;
  }

  void finishCompleteDeletion() {
    _deleting = false;
    _deletionFinished?.complete();
    _deletionFinished = null;
  }
}

final Provider<UniversityServiceOperationGate>
universityServiceOperationGateProvider =
    Provider<UniversityServiceOperationGate>(
      (Ref ref) => UniversityServiceOperationGate(),
    );

class _MailUniversityServiceAdapter implements UniversityServiceAdapter {
  const _MailUniversityServiceAdapter(this._ref);
  final Ref _ref;

  @override
  Future<void> connect(UniversityIdentity identity, {String? displayName}) =>
      _ref
          .read(mailAccountControllerProvider.notifier)
          .signIn(
            email: _universityMailAddress(identity.identifier),
            password: identity.password,
            displayName: displayName,
          );

  @override
  Future<void> disconnect() =>
      _ref.read(mailAccountControllerProvider.notifier).signOut();
}

/// The university accepts the same account as a bare username or as its full
/// mail address. Mail still needs a syntactically complete sender address for
/// IMAP/SMTP and the `From` header, so only this protocol adapter expands the
/// bare form. Already complete addresses are passed through unchanged.
String _universityMailAddress(String identifier) {
  final String value = identifier.trim();
  return value.contains('@') ? value : '$value@hs-anhalt.de';
}

class _MoodleUniversityServiceAdapter implements UniversityServiceAdapter {
  const _MoodleUniversityServiceAdapter(this._ref);
  final Ref _ref;

  @override
  Future<void> connect(UniversityIdentity identity, {String? displayName}) =>
      _ref
          .read(moodleAccountControllerProvider.notifier)
          .connect(username: identity.identifier, password: identity.password);

  @override
  Future<void> disconnect() =>
      _ref.read(moodleAccountControllerProvider.notifier).disconnect();
}

class _GradesUniversityServiceAdapter implements UniversityServiceAdapter {
  const _GradesUniversityServiceAdapter(this._ref);
  final Ref _ref;

  @override
  Future<void> connect(
    UniversityIdentity identity, {
    String? displayName,
  }) async {
    await _ref
        .read(gradeAccountControllerProvider.notifier)
        .signIn(username: identity.identifier, password: identity.password);
  }

  @override
  Future<void> disconnect() =>
      _ref.read(gradeAccountControllerProvider.notifier).deleteEverything();
}

final universityServiceAdapterProvider =
    Provider.family<UniversityServiceAdapter, DirectService>((
      Ref ref,
      service,
    ) {
      return switch (service) {
        DirectService.mail => _MailUniversityServiceAdapter(ref),
        DirectService.moodle => _MoodleUniversityServiceAdapter(ref),
        DirectService.grades => _GradesUniversityServiceAdapter(ref),
      };
    });

/// The non-secret service state that must survive a central identity update.
///
/// This is captured before the first mutation. It deliberately contains no
/// credential, token or personal content; the mail display name is the sole
/// cosmetic value needed to rebuild that service's local credentials.
class UniversityServiceConnectionSnapshot {
  const UniversityServiceConnectionSnapshot({
    this.connected = const <DirectService>{},
    this.mailDisplayName,
  });

  final Set<DirectService> connected;
  final String? mailDisplayName;

  String? displayNameFor(DirectService service) =>
      service == DirectService.mail ? mailDisplayName : null;
}

final Provider<UniversityServiceConnectionSnapshot>
universityServiceConnectionSnapshotProvider =
    Provider<UniversityServiceConnectionSnapshot>((Ref ref) {
      final MailAccountState? mail = ref
          .watch(mailAccountControllerProvider)
          .value;
      final moodle = ref.watch(moodleAccountControllerProvider).value;
      final GradeAccountState? grades = ref
          .watch(gradeAccountControllerProvider)
          .value;
      return UniversityServiceConnectionSnapshot(
        connected: <DirectService>{
          if (mail?.isSignedIn ?? false) DirectService.mail,
          if (moodle != null) DirectService.moodle,
          if (grades?.isSignedIn ?? false) DirectService.grades,
        },
        mailDisplayName: mail?.displayName,
      );
    });

/// Outcome of an explicit central-account update.
///
/// A failed reconnect is reported per service instead of turning an otherwise
/// successful account update into an ambiguous all-or-nothing error.
class UniversityServiceConnectionResult {
  const UniversityServiceConnectionResult({
    required this.identityChanged,
    this.reconnectedServices = const <DirectService>{},
    this.failedReconnections = const <DirectService>{},
  });

  final bool identityChanged;
  final Set<DirectService> reconnectedServices;
  final Set<DirectService> failedReconnections;
}

/// Connects one service at a time. A shared identity never becomes a shared
/// cookie, token or server-side session.
class UniversityServiceConnector {
  const UniversityServiceConnector(this._ref);

  final Ref _ref;

  /// Validates the supplied identity against [service]. When [retainIdentity]
  /// is true, it is retained centrally only after the service accepted it.
  /// A rejected login is never written.
  ///
  /// [displayName] is a purely cosmetic, mail-specific hint; every other
  /// service ignores it.
  Future<void> connectWithIdentity(
    DirectService service,
    UniversityIdentity identity, {
    String? displayName,
    bool retainIdentity = false,
  }) => _ref.read(universityServiceOperationGateProvider).run<void>(() async {
    final UniversityIdentity value = identity.normalized;
    if (!value.isValid) {
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.invalidIdentity,
      );
    }
    final UniversityServiceAdapter adapter = _ref.read(
      universityServiceAdapterProvider(service),
    );
    await adapter.connect(value, displayName: displayName);
    if (!retainIdentity) return;

    try {
      await _ref
          .read(universityAccountControllerProvider.notifier)
          .retainVerified(value);
    } catch (error, stackTrace) {
      // The service has already persisted its own credentials/session. If the
      // optional central write fails, keeping that half-connected state would
      // make the UI claim setup failed while personal data survived. Roll it
      // back through the same canonical wipe as an explicit minus action.
      try {
        await adapter.disconnect();
      } catch (_) {
        throw const UniversityAccountFailure(
          UniversityAccountFailureKind.connectionRollbackIncomplete,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  });

  /// Validates one selected service and retains the verified identity in the
  /// same gated operation.
  Future<void> connectAndRetain(
    DirectService service,
    UniversityIdentity identity, {
    String? displayName,
  }) => connectWithIdentity(
    service,
    identity,
    displayName: displayName,
    retainIdentity: true,
  );

  /// Replaces the centrally retained identity without ever presenting data
  /// from the previous account under the new one.
  ///
  /// The selected service validates first, so rejected credentials leave the
  /// old account untouched. A real identity change then wipes every other
  /// protocol boundary before the new identity becomes visible. Previously
  /// linked services are reconnected independently and failures are returned
  /// to the UI per service.
  Future<UniversityServiceConnectionResult> replaceIdentityAndReconnect(
    DirectService validationService,
    UniversityIdentity identity, {
    String? displayName,
  }) => _ref
      .read(universityServiceOperationGateProvider)
      .run<UniversityServiceConnectionResult>(() async {
        final UniversityIdentity replacement = identity.normalized;
        if (!replacement.isValid) {
          throw const UniversityAccountFailure(
            UniversityAccountFailureKind.invalidIdentity,
          );
        }

        final UniversityIdentity previous = await _ref
            .read(universityAccountControllerProvider.notifier)
            .requireIdentity();
        final UniversityServiceConnectionSnapshot snapshot = _ref.read(
          universityServiceConnectionSnapshotProvider,
        );
        final UniversityServiceAdapter validationAdapter = _ref.read(
          universityServiceAdapterProvider(validationService),
        );
        final String? validationDisplayName =
            displayName ?? snapshot.displayNameFor(validationService);

        // Re-entering the same secret is a service validation, not an account
        // switch. Do not disturb unrelated connections or their caches.
        if (replacement == previous.normalized) {
          await validationAdapter.connect(
            replacement,
            displayName: validationDisplayName,
          );
          return const UniversityServiceConnectionResult(
            identityChanged: false,
          );
        }

        // Existing service controllers validate remotely before replacing any
        // local credential. Thus a rejected replacement reaches no mutation.
        await validationAdapter.connect(
          replacement,
          displayName: validationDisplayName,
        );

        var cleanupFailed = false;
        for (final DirectService service in DirectService.values) {
          if (service == validationService) continue;
          try {
            await _ref
                .read(universityServiceAdapterProvider(service))
                .disconnect();
          } catch (_) {
            cleanupFailed = true;
          }
        }
        if (cleanupFailed) {
          final bool restored = await _restoreSnapshot(
            previous,
            snapshot,
            validationService: validationService,
          );
          throw UniversityAccountFailure(
            restored
                ? UniversityAccountFailureKind.accountChangeCleanupIncomplete
                : UniversityAccountFailureKind.accountChangeRollbackIncomplete,
          );
        }

        try {
          await _ref
              .read(universityAccountControllerProvider.notifier)
              .retainVerified(replacement);
        } catch (error, stackTrace) {
          final bool restored = await _restoreSnapshot(
            previous,
            snapshot,
            validationService: validationService,
            restoreCentralIdentity: true,
          );
          if (!restored) {
            throw const UniversityAccountFailure(
              UniversityAccountFailureKind.accountChangeRollbackIncomplete,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        }

        final Set<DirectService> reconnected = <DirectService>{};
        final Set<DirectService> failed = <DirectService>{};
        for (final DirectService service in snapshot.connected) {
          if (service == validationService) continue;
          try {
            await _ref
                .read(universityServiceAdapterProvider(service))
                .connect(
                  replacement,
                  displayName: snapshot.displayNameFor(service),
                );
            reconnected.add(service);
          } catch (_) {
            // Its canonical wipe already completed. A failed reconnect stays
            // disconnected and can safely be retried with the explicit `+`.
            failed.add(service);
          }
        }
        return UniversityServiceConnectionResult(
          identityChanged: true,
          reconnectedServices: reconnected,
          failedReconnections: failed,
        );
      });

  Future<bool> _restoreSnapshot(
    UniversityIdentity previous,
    UniversityServiceConnectionSnapshot snapshot, {
    required DirectService validationService,
    bool restoreCentralIdentity = false,
  }) async {
    var restored = true;
    if (restoreCentralIdentity) {
      try {
        // Secure storage deliberately deletes a partially written pair when a
        // write fails. Restore the old pair explicitly; retaining only the old
        // public state would leave the next app start without an identity.
        await _ref
            .read(universityAccountControllerProvider.notifier)
            .retainVerified(previous);
      } catch (_) {
        restored = false;
      }
    }
    // The validating adapter is the only boundary that may already hold the
    // replacement when a later mutation fails.
    try {
      await _ref
          .read(universityServiceAdapterProvider(validationService))
          .disconnect();
    } catch (_) {
      restored = false;
    }
    for (final DirectService service in snapshot.connected) {
      try {
        await _ref
            .read(universityServiceAdapterProvider(service))
            .connect(previous, displayName: snapshot.displayNameFor(service));
      } catch (_) {
        restored = false;
      }
    }
    return restored;
  }

  /// Explicit `+`: reads the secret only for this call and creates only this
  /// service's credentials/session.
  Future<void> connect(DirectService service, {String? displayName}) =>
      _ref.read(universityServiceOperationGateProvider).run<void>(() async {
        final UniversityIdentity identity = await _ref
            .read(universityAccountControllerProvider.notifier)
            .requireIdentity();
        await _ref
            .read(universityServiceAdapterProvider(service))
            .connect(identity, displayName: displayName);
      });

  /// Explicit `−`: uses the service's canonical verified wipe and deliberately
  /// leaves the central identity untouched.
  Future<void> disconnect(DirectService service) => _ref
      .read(universityServiceOperationGateProvider)
      .run<void>(
        () => _ref.read(universityServiceAdapterProvider(service)).disconnect(),
      );
}

final Provider<UniversityServiceConnector> universityServiceConnectorProvider =
    Provider<UniversityServiceConnector>(
      (Ref ref) => UniversityServiceConnector(ref),
    );
