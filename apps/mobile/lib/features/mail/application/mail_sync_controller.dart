// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/settings_controller.dart';
import '../domain/mail_folder.dart';
import '../domain/mail_cache_store.dart';
import '../domain/mail_failure.dart';
import '../domain/mail_gateway.dart';
import '../domain/mail_message.dart';
import 'mail_account_controller.dart';
import 'mail_inbox_controller.dart';
import 'mail_providers.dart';

/// How often the inbox is refreshed while the app is in the foreground.
const Duration kMailSyncInterval = Duration(minutes: 10);
const int kMailBodyPrefetchLimit = MailCachePolicy.defaultPrefetchBodies;

/// Merges the freshly fetched [latest] headers into the [cached] ones.
///
/// Accumulates on purpose: a message that has scrolled out of the fetched
/// server window stays cached. When [fetchedLimit] proves a non-empty response
/// authoritative for a UID range, messages deleted or moved elsewhere are
/// removed inside that range. When [mailboxSize] (the server's EXISTS count)
/// shows that the window covered the whole mailbox, every cached message
/// missing from it is gone and removed. An empty response is always
/// non-destructive. Newest first; [latest] wins on conflicts (updated \Seen
/// flag etc.).
List<MailMessageHeader> mergeInboxHeaders(
  List<MailMessageHeader> cached,
  List<MailMessageHeader> latest, {
  int? fetchedLimit,
  int? mailboxSize,
}) {
  Set<String>? retainedCachedIds;
  final bool coversMailbox =
      fetchedLimit != null &&
      mailboxSize != null &&
      mailboxSize > 0 &&
      mailboxSize <= fetchedLimit;
  if (latest.isNotEmpty &&
      fetchedLimit != null &&
      fetchedLimit > 0 &&
      (coversMailbox || latest.length >= fetchedLimit)) {
    final Set<String> latestIds = latest
        .map((MailMessageHeader header) => header.id)
        .toSet();
    final List<int?> parsed = latest
        .map((MailMessageHeader header) => int.tryParse(header.id))
        .toList(growable: false);
    if (coversMailbox) {
      // Nothing older exists on the server, so nothing older may stay.
      retainedCachedIds = latestIds;
    } else if (parsed.every((int? uid) => uid != null && uid > 0)) {
      final int oldestFetchedUid = parsed.cast<int>().reduce(
        (int a, int b) => a < b ? a : b,
      );
      retainedCachedIds = <String>{
        ...latestIds,
        for (final MailMessageHeader header in cached)
          if ((int.tryParse(header.id) ?? oldestFetchedUid) < oldestFetchedUid)
            header.id,
      };
    }
  }
  final Map<String, MailMessageHeader> byId = <String, MailMessageHeader>{};
  for (final MailMessageHeader h in cached) {
    if (retainedCachedIds == null || retainedCachedIds.contains(h.id)) {
      byId[h.id] = h;
    }
  }
  for (final MailMessageHeader h in latest) {
    byId[h.id] = h;
  }
  final List<MailMessageHeader> all = byId.values.toList()
    ..sort((MailMessageHeader a, MailMessageHeader b) {
      final DateTime? da = a.date;
      final DateTime? db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
  return all;
}

/// Status of the background inbox sync.
class MailSyncStatus {
  const MailSyncStatus({this.isSyncing = false, this.lastSyncedAt, this.error});

  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final Object? error;

  MailSyncStatus copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    Object? error,
    bool clearError = false,
  }) => MailSyncStatus(
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    error: clearError ? null : (error ?? this.error),
  );
}

class MailNewMessageEvent {
  const MailNewMessageEvent({
    required this.serial,
    required this.sessionGeneration,
    required this.newestMessageId,
    required this.count,
  });

  final int serial;
  final int sessionGeneration;
  final String newestMessageId;
  final int count;
}

class MailNewMessageEvents extends Notifier<MailNewMessageEvent?> {
  int _serial = 0;

  @override
  MailNewMessageEvent? build() {
    ref.watch(mailSessionGenerationProvider);
    return null;
  }

  void publish(List<MailMessageHeader> messages) {
    if (messages.isEmpty) return;
    state = MailNewMessageEvent(
      serial: ++_serial,
      sessionGeneration: ref.read(mailSessionGenerationProvider),
      newestMessageId: messages.first.id,
      count: messages.length,
    );
  }
}

final NotifierProvider<MailNewMessageEvents, MailNewMessageEvent?>
mailNewMessageEventProvider =
    NotifierProvider<MailNewMessageEvents, MailNewMessageEvent?>(
      MailNewMessageEvents.new,
    );

/// A monotonically increasing counter bumped whenever the mail cache changes,
/// so cache-reading providers can rebuild without a direct dependency on the
/// writer (which would be circular).
class MailCacheRevision extends Notifier<int> {
  @override
  int build() {
    ref.watch(mailSessionGenerationProvider);
    return 0;
  }

  void bump() => state = state + 1;
}

final NotifierProvider<MailCacheRevision, int> mailCacheRevisionProvider =
    NotifierProvider<MailCacheRevision, int>(MailCacheRevision.new);

/// The server rejected the stored mail password in this mail session.
///
/// Shared by the periodic sync and the live connection so that neither keeps
/// logging in with a password the server already refused: every failed login
/// counts against the central university account and can lock it. A new
/// sign-in (a new session generation) or any later successful sync clears it.
class MailCredentialsRejection extends Notifier<MailFailure?> {
  @override
  MailFailure? build() {
    ref.watch(mailSessionGenerationProvider);
    return null;
  }

  void reject(MailFailure failure) => state = failure;

  void clear() {
    if (state != null) state = null;
  }
}

final NotifierProvider<MailCredentialsRejection, MailFailure?>
mailCredentialsRejectionProvider =
    NotifierProvider<MailCredentialsRejection, MailFailure?>(
      MailCredentialsRejection.new,
    );

/// Runs the inbox sync. The *scheduling* (app start, every
/// [kMailSyncInterval] in the foreground, on sign-in) lives in the app shell;
/// this controller just performs one sync on request and reports progress. All
/// work is off the UI thread's critical path: the app stays usable throughout.
///
/// The sync fetches the newest 50 INBOX headers, accumulates them into the
/// cache, and prefetches the full body (and, when enabled, attachment bytes)
/// of every message not yet cached — so opening a mail is instant and offline.
///
/// Once the server rejected the stored password ([mailCredentialsRejectionProvider]),
/// automatic syncs no longer log in; only a user-initiated refresh tries again.
class MailSyncController extends Notifier<MailSyncStatus> {
  Future<void>? _activeSync;
  bool _queued = false;
  bool _queuedByUser = false;

  @override
  MailSyncStatus build() {
    ref.watch(mailSessionGenerationProvider);
    return const MailSyncStatus();
  }

  /// Runs one sync. Coalesces overlapping calls; never throws to the caller.
  ///
  /// [userInitiated] marks a deliberate refresh by the reader. Only such a
  /// refresh logs in again after the server rejected the stored password.
  Future<void> syncNow({bool userInitiated = false}) async {
    _queued = true;
    _queuedByUser = _queuedByUser || userInitiated;
    final Future<void>? active = _activeSync;
    if (active != null) return active;
    final Future<void> run = _runQueue();
    _activeSync = run;
    return run;
  }

  Future<void> _runQueue() async {
    try {
      while (_queued) {
        _queued = false;
        final bool byUser = _queuedByUser;
        _queuedByUser = false;
        await _syncOnce(userInitiated: byUser);
      }
    } finally {
      _activeSync = null;
    }
  }

  Future<void> _syncOnce({required bool userInitiated}) async {
    final MailAccountState? account = ref
        .read(mailAccountControllerProvider)
        .value;
    if (account == null || !account.isSignedIn) return;
    final MailAccountController accountController = ref.read(
      mailAccountControllerProvider.notifier,
    );
    final int generation = accountController.sessionGeneration;
    final MailFailure? rejected = ref.read(mailCredentialsRejectionProvider);
    if (rejected != null && !userInitiated) {
      state = state.copyWith(isSyncing: false, error: rejected);
      return;
    }

    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      final gateway = ref.read(mailGatewayProvider);
      final cache = ref.read(mailCacheStoreProvider);
      final bool downloadAttachments = ref
          .read(settingsProvider)
          .mailDownloadAttachments;

      // 1) Newest 50 headers → merge into the accumulated cache.
      List<MailMessageHeader> cachedBefore = await cache.readHeaders();
      final int? knownUidValidity = await cache.readUidValidity();
      bool hadBaseline = cachedBefore.isNotEmpty || state.lastSyncedAt != null;
      final MailHeaderPage page = await gateway.fetchHeaders(
        credentials,
        mailboxPath: kInboxPath,
        limit: kInboxLimit,
      );
      final List<MailMessageHeader> latest = page.headers;
      if (!accountController.isSessionCurrent(generation)) return;
      final int? uidValidity = page.uidValidity;
      if (uidValidity != null &&
          knownUidValidity != null &&
          uidValidity != knownUidValidity) {
        // The server renumbered the INBOX: every cached UID may now name a
        // different message. Drop the whole cached INBOX and start a fresh
        // baseline — renumbered mail is not new mail.
        await cache.clearCachedBodies();
        await cache.saveHeaders(const <MailMessageHeader>[]);
        if (!accountController.isSessionCurrent(generation)) return;
        ref.read(mailOlderInboxHeadersProvider.notifier).clear();
        cachedBefore = const <MailMessageHeader>[];
        hadBaseline = false;
      }
      final Set<String> knownIds = cachedBefore
          .map((MailMessageHeader header) => header.id)
          .toSet();
      final List<MailMessageHeader> newMessages = latest
          .where((MailMessageHeader header) => !knownIds.contains(header.id))
          .toList(growable: false);
      final List<MailMessageHeader> merged = mergeInboxHeaders(
        cachedBefore,
        latest,
        fetchedLimit: kInboxLimit,
        mailboxSize: page.messagesExists,
      );
      final Set<String> retainedIds = merged
          .map((MailMessageHeader header) => header.id)
          .toSet();
      final List<String> removedIds = cachedBefore
          .map((MailMessageHeader header) => header.id)
          .where((String id) => !retainedIds.contains(id))
          .toList(growable: false);
      if (!accountController.isSessionCurrent(generation)) return;
      await cache.saveHeaders(merged);
      for (final String removedId in removedIds) {
        if (!accountController.isSessionCurrent(generation)) return;
        await cache.removeMessage(removedId);
      }
      if (!accountController.isSessionCurrent(generation)) return;
      if (uidValidity != null && uidValidity != knownUidValidity) {
        await cache.saveUidValidity(uidValidity);
        if (!accountController.isSessionCurrent(generation)) return;
      }
      ref
          .read(mailOlderInboxHeadersProvider.notifier)
          .reconcile(
            latest,
            fetchedLimit: kInboxLimit,
            mailboxSize: page.messagesExists,
          );
      ref.read(mailCacheRevisionProvider.notifier).bump();
      if (hadBaseline && newMessages.isNotEmpty) {
        ref.read(mailNewMessageEventProvider.notifier).publish(newMessages);
      }

      // 2) Prefetch full bodies for messages not yet cached. Bodies the age
      //    retention would prune straight away are skipped: downloading them
      //    would only repeat on every sync. Opening one still loads it.
      final Set<String> cachedIds = await cache.cachedMessageIds();
      final List<String> missing = latest
          .where((MailMessageHeader h) => !cachedIds.contains(h.id))
          .where((MailMessageHeader h) => cache.retainsBody(h.date))
          .map((MailMessageHeader h) => h.id)
          .take(kMailBodyPrefetchLimit)
          .toList();
      if (missing.isNotEmpty) {
        final List<MailMessageDetail> details = await gateway.fetchMessages(
          credentials,
          mailboxPath: kInboxPath,
          ids: missing,
          includeAttachmentBytes: downloadAttachments,
        );
        if (!accountController.isSessionCurrent(generation)) return;
        // One batched write rather than one per message: the address index is a
        // single document spanning every cached message, and rewriting it per
        // message made a full prefetch quadratic in the size of the cache.
        await cache.saveMessages(details);
        if (!accountController.isSessionCurrent(generation)) return;
        ref.read(mailCacheRevisionProvider.notifier).bump();
      }

      if (accountController.isSessionCurrent(generation)) {
        ref.read(mailCredentialsRejectionProvider.notifier).clear();
        state = MailSyncStatus(isSyncing: false, lastSyncedAt: DateTime.now());
      }
    } catch (error) {
      if (accountController.isSessionCurrent(generation)) {
        if (error is MailFailure &&
            error.kind == MailFailureKind.invalidCredentials) {
          ref.read(mailCredentialsRejectionProvider.notifier).reject(error);
        }
        state = state.copyWith(isSyncing: false, error: error);
      }
    }
  }
}

final NotifierProvider<MailSyncController, MailSyncStatus>
mailSyncControllerProvider =
    NotifierProvider<MailSyncController, MailSyncStatus>(
      MailSyncController.new,
    );

enum MailLiveConnection {
  stopped,
  connecting,
  idle,
  polling,
  retrying,

  /// The server rejected the stored password, or the secure connection could
  /// not be established. The live connection is NOT retried automatically:
  /// every reconnect is a fresh login against the central university account,
  /// and repeated failed logins can lock it. [MailLiveSyncStatus.error] carries
  /// the typed reason.
  authRequired,
}

/// First automatic reconnect delay after the live connection dropped.
const Duration kMailLiveRetryInitialDelay = Duration(seconds: 15);

/// Upper bound of the exponential reconnect backoff.
const Duration kMailLiveRetryMaxDelay = Duration(minutes: 30);

/// A live connection that stayed up this long counts as healthy again: the
/// next drop starts the backoff over at [kMailLiveRetryInitialDelay]. A
/// connection that drops right after its login keeps escalating instead, so a
/// server that accepts and immediately closes cannot cause a login loop.
const Duration kMailLiveStableAfter = Duration(minutes: 2);

/// The delay before the next automatic reconnect after [failedAttempts]
/// consecutive failures: 15 s, 30 s, 1 min, … capped at 30 min.
Duration mailLiveRetryDelay(int failedAttempts) {
  final int doublings = failedAttempts.clamp(0, 16);
  final Duration delay = kMailLiveRetryInitialDelay * (1 << doublings);
  return delay > kMailLiveRetryMaxDelay ? kMailLiveRetryMaxDelay : delay;
}

class MailLiveSyncStatus {
  const MailLiveSyncStatus({
    this.connection = MailLiveConnection.stopped,
    this.error,
  });

  final MailLiveConnection connection;
  final Object? error;
}

/// Owns the foreground-only IMAP IDLE connection. Mobile operating systems do
/// not guarantee sockets while the process is suspended; the normal resume
/// sync remains the correctness fallback.
///
/// Reconnects back off exponentially ([mailLiveRetryDelay]). A rejected
/// password stops the live connection for the rest of the mail session — a
/// later [start] (for example on resume) does not try it again; only a new
/// sign-in, which advances the session generation, does.
class MailLiveSyncController extends Notifier<MailLiveSyncStatus> {
  StreamSubscription<MailLiveSignal>? _subscription;
  Timer? _retry;
  Timer? _stable;
  int _generation = 0;
  int _failedAttempts = 0;

  /// The foreground owner asked for a live connection and has not stopped it.
  bool _wanted = false;

  /// The session was replaced while a live connection was wanted. The new
  /// account is published only after its credentials are stored, so the
  /// reconnect waits for that instead of racing the replacement.
  bool _reconnectForNewSession = false;

  @override
  MailLiveSyncStatus build() {
    ref.listen<int>(mailSessionGenerationProvider, (_, _) {
      // A new session brings new credentials: forget the backoff of the
      // replaced one (the shared rejection resets with the generation).
      _failedAttempts = 0;
      _reconnectForNewSession = _wanted;
      unawaited(_disconnect());
      state = const MailLiveSyncStatus();
    });
    ref.listen<AsyncValue<MailAccountState>>(mailAccountControllerProvider, (
      _,
      AsyncValue<MailAccountState> next,
    ) {
      if (!_reconnectForNewSession || next is! AsyncData<MailAccountState>) {
        return;
      }
      // Re-signing in while already signed in never flips the account from
      // signed out to signed in, so the app shell's start trigger stays
      // silent; reconnect here instead of waiting for the next resume.
      _reconnectForNewSession = false;
      if (_wanted && next.value.isSignedIn) unawaited(start());
    });
    ref.onDispose(() {
      _generation++;
      _retry?.cancel();
      _stable?.cancel();
      unawaited(_subscription?.cancel());
    });
    return const MailLiveSyncStatus();
  }

  Future<void> start() async {
    _wanted = true;
    if (_subscription != null) return;
    final MailFailure? rejected = ref.read(mailCredentialsRejectionProvider);
    if (rejected != null) {
      state = MailLiveSyncStatus(
        connection: MailLiveConnection.authRequired,
        error: rejected,
      );
      return;
    }
    final MailAccountState? account = ref
        .read(mailAccountControllerProvider)
        .value;
    if (account == null || !account.isSignedIn) return;
    final int generation = ++_generation;
    _retry?.cancel();
    state = const MailLiveSyncStatus(connection: MailLiveConnection.connecting);
    try {
      final credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      if (generation != _generation) return;
      _subscription = ref
          .read(mailGatewayProvider)
          .watchInbox(credentials)
          .listen(
            (MailLiveSignal signal) {
              if (generation != _generation) return;
              switch (signal) {
                case MailLiveSignal.connected:
                  _markConnected();
                  state = const MailLiveSyncStatus(
                    connection: MailLiveConnection.idle,
                  );
                  return;
                case MailLiveSignal.pollingFallback:
                  _markConnected();
                  state = const MailLiveSyncStatus(
                    connection: MailLiveConnection.polling,
                  );
                  return;
                case MailLiveSignal.changed:
                  unawaited(
                    ref.read(mailSyncControllerProvider.notifier).syncNow(),
                  );
                  return;
              }
            },
            onError: (Object error, StackTrace _) {
              if (generation == _generation) _connectionLost(error);
            },
            onDone: () {
              if (generation == _generation) _connectionLost(null);
            },
          );
    } catch (error) {
      if (generation == _generation) _connectionLost(error);
    }
  }

  void _markConnected() {
    _stable?.cancel();
    _stable = Timer(kMailLiveStableAfter, () => _failedAttempts = 0);
  }

  void _connectionLost(Object? error) {
    // Invalidate every further callback of the lost connection (a failing
    // watcher reports an error AND closes its stream).
    _generation++;
    _stable?.cancel();
    _stable = null;
    _retry?.cancel();
    _retry = null;
    final StreamSubscription<MailLiveSignal>? active = _subscription;
    _subscription = null;
    unawaited(active?.cancel());

    if (error is MailFailure &&
        (error.kind == MailFailureKind.invalidCredentials ||
            error.kind == MailFailureKind.tls)) {
      // No automatic retry. A rejected password stays rejected for this
      // session; a TLS failure sent no credentials, so an explicit later
      // start (resume) may try again — but never on a timer.
      if (error.kind == MailFailureKind.invalidCredentials) {
        ref.read(mailCredentialsRejectionProvider.notifier).reject(error);
      }
      state = MailLiveSyncStatus(
        connection: MailLiveConnection.authRequired,
        error: error,
      );
      return;
    }

    final Duration delay = mailLiveRetryDelay(_failedAttempts);
    _failedAttempts++;
    state = MailLiveSyncStatus(
      connection: MailLiveConnection.retrying,
      error: error,
    );
    _retry = Timer(delay, () {
      if (_wanted) unawaited(start());
    });
  }

  Future<void> _disconnect() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _stable?.cancel();
    _stable = null;
    final StreamSubscription<MailLiveSignal>? active = _subscription;
    _subscription = null;
    return active?.cancel() ?? Future<void>.value();
  }

  Future<void> stop() async {
    _wanted = false;
    _reconnectForNewSession = false;
    final Future<void> closed = _disconnect();
    state = const MailLiveSyncStatus();
    await closed;
  }
}

final NotifierProvider<MailLiveSyncController, MailLiveSyncStatus>
mailLiveSyncControllerProvider =
    NotifierProvider<MailLiveSyncController, MailLiveSyncStatus>(
      MailLiveSyncController.new,
    );
