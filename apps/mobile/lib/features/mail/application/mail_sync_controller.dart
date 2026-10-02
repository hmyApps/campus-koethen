// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/settings_controller.dart';
import '../domain/mail_folder.dart';
import '../domain/mail_cache_store.dart';
import '../domain/mail_message.dart';
import 'mail_account_controller.dart';
import 'mail_inbox_controller.dart';
import 'mail_providers.dart';

/// How often the inbox is refreshed while the app is in the foreground.
const Duration kMailSyncInterval = Duration(minutes: 10);
const int kMailBodyPrefetchLimit = MailCachePolicy.defaultPrefetchBodies;

/// Merges the freshly fetched [latest] headers into the [cached] ones.
///
/// Accumulates on purpose: a message that has scrolled out of the newest 50 on
/// the server stays cached, so the offline set grows past 50 over time. Newest
/// first; [latest] wins on conflicts (updated \Seen flag etc.).
List<MailMessageHeader> mergeInboxHeaders(
  List<MailMessageHeader> cached,
  List<MailMessageHeader> latest,
) {
  final Map<String, MailMessageHeader> byId = <String, MailMessageHeader>{};
  for (final MailMessageHeader h in cached) {
    byId[h.id] = h;
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

/// Runs the inbox sync. The *scheduling* (app start, every
/// [kMailSyncInterval] in the foreground, on sign-in) lives in the app shell;
/// this controller just performs one sync on request and reports progress. All
/// work is off the UI thread's critical path: the app stays usable throughout.
///
/// The sync fetches the newest 50 INBOX headers, accumulates them into the
/// cache, and prefetches the full body (and, when enabled, attachment bytes)
/// of every message not yet cached — so opening a mail is instant and offline.
class MailSyncController extends Notifier<MailSyncStatus> {
  bool _running = false;

  @override
  MailSyncStatus build() {
    ref.watch(mailSessionGenerationProvider);
    return const MailSyncStatus();
  }

  /// Runs one sync. Coalesces overlapping calls; never throws to the caller.
  Future<void> syncNow() async {
    if (_running) return;
    final MailAccountState? account = ref
        .read(mailAccountControllerProvider)
        .value;
    if (account == null || !account.isSignedIn) return;
    final MailAccountController accountController = ref.read(
      mailAccountControllerProvider.notifier,
    );
    final int generation = accountController.sessionGeneration;

    _running = true;
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
      final List<MailMessageHeader> latest = await gateway.fetchHeaders(
        credentials,
        mailboxPath: kInboxPath,
        limit: kInboxLimit,
      );
      if (!accountController.isSessionCurrent(generation)) return;
      final List<MailMessageHeader> merged = mergeInboxHeaders(
        await cache.readHeaders(),
        latest,
      );
      if (!accountController.isSessionCurrent(generation)) return;
      await cache.saveHeaders(merged);
      if (!accountController.isSessionCurrent(generation)) return;
      ref.read(mailCacheRevisionProvider.notifier).bump();

      // 2) Prefetch full bodies for messages not yet cached.
      final Set<String> cachedIds = await cache.cachedMessageIds();
      final List<String> missing = latest
          .map((MailMessageHeader h) => h.id)
          .where((String id) => !cachedIds.contains(id))
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
        state = MailSyncStatus(isSyncing: false, lastSyncedAt: DateTime.now());
      }
    } catch (error) {
      if (accountController.isSessionCurrent(generation)) {
        state = state.copyWith(isSyncing: false, error: error);
      }
    } finally {
      _running = false;
    }
  }
}

final NotifierProvider<MailSyncController, MailSyncStatus>
mailSyncControllerProvider =
    NotifierProvider<MailSyncController, MailSyncStatus>(
      MailSyncController.new,
    );
