// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'mail_message.dart';
import 'mail_search_match.dart';

class MailCachePolicy {
  static const int defaultPrefetchBodies = 20;

  /// Size of the newest-headers window every INBOX sync fetches.
  static const int defaultWindowHeaders = 50;

  const MailCachePolicy({
    this.maxHeaders = 500,
    this.maxBodies = 200,
    this.maxBodyBytes = 100 * 1024 * 1024,
    this.headerRetention = const Duration(days: 365),
    this.bodyRetention = const Duration(days: 180),
    this.prefetchBodies = defaultPrefetchBodies,
    this.windowHeaders = defaultWindowHeaders,
  });

  /// The [windowHeaders] headers with the highest IMAP UIDs — exactly the
  /// server window of the last sync — are exempt from [headerRetention] and
  /// [maxHeaders]: dropping one would hide a current mail and make the next
  /// sync report it as new again.
  final int windowHeaders;
  final int maxHeaders;
  final int maxBodies;
  final int maxBodyBytes;
  final Duration headerRetention;
  final Duration bodyRetention;
  final int prefetchBodies;

  /// Whether a body dated [date] survives the age-based pruning at [now].
  /// An undated body ages from the moment it is stored, so it always does.
  bool retainsBodyDated(DateTime? date, DateTime now) =>
      date == null ||
      !date.toUtc().isBefore(now.toUtc().subtract(bodyRetention));
}

class MailCacheStats {
  const MailCacheStats({
    required this.headerCount,
    required this.bodyCount,
    required this.byteCount,
  });

  final int headerCount;
  final int bodyCount;
  final int byteCount;
}

/// Offline store for the INBOX: headers, full message bodies and (optionally)
/// attachment bytes are kept on the device so messages open instantly and work
/// without a connection.
///
/// Like the content cache, implementations **must not** throw: a cache miss or
/// a storage error degrades to "fetch online", it never crashes the app.
///
/// The store accumulates: once a message is cached it stays cached even after
/// it drops out of the newest 50 on the server, so the offline set grows over
/// time. Only removing the account [clear]s it.
abstract interface class MailCacheStore {
  /// The cached header index, newest first.
  Future<List<MailMessageHeader>> readHeaders();

  /// Replaces the header index with [headers] (the caller merges first).
  Future<void> saveHeaders(List<MailMessageHeader> headers);

  /// The INBOX UIDVALIDITY the cached UIDs belong to, or null when none has
  /// been recorded yet. A server reporting a different value has renumbered
  /// the mailbox: every cached UID may then name another message.
  Future<int?> readUidValidity();

  /// Records the UIDVALIDITY the cached INBOX UIDs belong to. Survives
  /// [clearCachedBodies] together with the header list; [clear] removes it.
  Future<void> saveUidValidity(int uidValidity);

  /// Ids of messages whose full body is cached.
  Future<Set<String>> cachedMessageIds();

  /// A cached full message, or null if only its header (or nothing) is known.
  Future<MailMessageDetail?> readMessage(String id);

  /// Whether a body dated [date] would outlive the next age-based [prune].
  ///
  /// A background prefetch must skip bodies for which this is false: storing
  /// them only to delete them again would repeat the full download on every
  /// sync. Opening such a message still loads it on demand.
  bool retainsBody(DateTime? date);

  /// Stores a full message (and updates the known-address index from it).
  Future<void> saveMessage(MailMessageDetail message);

  /// Stores a batch of full messages, updating the known-address index **once**.
  ///
  /// The sync prefetches up to a full page of bodies at a time, and the address
  /// index is one document covering every message ever cached: rebuilding it per
  /// message re-reads, re-parses, re-serialises and re-encrypts the whole
  /// (growing) index once per message, which turns a page of mail into
  /// quadratic work. Callers with more than one message must use this.
  Future<void> saveMessages(List<MailMessageDetail> messages);

  /// Removes one message, its header and any addresses no longer referenced by
  /// another cached message.
  Future<void> removeMessage(String id);

  /// Headers of the cached messages matching [query], newest first.
  ///
  /// This is the offline half of mail search: it matches sender, recipients,
  /// subject and body against what is *actually* on the device — never against
  /// folders that were never cached, and never by asking the server. The query
  /// is normalised by the implementation ([normalizeMailSearchTerm]); a blank
  /// query matches nothing.
  ///
  /// A message whose body is cached but whose header has dropped out of the
  /// index still yields a header, reconstructed from the cached message.
  Future<List<MailMessageHeader>> searchHeaders(String query);

  /// Every address seen across cached messages (From/To/Cc), for suggestions.
  Future<List<MailAddressEntry>> knownAddresses();

  Future<MailCacheStats> stats();

  /// Removes offline bodies, attachment bytes and derived indexes while
  /// retaining the lightweight header list.
  Future<void> clearCachedBodies();

  Future<void> prune();

  /// Wipes everything. Called when the account is removed.
  Future<void> clear();
}

/// A known correspondent for recipient suggestions.
class MailAddressEntry {
  const MailAddressEntry({required this.email, this.name});

  final String email;
  final String? name;

  /// What an autocomplete shows: `Name <email>` when a name is known.
  String get display =>
      (name != null && name!.trim().isNotEmpty) ? '$name <$email>' : email;
}

/// Collects the distinct addresses that appear on a message (From, To, Cc).
Iterable<MailAddress> addressesOf(MailMessageDetail message) sync* {
  yield message.from;
  yield* message.to;
  yield* message.cc;
}
