// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mail_cache_store.dart';
import '../domain/mail_failure.dart';
import 'mail_account_controller.dart';
import 'mail_providers.dart';
import 'mail_sync_controller.dart';

/// Every correspondent seen in the cached mail history, for recipient
/// suggestions. Rebuilds as the cache grows.
final FutureProvider<List<MailAddressEntry>> mailKnownAddressesProvider =
    FutureProvider<List<MailAddressEntry>>((Ref ref) async {
      ref.watch(mailCacheRevisionProvider);
      return ref.read(mailCacheStoreProvider).knownAddresses();
    });

/// Set after Exchange rejected the stored credentials (HTTP 401/403) for the
/// first time in the current mail session.
///
/// Every directory lookup is a Basic-auth login against the central university
/// account. Once the password is known to be rejected, further lookups — one
/// per typed recipient — would only add failed logins and risk a lockout. A new
/// sign-in advances the session generation and lifts the lock.
class MailDirectoryAuthLock extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(mailSessionGenerationProvider);
    return false;
  }

  void lock() => state = true;
}

final NotifierProvider<MailDirectoryAuthLock, bool>
mailDirectoryAuthLockProvider = NotifierProvider<MailDirectoryAuthLock, bool>(
  MailDirectoryAuthLock.new,
);

/// How long the recipient field waits after the last keystroke before it asks
/// for suggestions.
const Duration kRecipientSuggestionDebounce = Duration(milliseconds: 250);

/// Local + authenticated Exchange address-book suggestions for one query.
///
/// Callers debounce input ([kRecipientSuggestionDebounce]) and must keep a
/// listener while awaiting the result: without one, this auto-dispose provider
/// is disposed at the end of the event loop and abandons the lookup. EWS
/// failures degrade to the encrypted local history so composing mail remains
/// usable offline.
final mailRecipientSuggestionsProvider = FutureProvider.autoDispose
    .family<List<MailAddressEntry>, String>((Ref ref, String rawQuery) async {
      final String query = rawQuery.trim();
      if (query.length < 2) return const <MailAddressEntry>[];
      bool cancelled = false;
      ref.onDispose(() => cancelled = true);
      final Future<List<MailAddressEntry>> localFuture = ref.read(
        mailKnownAddressesProvider.future,
      );
      final MailAccountController accountController = ref.read(
        mailAccountControllerProvider.notifier,
      );
      final MailDirectoryAuthLock authLock = ref.read(
        mailDirectoryAuthLockProvider.notifier,
      );
      final int generation = ref.read(mailSessionGenerationProvider);
      final directory = ref.read(mailDirectoryGatewayProvider);

      final List<MailAddressEntry> local = await localFuture;
      if (cancelled) return const <MailAddressEntry>[];
      List<MailAddressEntry> exchange = const <MailAddressEntry>[];
      if (!ref.read(mailDirectoryAuthLockProvider)) {
        try {
          final credentials = await accountController.requireCredentials();
          if (cancelled) return const <MailAddressEntry>[];
          exchange = await directory.search(credentials, query);
        } on MailFailure catch (failure) {
          if (failure.kind == MailFailureKind.invalidCredentials &&
              !cancelled &&
              ref.read(mailSessionGenerationProvider) == generation) {
            authLock.lock();
          }
          // Search suggestions are optional assistance. The compose form
          // keeps working with local results and direct address input.
        } catch (_) {
          // Same as above: never let an unexpected directory error reach the
          // form.
        }
      }
      return cancelled
          ? const <MailAddressEntry>[]
          : mergeRecipientSuggestions(local, exchange, query);
    });

List<MailAddressEntry> mergeRecipientSuggestions(
  Iterable<MailAddressEntry> local,
  Iterable<MailAddressEntry> exchange,
  String query, {
  int limit = 8,
}) {
  final Map<String, MailAddressEntry> distinct = <String, MailAddressEntry>{};
  for (final MailAddressEntry entry in <MailAddressEntry>[
    ...exchange,
    ...local,
  ]) {
    distinct.putIfAbsent(entry.email.toLowerCase(), () => entry);
  }
  return suggestRecipients(distinct.values.toList(), query, limit: limit);
}

/// Ranks [all] against a query: an address whose email or name contains the
/// query (case-insensitive), best matches first, capped for a compact list.
List<MailAddressEntry> suggestRecipients(
  List<MailAddressEntry> all,
  String query, {
  int limit = 6,
}) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return const <MailAddressEntry>[];

  final List<MailAddressEntry> matches = all.where((MailAddressEntry e) {
    final String email = e.email.toLowerCase();
    final String name = (e.name ?? '').toLowerCase();
    return email.contains(q) || name.contains(q);
  }).toList();

  matches.sort((MailAddressEntry a, MailAddressEntry b) {
    // Prefix matches on the email rank above substring matches.
    final bool aPrefix = a.email.toLowerCase().startsWith(q);
    final bool bPrefix = b.email.toLowerCase().startsWith(q);
    if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
    return a.email.toLowerCase().compareTo(b.email.toLowerCase());
  });
  return matches.take(limit).toList();
}
