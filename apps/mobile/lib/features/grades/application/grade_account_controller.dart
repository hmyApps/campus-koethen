// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/session_guard.dart';
import '../domain/clock.dart';
import '../domain/grade.dart';
import '../domain/grade_cache_store.dart';
import '../domain/grade_credential_store.dart';
import '../domain/grade_credentials.dart';
import '../domain/grade_failure.dart';
import '../domain/grade_portal.dart';
import '../domain/grade_portal_store.dart';
import '../domain/grades_gateway.dart';
import 'grades_providers.dart';

/// Public account state — deliberately carries ONLY the username and the
/// active portal, never the password, so nothing downstream can leak the
/// secret.
class GradeAccountState {
  const GradeAccountState({this.username, this.activePortal});

  final String? username;

  /// The portal this account was set up on. `null` while signed out.
  final GradePortal? activePortal;

  bool get isSignedIn => username != null;

  @override
  String toString() =>
      'GradeAccountState(signedIn: $isSignedIn, portal: ${activePortal?.name})';
}

/// The order setup tries the two portals in, and the hard cap on login
/// attempts per setup — see `docs/grades.md` "Portalwahl".
const List<GradePortal> kGradePortalTryOrder = <GradePortal>[
  GradePortal.hisInOne,
  GradePortal.hisQisLegacy,
];
const int kMaxSetupLoginAttempts = 2;

/// Owns setup, portal selection and removal of the exam-portal account.
///
/// Credentials live only in secure storage; the password is read from there
/// just before a portal call and is never held in a field or in the state.
class GradeAccountController extends AsyncNotifier<GradeAccountState> {
  GradeCredentialStore get _store => ref.read(gradeCredentialStoreProvider);
  GradePortalStore get _portalStore => ref.read(gradePortalStoreProvider);
  GradeCacheStore get _cache => ref.read(gradeCacheStoreProvider);
  Clock get _clock => ref.read(gradeClockProvider);
  SessionGuard<({String username, GradePortal portal})> get _sessions =>
      ref.read(gradeSessionGuardProvider);

  Future<void> _wipeLinkedPersonalData() async {
    Object? failure;
    for (final GradeLinkedPersonalDataWiper wipe in ref.read(
      gradeLinkedPersonalDataWipersProvider,
    )) {
      try {
        await wipe();
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) {
      throw const GradeFailure(GradeFailureKind.cacheUnavailable);
    }
  }

  GradesGateway _gatewayFor(GradePortal portal) =>
      portal == GradePortal.hisInOne
      ? ref.read(hisInOneGatewayProvider)
      : ref.read(legacyQisGatewayProvider);

  @override
  Future<GradeAccountState> build() async {
    final GradeCredentials? stored = await _store.read();
    if (stored == null) {
      await _sessions.invalidateAndWait();
      // Best-effort catch-up for a `deleteEverything()` that was interrupted
      // (app killed) after clearing grades' own store but before reaching
      // this step — never lets a stumbling wipe turn an ordinary signed-out
      // read into an error. Every screen that gates on THIS provider,
      // including the HISinOne student-service screen, would otherwise show
      // a failure for a problem that has nothing to do with it.
      try {
        await _wipeLinkedPersonalData();
      } catch (_) {}
      return const GradeAccountState();
    }
    // Accounts set up before the portal choice existed default to the legacy
    // portal — the only one that existed then.
    final GradePortal portal =
        await _portalStore.read() ?? GradePortal.hisQisLegacy;
    _sessions.activate((username: stored.username, portal: portal));
    return GradeAccountState(username: stored.username, activePortal: portal);
  }

  /// Reads the stored credentials for a portal call, or throws if signed out.
  Future<GradeCredentials> requireCredentials() async {
    final GradeCredentials? stored = await _store.read();
    if (stored == null) {
      throw const GradeFailure(GradeFailureKind.invalidCredentials);
    }
    return stored;
  }

  /// Sets up the account. Students do not know which portal their programme
  /// uses, so setup tries [kGradePortalTryOrder] in order and keeps the FIRST
  /// portal that both logs in AND returns a non-empty Notenspiegel. A portal
  /// that logs in but returns an empty report is remembered and the next
  /// portal is tried; if every portal is empty, the first one that logged in
  /// stays active (the existing "no grades yet" message covers that case).
  ///
  /// At most [kMaxSetupLoginAttempts] login attempts happen — this method
  /// NEVER retries automatically beyond that. A failure that is specific to
  /// ONE portal (`invalidCredentials`, `portalStructureChanged`,
  /// `portalUnavailable`, `sessionExpired`) lets the NEXT portal be tried; the
  /// failure is remembered and only rethrown if no portal works. A failure of
  /// the DEVICE side (`networkUnavailable`, `timeout`, `tlsOrHostRejected`,
  /// `secureStorageUnavailable`) aborts immediately — trying the second portal
  /// over the same broken connection can only fail the same way.
  ///
  /// The fall-through matters in practice: Hochschule Anhalt's HISinOne
  /// accepts the credentials of accounts whose results still live in HIS-QIS
  /// and answers with an empty Leistungen page. Aborting on the first portal
  /// left those accounts unable to see any grades at all.
  ///
  /// Verifies before persisting: wrong credentials are never written. Returns
  /// the fetched report. Throws [GradeFailure] on any problem.
  Future<GradeReport> signIn({
    required String username,
    required String password,
  }) async {
    final String user = normalizeUsername(username);
    if (!isValidUsername(user) || !isValidPassword(password)) {
      throw const GradeFailure(GradeFailureKind.invalidCredentials);
    }
    final GradeCredentials credentials = GradeCredentials(
      username: user,
      password: password,
    );

    GradePortal? emptyButLoggedInPortal;
    GradeReport? emptyButLoggedInReport;
    GradeFailure? lastPortalFailure;
    int attempts = 0;

    for (final GradePortal portal in kGradePortalTryOrder) {
      if (attempts >= kMaxSetupLoginAttempts) break;
      attempts++;
      try {
        final GradeReport report = await _gatewayFor(
          portal,
        ).fetchGrades(credentials);
        if (!report.isEmpty) {
          return await _persist(portal, credentials, report);
        }
        emptyButLoggedInPortal ??= portal;
        emptyButLoggedInReport ??= report;
      } on GradeFailure catch (e) {
        if (!_isPortalSpecific(e.kind)) {
          rethrow; // a device-side failure aborts setup immediately
        }
        lastPortalFailure = e;
        continue; // try the next portal, still bounded by the attempt cap
      }
    }

    if (emptyButLoggedInPortal != null) {
      return _persist(
        emptyButLoggedInPortal,
        credentials,
        emptyButLoggedInReport!,
      );
    }
    throw lastPortalFailure ??
        const GradeFailure(GradeFailureKind.invalidCredentials);
  }

  /// Whether a failure says something about ONE portal (so the other one is
  /// still worth a try) rather than about the device/connection.
  static bool _isPortalSpecific(GradeFailureKind kind) => switch (kind) {
    GradeFailureKind.invalidCredentials ||
    GradeFailureKind.portalStructureChanged ||
    GradeFailureKind.portalUnavailable ||
    GradeFailureKind.sessionExpired => true,
    GradeFailureKind.networkUnavailable ||
    GradeFailureKind.timeout ||
    GradeFailureKind.tlsOrHostRejected ||
    GradeFailureKind.secureStorageUnavailable ||
    GradeFailureKind.cacheUnavailable ||
    GradeFailureKind.unknown => false,
  };

  Future<GradeReport> _persist(
    GradePortal portal,
    GradeCredentials credentials,
    GradeReport report, {
    bool replaceAccount = true,
  }) async {
    final bool wasSignedIn = state.value?.isSignedIn ?? false;
    try {
      await _sessions.invalidateAndWait();
      if (replaceAccount) {
        // Clear grades' own report before publishing or persisting the new
        // account. Otherwise a failed write could leave account B paired with
        // account A's last successful report on disk.
        await _cache.clear();
        await _wipeLinkedPersonalData();
      }
      await _store.write(credentials);
      await _portalStore.write(portal);
      final DateTime now = _clock.now();
      await _cache.writeReport(report);
      await _cache.writeLastSuccessfulSync(now);
      await _cache.writeLastAttemptedSync(now);

      _sessions.activate((username: credentials.username, portal: portal));

      // The grades controller watches this state, so publishing it rebuilds the
      // overview onto the fresh cache — no manual invalidation needed.
      state = AsyncData(
        GradeAccountState(username: credentials.username, activePortal: portal),
      );
      return report;
    } catch (error, stackTrace) {
      if (wasSignedIn) {
        // Once local replacement begins, any failure can leave the former
        // credential/cache pair incomplete. Never present that old account as
        // a successful connection under the new central identity.
        state = AsyncError<GradeAccountState>(error, stackTrace);
      }
      rethrow;
    }
  }

  /// Replaces the stored password after a portal-side password change.
  ///
  /// The banner that reports `invalidCredentials` used to offer only "delete
  /// credentials and local grades", which reads as "lose your grades" — so
  /// the safe recovery from a routine password change looked like the
  /// destructive option. This is the non-destructive one: it verifies against
  /// the portal the account is already on, rewrites only the credentials, and
  /// leaves the cached report, its key and every timestamp untouched.
  ///
  /// The portal is NOT re-detected. A password change does not move an
  /// account between portals, and re-running detection here would spend a
  /// second login attempt on the wrong host.
  ///
  /// Throws [GradeFailure] and writes nothing when the portal rejects the new
  /// password.
  Future<GradeReport> reauthenticate({required String password}) async {
    final GradeAccountState current = state.value ?? const GradeAccountState();
    final String? username = current.username;
    final GradePortal? portal = current.activePortal;
    if (username == null || portal == null) {
      throw const GradeFailure(GradeFailureKind.invalidCredentials);
    }
    if (!isValidPassword(password)) {
      throw const GradeFailure(GradeFailureKind.invalidCredentials);
    }
    final GradeCredentials credentials = GradeCredentials(
      username: username,
      password: password,
    );
    // Verified before it is persisted, exactly as in setup: a password that
    // the portal rejects is never written to secure storage.
    final GradeReport report = await _gatewayFor(
      portal,
    ).fetchGrades(credentials);
    return _persist(portal, credentials, report, replaceAccount: false);
  }

  /// Switches to the other exam portal. Persists the new choice, discards the
  /// local cache (a report from the other portal must never be shown as if it
  /// were current) and leaves it to the caller to trigger a fresh sync (e.g.
  /// `gradesControllerProvider.notifier.refresh()`).
  Future<void> switchPortal(GradePortal target) async {
    final GradeAccountState current = state.value ?? const GradeAccountState();
    if (!current.isSignedIn) return;

    await _sessions.invalidateAndWait();

    // The cache is cleared FIRST and its failure is fatal to the switch. The
    // old order wrote the new portal, swallowed a failed clear, and — if the
    // follow-up sync then failed too, which offline it will — showed the
    // previous portal's grades under the new portal's name. That is exactly
    // the confusion `docs/grades.md` rules out.
    await _cache.clear();
    await _wipeLinkedPersonalData();
    await _portalStore.write(target);
    _sessions.activate((username: current.username!, portal: target));
    state = AsyncData(
      GradeAccountState(username: current.username, activePortal: target),
    );
  }

  /// "Delete credentials and local grades": wipes secure storage, the
  /// portal choice, the encrypted cache, its key and all sync timestamps, then
  /// resets the state.
  ///
  /// Throws a typed secure-storage or cache failure when anything is left
  /// behind. It used to swallow clears, so a failed wipe still reported
  /// "signed out" while encrypted grades or their key remained on the device.
  /// The state is only reset once every step has actually succeeded.
  Future<void> deleteEverything() async {
    // Stop accepting work first and wait for every already-started sync. The
    // verified wipe then necessarily happens after its final possible write.
    await _sessions.invalidateAndWait();

    // Every store is attempted even if an earlier one fails: a partial wipe
    // that removed more is strictly better than stopping at the first error.
    // What is not allowed is reporting success afterwards.
    GradeFailure? failure;
    try {
      await _store.clear();
    } catch (error) {
      failure ??= error is GradeFailure
          ? error
          : const GradeFailure(GradeFailureKind.secureStorageUnavailable);
    }
    try {
      await _portalStore.clear();
    } catch (error) {
      failure ??= error is GradeFailure
          ? error
          : const GradeFailure(GradeFailureKind.secureStorageUnavailable);
    }
    try {
      await _cache.clear();
    } catch (error) {
      failure ??= error is GradeFailure
          ? error
          : const GradeFailure(GradeFailureKind.cacheUnavailable);
    }
    try {
      await _wipeLinkedPersonalData();
    } catch (error) {
      failure ??= error is GradeFailure
          ? error
          : const GradeFailure(GradeFailureKind.cacheUnavailable);
    }
    if (failure != null) {
      throw failure;
    }
    state = const AsyncData(GradeAccountState());
  }
}

final AsyncNotifierProvider<GradeAccountController, GradeAccountState>
gradeAccountControllerProvider =
    AsyncNotifierProvider<GradeAccountController, GradeAccountState>(
      GradeAccountController.new,
      // No Riverpod auto-retry: a failed build() must surface immediately,
      // not after several silent, exponentially-delayed background retries —
      // the same convention every other controller in this app follows.
      retry: (_, _) => null,
    );
