// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/settings_controller.dart';
import '../domain/mail_cache_store.dart';
import '../domain/mail_credentials.dart';
import '../domain/mail_folder.dart';
import '../domain/mail_failure.dart';
import '../domain/mail_gateway.dart';
import '../domain/mail_message.dart';
import 'mail_account_controller.dart';
import 'mail_folders.dart';
import 'mail_providers.dart';
import 'mail_sync_controller.dart';

const int kInboxLimit = MailCachePolicy.defaultWindowHeaders;
const int kOlderMailPageSize = 100;

class MailPaginationStatus {
  const MailPaginationStatus({
    this.isLoading = false,
    this.hasMore = true,
    this.hasAttempted = false,
    this.error,
  });

  final bool isLoading;
  final bool hasMore;
  final bool hasAttempted;
  final Object? error;
}

class MailPaginationController extends Notifier<MailPaginationStatus> {
  @override
  MailPaginationStatus build() {
    ref.watch(mailSessionGenerationProvider);
    ref.watch(selectedMailboxProvider);
    return const MailPaginationStatus();
  }

  void start() => state = MailPaginationStatus(
    isLoading: true,
    hasMore: state.hasMore,
    hasAttempted: state.hasAttempted,
  );

  void succeed({required bool hasMore}) =>
      state = MailPaginationStatus(hasMore: hasMore, hasAttempted: true);

  void fail(Object error) => state = MailPaginationStatus(
    hasMore: state.hasMore,
    hasAttempted: state.hasAttempted,
    error: error,
  );

  void reset() => state = const MailPaginationStatus();
}

final NotifierProvider<MailPaginationController, MailPaginationStatus>
mailPaginationProvider =
    NotifierProvider<MailPaginationController, MailPaginationStatus>(
      MailPaginationController.new,
    );

/// INBOX headers loaded through "older mails" during this session.
///
/// Each page is also offered to the persistent cache, but the cache's
/// retention drops headers older than a year or beyond its cap. Kept here
/// in memory only, such a page stays visible and the UID cursor continues
/// below it instead of reloading the same page forever. Reset with the
/// session and whenever another mailbox is selected.
class MailOlderInboxHeaders extends Notifier<List<MailMessageHeader>> {
  @override
  List<MailMessageHeader> build() {
    ref.watch(mailSessionGenerationProvider);
    ref.watch(selectedMailboxProvider);
    return const <MailMessageHeader>[];
  }

  void add(List<MailMessageHeader> headers) {
    if (headers.isNotEmpty) state = mergeInboxHeaders(state, headers);
  }

  /// Applies the same authoritative-window rule as the cache merge, so a
  /// message deleted elsewhere cannot survive here after a sync removed it.
  void reconcile(
    List<MailMessageHeader> latest, {
    required int fetchedLimit,
    required int mailboxSize,
  }) {
    if (state.isEmpty) return;
    final Set<String> kept = mergeInboxHeaders(
      state,
      latest,
      fetchedLimit: fetchedLimit,
      mailboxSize: mailboxSize,
    ).map((MailMessageHeader header) => header.id).toSet();
    final List<MailMessageHeader> next = state
        .where((MailMessageHeader header) => kept.contains(header.id))
        .toList(growable: false);
    if (next.length != state.length) state = next;
  }

  void remove(String id) {
    if (state.any((MailMessageHeader header) => header.id == id)) {
      state = state
          .where((MailMessageHeader header) => header.id != id)
          .toList(growable: false);
    }
  }

  void markSeen(String id) {
    if (state.any((MailMessageHeader h) => h.id == id && !h.isSeen)) {
      state = <MailMessageHeader>[
        for (final MailMessageHeader h in state)
          h.id == id ? h.copyWith(isSeen: true) : h,
      ];
    }
  }

  void clear() => state = const <MailMessageHeader>[];
}

final NotifierProvider<MailOlderInboxHeaders, List<MailMessageHeader>>
mailOlderInboxHeadersProvider =
    NotifierProvider<MailOlderInboxHeaders, List<MailMessageHeader>>(
      MailOlderInboxHeaders.new,
    );

/// The cached INBOX plus the older pages loaded in this session; the cached
/// copy wins on conflicts because the sync keeps its flags current.
Future<List<MailMessageHeader>> _visibleInboxHeaders(Ref ref) async {
  final List<MailMessageHeader> older = ref.read(mailOlderInboxHeadersProvider);
  final List<MailMessageHeader> cached = await ref
      .read(mailCacheStoreProvider)
      .readHeaders();
  return older.isEmpty ? cached : mergeInboxHeaders(older, cached);
}

/// Provides the message list of the currently selected mailbox.
///
/// The INBOX is served from the offline cache, so it appears instantly and
/// works offline; a background sync (see [MailSyncController]) keeps it fresh
/// and the list rebuilds via [mailCacheRevisionProvider]. Other folders are
/// fetched online on demand — they are not cached.
class MailInboxController extends AsyncNotifier<List<MailMessageHeader>> {
  @override
  Future<List<MailMessageHeader>> build() async {
    final account = ref.watch(mailAccountControllerProvider).value;
    if (account == null || !account.isSignedIn) {
      return const <MailMessageHeader>[];
    }
    final MailFolder folder = ref.watch(selectedMailboxProvider);

    if (folder.isInbox) {
      // Rebuild whenever the cache changes; read from the cache (offline-first).
      ref.watch(mailCacheRevisionProvider);
      ref.watch(mailOlderInboxHeadersProvider);
      return _visibleInboxHeaders(ref);
    }

    // Other folders: online, uncached.
    final credentials = await ref
        .read(mailAccountControllerProvider.notifier)
        .requireCredentials();
    final MailHeaderPage page = await ref
        .read(mailGatewayProvider)
        .fetchHeaders(
          credentials,
          mailboxPath: folder.path,
          limit: kInboxLimit,
        );
    return page.headers;
  }

  /// Manual refresh. For the INBOX this triggers a background sync (which
  /// updates the cache and, in turn, this list); for other folders it re-fetches.
  Future<void> refresh() async {
    final MailFolder folder = ref.read(selectedMailboxProvider);
    if (folder.isInbox) {
      await ref
          .read(mailSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      return;
    }
    ref.read(mailPaginationProvider.notifier).reset();
    state = const AsyncLoading<List<MailMessageHeader>>();
    state = await AsyncValue.guard(() async {
      final credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      final MailHeaderPage page = await ref
          .read(mailGatewayProvider)
          .fetchHeaders(
            credentials,
            mailboxPath: folder.path,
            limit: kInboxLimit,
          );
      return page.headers;
    });
  }

  /// Loads the next 100 headers older than every currently visible message.
  /// The cursor is the smallest cached IMAP UID, not a numeric page offset, so
  /// concurrent mailbox changes cannot shift or duplicate the next page.
  Future<void> loadOlder() async {
    final MailPaginationStatus pagination = ref.read(mailPaginationProvider);
    if (pagination.isLoading || !pagination.hasMore) return;
    final MailFolder folder = ref.read(selectedMailboxProvider);
    final List<MailMessageHeader>? current = folder.isInbox
        ? await _visibleInboxHeaders(ref)
        : state.value;
    if (ref.read(selectedMailboxProvider).path != folder.path) return;
    if (current == null || current.isEmpty) return;

    int? oldestUid;
    for (final MailMessageHeader header in current) {
      final int? uid = int.tryParse(header.id);
      if (uid != null && (oldestUid == null || uid < oldestUid)) {
        oldestUid = uid;
      }
    }
    if (oldestUid == null) {
      ref
          .read(mailPaginationProvider.notifier)
          .fail(const MailFailure(MailFailureKind.protocol));
      return;
    }

    final MailPaginationController paginationController = ref.read(
      mailPaginationProvider.notifier,
    );
    paginationController.start();
    try {
      final MailCredentials credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      final MailAccountController accountController = ref.read(
        mailAccountControllerProvider.notifier,
      );
      final int generation = accountController.sessionGeneration;
      final MailHeaderPage page = await ref
          .read(mailGatewayProvider)
          .fetchHeaders(
            credentials,
            mailboxPath: folder.path,
            limit: kOlderMailPageSize,
            beforeId: oldestUid.toString(),
          );
      final List<MailMessageHeader> older = page.headers;
      if (!accountController.isSessionCurrent(generation)) return;
      if (ref.read(selectedMailboxProvider).path != folder.path) return;

      if (folder.isInbox) {
        final cache = ref.read(mailCacheStoreProvider);
        final int? knownUidValidity = await cache.readUidValidity();
        if (page.uidValidity != null &&
            knownUidValidity != null &&
            page.uidValidity != knownUidValidity) {
          // Renumbered INBOX: these UIDs do not continue the cached ones.
          // The sync discards the stale cache; the page is not merged.
          unawaited(ref.read(mailSyncControllerProvider.notifier).syncNow());
          throw const MailFailure(MailFailureKind.mailboxChanged);
        }
        final List<MailMessageHeader> merged = mergeInboxHeaders(
          await cache.readHeaders(),
          older,
        );
        if (!accountController.isSessionCurrent(generation)) return;
        if (ref.read(selectedMailboxProvider).path != folder.path) return;
        await cache.saveHeaders(merged);
        if (!accountController.isSessionCurrent(generation)) return;
        if (ref.read(selectedMailboxProvider).path != folder.path) return;
        // The cache may drop part of the page; the in-memory copy keeps it
        // visible and moves the cursor below it.
        ref.read(mailOlderInboxHeadersProvider.notifier).add(older);
        ref.read(mailCacheRevisionProvider.notifier).bump();
      } else {
        state = AsyncData<List<MailMessageHeader>>(
          mergeInboxHeaders(current, older),
        );
      }
      paginationController.succeed(hasMore: older.length == kOlderMailPageSize);
    } catch (error) {
      if (ref.read(selectedMailboxProvider).path == folder.path) {
        paginationController.fail(error);
      }
    }
  }

  /// Downloads the complete message again so attachment bytes that were left
  /// out of the offline prefetch become available after an explicit tap.
  ///
  /// For the INBOX the enriched detail replaces the metadata-only cache entry;
  /// other folders keep their existing online-only behaviour.
  Future<MailMessageDetail> downloadAttachments(MailMessageRef message) async {
    final MailCredentials credentials = await ref
        .read(mailAccountControllerProvider.notifier)
        .requireCredentials();
    final MailAccountController accountController = ref.read(
      mailAccountControllerProvider.notifier,
    );
    final int generation = accountController.sessionGeneration;
    final MailMessageDetail detail = await ref
        .read(mailGatewayProvider)
        .fetchMessage(
          credentials,
          mailboxPath: message.mailboxPath,
          id: message.id,
          includeAttachmentBytes: true,
        );
    if (!accountController.isSessionCurrent(generation)) {
      throw const MailFailure(MailFailureKind.sessionClosed);
    }
    if (message.mailboxPath == kInboxPath) {
      await ref.read(mailCacheStoreProvider).saveMessage(detail);
      if (!accountController.isSessionCurrent(generation)) {
        throw const MailFailure(MailFailureKind.sessionClosed);
      }
      ref.read(mailCacheRevisionProvider.notifier).bump();
    }
    return detail;
  }

  /// Deletes on the server first. Only a confirmed server success may remove
  /// the offline copy; otherwise the reader still sees the message and can
  /// retry without the UI pretending a destructive action succeeded.
  Future<void> deleteMessage(MailMessageRef message) async {
    final MailCredentials credentials = await ref
        .read(mailAccountControllerProvider.notifier)
        .requireCredentials();
    final MailAccountController accountController = ref.read(
      mailAccountControllerProvider.notifier,
    );
    final int generation = accountController.sessionGeneration;
    await ref
        .read(mailGatewayProvider)
        .deleteMessage(
          credentials,
          mailboxPath: message.mailboxPath,
          id: message.id,
          expectedUidValidity: await _cachedUidValidity(ref, message),
        );
    if (!accountController.isSessionCurrent(generation)) {
      throw const MailFailure(MailFailureKind.sessionClosed);
    }

    if (message.mailboxPath == kInboxPath) {
      await ref.read(mailCacheStoreProvider).removeMessage(message.id);
      if (!accountController.isSessionCurrent(generation)) {
        throw const MailFailure(MailFailureKind.sessionClosed);
      }
      ref.read(mailOlderInboxHeadersProvider.notifier).remove(message.id);
      ref.read(mailCacheRevisionProvider.notifier).bump();
    } else {
      state = AsyncData<List<MailMessageHeader>>(
        (state.value ?? const <MailMessageHeader>[])
            .where((MailMessageHeader header) => header.id != message.id)
            .toList(growable: false),
      );
    }
    ref.invalidate(mailMessageProvider(message));
  }
}

final AsyncNotifierProvider<MailInboxController, List<MailMessageHeader>>
mailInboxControllerProvider =
    AsyncNotifierProvider<MailInboxController, List<MailMessageHeader>>(
      MailInboxController.new,
      // No silent auto-retry: a failed fetch (timeout, TLS, auth) must surface
      // to the user as an error they can retry, not spin in exponential backoff.
      retry: (_, _) => null,
    );

/// Identifies one message: its mailbox path and its per-mailbox id (UID).
typedef MailMessageRef = ({String mailboxPath, String id});

/// One message detail. For the INBOX the cache is consulted first (instant,
/// offline); a cache miss falls back to the network and the result is cached.
/// Marks the message \Seen on the server after a successful load.
final mailMessageProvider =
    FutureProvider.family<MailMessageDetail, MailMessageRef>((
      Ref ref,
      MailMessageRef message,
    ) async {
      ref.watch(mailSessionGenerationProvider);
      final bool isInbox = message.mailboxPath == kInboxPath;
      final cache = ref.read(mailCacheStoreProvider);

      if (isInbox) {
        final MailMessageDetail? cached = await cache.readMessage(message.id);
        if (cached != null) {
          await _markSeenLocally(ref, message);
          // Best effort: mark seen on the server without blocking the read.
          unawaited(_markSeen(ref, message));
          return cached;
        }
      }

      final credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      final MailAccountController accountController = ref.read(
        mailAccountControllerProvider.notifier,
      );
      final int generation = accountController.sessionGeneration;
      final gateway = ref.read(mailGatewayProvider);
      final bool downloadAttachments = ref
          .read(settingsProvider)
          .mailDownloadAttachments;
      final detail = await gateway.fetchMessage(
        credentials,
        mailboxPath: message.mailboxPath,
        id: message.id,
        includeAttachmentBytes: downloadAttachments,
      );
      if (!accountController.isSessionCurrent(generation)) {
        throw const MailFailure(MailFailureKind.sessionClosed);
      }
      if (isInbox) {
        await cache.saveMessage(detail);
        if (!accountController.isSessionCurrent(generation)) {
          throw const MailFailure(MailFailureKind.sessionClosed);
        }
        ref.read(mailCacheRevisionProvider.notifier).bump();
        await _markSeenLocally(ref, message);
      }
      unawaited(_markSeen(ref, message));
      return detail;
    }, retry: (_, _) => null);

/// Flips the cached header's \Seen flag and rebuilds the inbox, so the list
/// reflects "read" immediately after opening — no sync required. A no-op when
/// the header isn't cached (nothing to show yet) or is already marked seen.
Future<void> _markSeenLocally(Ref ref, MailMessageRef message) async {
  ref.read(mailOlderInboxHeadersProvider.notifier).markSeen(message.id);
  final cache = ref.read(mailCacheStoreProvider);
  final List<MailMessageHeader> headers = await cache.readHeaders();
  final int index = headers.indexWhere(
    (MailMessageHeader h) => h.id == message.id,
  );
  if (index == -1 || headers[index].isSeen) return;
  final List<MailMessageHeader> updated = List<MailMessageHeader>.of(headers);
  updated[index] = updated[index].copyWith(isSeen: true);
  await cache.saveHeaders(updated);
  ref.read(mailCacheRevisionProvider.notifier).bump();
}

/// Best-effort server sync of the \Seen flag. Never throws: a network failure
/// here must not affect the (already successful) local open — a later header
/// sync reconciles with the confirmed server state.
Future<void> _markSeen(Ref ref, MailMessageRef message) async {
  try {
    final credentials = await ref
        .read(mailAccountControllerProvider.notifier)
        .requireCredentials();
    await ref
        .read(mailGatewayProvider)
        .markSeen(
          credentials,
          mailboxPath: message.mailboxPath,
          id: message.id,
          expectedUidValidity: await _cachedUidValidity(ref, message),
        );
  } catch (_) {}
}

/// The UIDVALIDITY an INBOX id was cached under, so a destructive server
/// action can refuse to run once the mailbox has been renumbered. Other
/// folders are read live, so their ids are never stale and need no guard.
Future<int?> _cachedUidValidity(Ref ref, MailMessageRef message) async =>
    message.mailboxPath == kInboxPath
    ? ref.read(mailCacheStoreProvider).readUidValidity()
    : null;
