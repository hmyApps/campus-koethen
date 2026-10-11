// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../domain/mail_cache_store.dart';
import '../domain/mail_folder.dart';
import '../domain/mail_message.dart';
import 'mail_account_controller.dart';
import 'mail_folders.dart';
import 'mail_inbox_controller.dart';
import 'mail_providers.dart';

/// How far the additional server-side search has got.
enum MailServerSearchStatus {
  /// Not asked for. The local results stand on their own.
  idle,

  running,

  /// Finished — [MailSearchState.server] holds the hits the cache did not have.
  done,

  /// Failed. The local results are still valid and stay on screen.
  failed,
}

/// What the search screen shows: the local hits, and — only once explicitly
/// asked for — the additional server hits.
///
/// The two halves are deliberately separate states, not one merged async
/// value: an IMAP failure must never take already-found local results off the
/// screen, and "nothing cached matches" must be distinguishable from "the
/// server has not been asked yet".
@immutable
class MailSearchState {
  const MailSearchState({
    this.query = '',
    this.mailboxPath = kInboxPath,
    this.hasSearched = false,
    this.localAvailable = true,
    this.isSearchingLocally = false,
    this.local = const <MailMessageHeader>[],
    this.server = const <MailMessageHeader>[],
    this.serverStatus = MailServerSearchStatus.idle,
    this.serverError,
  });

  /// The trimmed term behind the current results (empty before the first run).
  final String query;

  /// The mailbox the current results belong to. The server search re-uses it,
  /// so both halves always describe the same folder.
  final String mailboxPath;

  /// True once a non-blank query has been run — tells "nothing found" apart
  /// from "nothing searched yet".
  final bool hasSearched;

  /// Whether local results are possible at all: only the INBOX is cached, and
  /// for any other folder the screen says so instead of implying an empty
  /// cache is an empty mailbox.
  final bool localAvailable;

  final bool isSearchingLocally;

  /// Hits from the encrypted device cache — instant and available offline.
  final List<MailMessageHeader> local;

  /// Hits the server returned that are *not* already in [local], deduplicated
  /// on the stable per-mailbox message id.
  final List<MailMessageHeader> server;

  final MailServerSearchStatus serverStatus;

  /// The typed failure of the last server search, for the retry banner.
  final Object? serverError;

  /// Local hits first (they were there immediately), then the extra server
  /// hits — a stable order that never reshuffles when the server answers.
  List<MailMessageHeader> get results => <MailMessageHeader>[
    ...local,
    ...server,
  ];

  bool get hasResults => local.isNotEmpty || server.isNotEmpty;

  /// Whether asking the server is a meaningful next step right now.
  bool get canSearchServer =>
      query.isNotEmpty && serverStatus != MailServerSearchStatus.running;

  MailSearchState copyWith({
    String? query,
    String? mailboxPath,
    bool? hasSearched,
    bool? localAvailable,
    bool? isSearchingLocally,
    List<MailMessageHeader>? local,
    List<MailMessageHeader>? server,
    MailServerSearchStatus? serverStatus,
    Object? serverError,
    bool clearServerError = false,
  }) => MailSearchState(
    query: query ?? this.query,
    mailboxPath: mailboxPath ?? this.mailboxPath,
    hasSearched: hasSearched ?? this.hasSearched,
    localAvailable: localAvailable ?? this.localAvailable,
    isSearchingLocally: isSearchingLocally ?? this.isSearchingLocally,
    local: local ?? this.local,
    server: server ?? this.server,
    serverStatus: serverStatus ?? this.serverStatus,
    serverError: clearServerError ? null : (serverError ?? this.serverError),
  );
}

/// Drives mail search: the device cache first, the server on request.
///
/// [run] searches only what is already on the device, so a hit appears without
/// a network round trip and works offline. [searchServer] adds an IMAP SEARCH
/// over the same term and folder for everything not cached; its result is
/// merged in without duplicates and its failure never removes local hits.
class MailSearchController extends Notifier<MailSearchState> {
  /// Guards against a slow answer for a term the user has already replaced.
  int _run = 0;

  @override
  MailSearchState build() {
    // Removing the account (or switching to another one) advances the
    // generation: results, query and any server error of the previous account
    // are dropped with it.
    ref.watch(mailSessionGenerationProvider);
    // Results are ids of one folder, and the message screen opens them in the
    // currently selected one. A folder switch therefore drops them, and
    // [_stillShowing] keeps a search still in flight from writing its hits
    // into the new folder's state.
    ref.watch(selectedMailboxProvider);
    return const MailSearchState();
  }

  /// Searches the local cache for [rawQuery]. A blank query clears everything.
  Future<void> run(String rawQuery) async {
    final String q = rawQuery.trim();
    final int token = ++_run;
    if (q.isEmpty) {
      state = const MailSearchState();
      return;
    }

    final MailFolder folder = ref.read(selectedMailboxProvider);
    // Only the INBOX is cached; no other folder is silently presented as if it
    // were searched locally.
    final bool localAvailable = folder.isInbox;
    state = MailSearchState(
      query: q,
      mailboxPath: folder.path,
      hasSearched: true,
      localAvailable: localAvailable,
      isSearchingLocally: localAvailable,
    );
    if (!localAvailable) return;

    final MailCacheStore cache = ref.read(mailCacheStoreProvider);
    final List<MailMessageHeader> hits = await cache.searchHeaders(q);
    if (token != _run || !_stillShowing(folder.path)) return;
    state = state.copyWith(isSearchingLocally: false, local: hits);
  }

  /// Runs the additional IMAP search for the current term and folder.
  Future<void> searchServer() async {
    final MailSearchState current = state;
    if (current.query.isEmpty) return;
    if (current.serverStatus == MailServerSearchStatus.running) return;
    final int token = _run;

    state = current.copyWith(
      serverStatus: MailServerSearchStatus.running,
      clearServerError: true,
    );
    try {
      final credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      final List<MailMessageHeader> found = await ref
          .read(mailGatewayProvider)
          .searchMessages(
            credentials,
            mailboxPath: current.mailboxPath,
            query: current.query,
            limit: kInboxLimit,
          );
      if (token != _run || !_stillShowing(current.mailboxPath)) return;
      final Set<String> known = state.local
          .map((MailMessageHeader h) => h.id)
          .toSet();
      state = state.copyWith(
        server: found
            .where((MailMessageHeader h) => known.add(h.id))
            .toList(growable: false),
        serverStatus: MailServerSearchStatus.done,
        clearServerError: true,
      );
    } catch (error) {
      if (token != _run || !_stillShowing(current.mailboxPath)) return;
      // The local hits stay exactly as they are — offline or a broken server
      // must not empty a list the device could answer on its own.
      state = state.copyWith(
        serverStatus: MailServerSearchStatus.failed,
        serverError: error,
      );
    }
  }

  /// Whether an answer for [mailboxPath] may still be written: the provider
  /// is alive and that folder is still the selected one.
  bool _stillShowing(String mailboxPath) =>
      ref.mounted && ref.read(selectedMailboxProvider).path == mailboxPath;

  void clear() {
    _run++;
    state = const MailSearchState();
  }
}

final NotifierProvider<MailSearchController, MailSearchState>
mailSearchControllerProvider =
    NotifierProvider<MailSearchController, MailSearchState>(
      MailSearchController.new,
    );
