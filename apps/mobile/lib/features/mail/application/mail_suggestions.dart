// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mail_cache_store.dart';
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

/// Debounced local + authenticated Exchange address-book suggestions. EWS
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
      final directory = ref.read(mailDirectoryGatewayProvider);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (cancelled) return const <MailAddressEntry>[];

      final List<MailAddressEntry> local = await localFuture;
      if (cancelled) return const <MailAddressEntry>[];
      List<MailAddressEntry> exchange = const <MailAddressEntry>[];
      try {
        final credentials = await accountController.requireCredentials();
        if (cancelled) return const <MailAddressEntry>[];
        exchange = await directory.search(credentials, query);
      } catch (_) {
        // Search suggestions are optional assistance. The compose form keeps
        // working with local results and direct address input.
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
