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
  /// can then take an up-to-date connected-service snapshot and wipe it.
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

/// Connects one service at a time. A shared identity never becomes a shared
/// cookie, token or server-side session.
class UniversityServiceConnector {
  const UniversityServiceConnector(this._ref);

  final Ref _ref;

  /// Validates the supplied identity against [service] and only then retains
  /// it centrally. A rejected login is never written.
  ///
  /// [displayName] is a purely cosmetic, mail-specific hint; every other
  /// service ignores it.
  Future<void> connectAndRetain(
    DirectService service,
    UniversityIdentity identity, {
    String? displayName,
  }) => _ref.read(universityServiceOperationGateProvider).run<void>(() async {
    final UniversityIdentity value = identity.normalized;
    if (!value.isValid) {
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.invalidIdentity,
      );
    }
    await _ref
        .read(universityServiceAdapterProvider(service))
        .connect(value, displayName: displayName);
    await _ref
        .read(universityAccountControllerProvider.notifier)
        .retainVerified(value);
  });

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
