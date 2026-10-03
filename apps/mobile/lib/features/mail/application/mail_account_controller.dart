// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mail_credentials.dart';
import '../domain/mail_failure.dart';
import '../domain/mail_gateway.dart';
import 'mail_providers.dart';

/// Public account state. Deliberately carries the email address and the
/// cosmetic display name — never the password — so nothing downstream can leak
/// the secret.
class MailAccountState {
  const MailAccountState({this.emailAddress, this.displayName});

  final String? emailAddress;
  final String? displayName;

  bool get isSignedIn => emailAddress != null;

  @override
  String toString() => 'MailAccountState(signedIn: $isSignedIn)';
}

/// Owns sign-in, sign-out and the stored account.
///
/// Credentials live only in secure storage; this controller reads them there
/// when it needs to talk to the gateway and never keeps the password in a field
/// or in its public state.
class MailAccountController extends AsyncNotifier<MailAccountState> {
  MailGateway get _gateway => ref.read(mailGatewayProvider);
  int _sessionGeneration = 0;
  bool _removing = false;

  int get sessionGeneration => _sessionGeneration;

  bool isSessionCurrent(int generation) =>
      generation == _sessionGeneration &&
      !_removing &&
      (state.value?.isSignedIn ?? false);

  @override
  Future<MailAccountState> build() async {
    final MailCredentials? stored = await ref
        .read(mailLocalDataCoordinatorProvider)
        .readCredentials();
    return MailAccountState(
      emailAddress: stored?.emailAddress,
      displayName: stored?.displayName,
    );
  }

  /// Reads the stored credentials for a gateway call, or throws if signed out.
  Future<MailCredentials> requireCredentials() async {
    final MailCredentials? stored = await ref
        .read(mailLocalDataCoordinatorProvider)
        .readCredentials();
    if (stored == null) {
      throw const MailFailure(MailFailureKind.invalidCredentials);
    }
    return stored;
  }

  /// Verifies IMAP + SMTP, then — only on success — stores the credentials.
  ///
  /// [displayName] is optional and purely cosmetic (the friendly part of the
  /// `From` header); it plays no role in authentication.
  Future<void> signIn({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final String address = normalizeEmailAddress(email);
    if (!isValidEmailAddress(address)) {
      throw const MailFailure(MailFailureKind.invalidEmail);
    }
    final String? name = displayName?.trim();
    final MailCredentials credentials = MailCredentials(
      emailAddress: address,
      password: password,
      displayName: (name != null && name.isNotEmpty) ? name : null,
    );

    // Verify before persisting: a wrong password must never be written.
    try {
      await _gateway
          .verifyConnection(credentials)
          .timeout(ref.read(mailSignInTimeoutProvider));
    } on TimeoutException {
      throw const MailFailure(MailFailureKind.timeout);
    }
    final bool wasSignedIn = state.value?.isSignedIn ?? false;
    try {
      final coordinator = ref.read(mailLocalDataCoordinatorProvider);
      final MailCredentials? previous = await coordinator.readCredentials();
      if (previous?.emailAddress != address) {
        // Record the wipe and invalidate every in-memory holder before the new
        // account can become visible. This also clears artifacts left by an
        // interrupted/legacy account even when no credential is present.
        await coordinator.wipe(onIntentRecorded: _invalidateMailSession);
      } else {
        // A password refresh for the same mailbox may keep its encrypted
        // cache, but outstanding requests still belong to the old
        // authenticated session and must not write after the replacement.
        _invalidateMailSession();
      }
      await coordinator.writeCredentials(credentials);
    } catch (error, stackTrace) {
      if (wasSignedIn) {
        // Mutation has begun after successful remote verification. The old
        // public account must no longer look usable when its local wipe or the
        // replacement write could only be completed partially.
        state = AsyncError<MailAccountState>(error, stackTrace);
      }
      rethrow;
    }
    _removing = false;

    // The inbox watches this controller, so publishing the new account state is
    // enough to make it rebuild for the new mailbox — no manual invalidation,
    // which would be a circular dependency (the inbox depends on us).
    state = AsyncData(
      MailAccountState(
        emailAddress: address,
        displayName: credentials.displayName,
      ),
    );
  }

  /// Closes any connection state and removes both fields from secure storage.
  /// Also wipes the offline mail cache so nothing survives for the next account.
  Future<void> signOut() async {
    await ref
        .read(mailLocalDataCoordinatorProvider)
        .wipe(onIntentRecorded: _invalidateMailSession);
    state = const AsyncData(MailAccountState());
  }

  void _invalidateMailSession() {
    _removing = true;
    _sessionGeneration++;
    ref.read(mailSessionGenerationProvider.notifier).advance();
  }
}

final AsyncNotifierProvider<MailAccountController, MailAccountState>
mailAccountControllerProvider =
    AsyncNotifierProvider<MailAccountController, MailAccountState>(
      MailAccountController.new,
    );
