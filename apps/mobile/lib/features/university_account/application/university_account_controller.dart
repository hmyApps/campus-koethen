// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/secure_university_identity_store.dart';
import '../domain/university_identity.dart';
import '../domain/university_identity_store.dart';

/// Public identity state without the password.
class UniversityAccountState {
  const UniversityAccountState({this.identifier});

  /// The stored username or email address, whichever form was entered.
  final String? identifier;

  bool get hasIdentity => identifier != null;

  @override
  String toString() => 'UniversityAccountState(hasIdentity: $hasIdentity)';
}

final Provider<UniversityIdentityStore> universityIdentityStoreProvider =
    Provider<UniversityIdentityStore>(
      (Ref ref) => SecureUniversityIdentityStore(),
    );

/// Owns the central identity lifecycle while keeping its password out of state.
class UniversityAccountController
    extends AsyncNotifier<UniversityAccountState> {
  UniversityIdentityStore get _store =>
      ref.read(universityIdentityStoreProvider);

  @override
  Future<UniversityAccountState> build() async {
    final UniversityIdentity? identity = await _store.read();
    return _publicState(identity);
  }

  /// Retains an identity only after a service connector has validated it.
  /// Callers must never use this method as an unverified settings write.
  Future<void> retainVerified(UniversityIdentity identity) async {
    final UniversityIdentity value = identity.normalized;
    if (!value.isValid) {
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.invalidIdentity,
      );
    }
    await _store.write(value);
    state = AsyncData<UniversityAccountState>(_publicState(value));
  }

  /// Reads the secret just in time for an explicit service connection.
  Future<UniversityIdentity> requireIdentity() async {
    final UniversityIdentity? identity = await _store.read();
    if (identity == null) {
      throw const UniversityAccountFailure(
        UniversityAccountFailureKind.identityMissing,
      );
    }
    return identity;
  }

  Future<void> deleteIdentity() async {
    await _store.clear();
    state = const AsyncData<UniversityAccountState>(UniversityAccountState());
  }

  static UniversityAccountState _publicState(UniversityIdentity? identity) =>
      UniversityAccountState(identifier: identity?.identifier);
}

final AsyncNotifierProvider<UniversityAccountController, UniversityAccountState>
universityAccountControllerProvider =
    AsyncNotifierProvider<UniversityAccountController, UniversityAccountState>(
      UniversityAccountController.new,
      retry: (_, _) => null,
    );
