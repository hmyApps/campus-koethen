// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../core/cache/encrypted_box.dart';
import '../domain/mail_cache_store.dart';
import '../domain/mail_message.dart';
import '../domain/mail_search_match.dart';
import 'mail_cache_codec.dart';

void _indexAddress(Map<String, MailAddressEntry> index, MailAddress address) {
  final String email = address.email.trim();
  if (email.isEmpty) return;
  final String key = email.toLowerCase();
  final MailAddressEntry? existing = index[key];
  final bool hasName = address.name != null && address.name!.trim().isNotEmpty;
  if (existing == null || (existing.name == null && hasName)) {
    index[key] = MailAddressEntry(
      email: email,
      name: hasName ? address.name : null,
    );
  }
}

/// Orders search hits like every other message list in this feature: newest
/// first, undated messages last, ties broken by id so the order is stable.
List<MailMessageHeader> sortMailSearchHits(List<MailMessageHeader> hits) {
  final List<MailMessageHeader> sorted = List<MailMessageHeader>.of(hits)
    ..sort((MailMessageHeader a, MailMessageHeader b) {
      final DateTime? da = a.date;
      final DateTime? db = b.date;
      if (da != null && db != null && da != db) return db.compareTo(da);
      if (da == null && db != null) return 1;
      if (da != null && db == null) return -1;
      return a.id.compareTo(b.id);
    });
  return sorted;
}

class MemoryMailCache implements MailCacheStore {
  MemoryMailCache({
    this.policy = const MailCachePolicy(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final MailCachePolicy policy;
  final DateTime Function() _now;
  List<MailMessageHeader> _headers = <MailMessageHeader>[];
  final Map<String, MailMessageDetail> _messages =
      <String, MailMessageDetail>{};
  final Map<String, MailAddressEntry> _addresses = <String, MailAddressEntry>{};
  final Map<String, DateTime> _storedAt = <String, DateTime>{};

  @override
  Future<List<MailMessageHeader>> readHeaders() async =>
      List<MailMessageHeader>.of(_headers);

  @override
  Future<void> saveHeaders(List<MailMessageHeader> headers) async {
    _headers = _retainedHeaders(headers, policy, _now());
  }

  @override
  Future<Set<String>> cachedMessageIds() async => _messages.keys.toSet();

  @override
  Future<MailMessageDetail?> readMessage(String id) async {
    final MailMessageDetail? message = _messages.remove(id);
    if (message != null) _messages[id] = message;
    return message;
  }

  @override
  Future<void> saveMessage(MailMessageDetail message) async {
    _messages[message.id] = message;
    _storedAt[message.id] = _now().toUtc();
    for (final MailAddress a in addressesOf(message)) {
      _indexAddress(_addresses, a);
    }
    await prune();
  }

  @override
  Future<void> saveMessages(List<MailMessageDetail> messages) async {
    for (final MailMessageDetail message in messages) {
      _messages[message.id] = message;
      _storedAt[message.id] = _now().toUtc();
      for (final MailAddress a in addressesOf(message)) {
        _indexAddress(_addresses, a);
      }
    }
    await prune();
  }

  @override
  Future<void> removeMessage(String id) async {
    _headers = _headers
        .where((MailMessageHeader header) => header.id != id)
        .toList(growable: false);
    _messages.remove(id);
    _addresses.clear();
    for (final MailMessageDetail message in _messages.values) {
      for (final MailAddress address in addressesOf(message)) {
        _indexAddress(_addresses, address);
      }
    }
  }

  @override
  Future<List<MailMessageHeader>> searchHeaders(String query) async {
    final String term = normalizeMailSearchTerm(query);
    if (term.isEmpty) return <MailMessageHeader>[];

    final Map<String, MailMessageHeader> byId = <String, MailMessageHeader>{
      for (final MailMessageHeader h in _headers) h.id: h,
    };
    final Map<String, MailMessageHeader> hits = <String, MailMessageHeader>{};
    for (final MailMessageHeader h in _headers) {
      if (mailTextMatches(mailHeaderSearchFields(h), term)) hits[h.id] = h;
    }
    for (final MailMessageDetail d in _messages.values) {
      if (hits.containsKey(d.id)) continue;
      if (!mailTextMatches(mailDetailSearchFields(d), term)) continue;
      hits[d.id] = byId[d.id] ?? _headerOf(d);
    }
    return sortMailSearchHits(hits.values.toList());
  }

  static MailMessageHeader _headerOf(MailMessageDetail d) => MailMessageHeader(
    id: d.id,
    subject: d.subject,
    from: d.from,
    date: d.date,
    isSeen: true,
    hasAttachments: d.hasAttachments,
  );

  @override
  Future<List<MailAddressEntry>> knownAddresses() async =>
      List<MailAddressEntry>.of(_addresses.values);

  @override
  Future<MailCacheStats> stats() async {
    final int bytes = _messages.values.fold<int>(
      0,
      (int total, MailMessageDetail message) =>
          total +
          utf8.encode(jsonEncode(MailCacheCodec.detail(message))).length,
    );
    return MailCacheStats(
      headerCount: _headers.length,
      bodyCount: _messages.length,
      byteCount: bytes,
    );
  }

  @override
  Future<void> clearCachedBodies() async {
    _messages.clear();
    _storedAt.clear();
    _addresses.clear();
  }

  @override
  Future<void> prune() async {
    if (_messages.isEmpty) return;
    final DateTime cutoff = _now().toUtc().subtract(policy.bodyRetention);
    final List<String> ids = _messages.keys.toList(growable: true);
    final String newestId = ids.last;
    for (final String id in ids.toList()) {
      final MailMessageDetail? message = _messages[id];
      final DateTime effective =
          message?.date?.toUtc() ?? _storedAt[id] ?? _now().toUtc();
      if (id != newestId && effective.isBefore(cutoff)) {
        _messages.remove(id);
        _storedAt.remove(id);
        ids.remove(id);
      }
    }
    int bytes = (await stats()).byteCount;
    while (ids.isNotEmpty &&
        (ids.length > policy.maxBodies || bytes > policy.maxBodyBytes)) {
      final String id = ids.removeAt(0);
      final MailMessageDetail? removed = _messages.remove(id);
      _storedAt.remove(id);
      if (removed != null) {
        bytes -= utf8.encode(jsonEncode(MailCacheCodec.detail(removed))).length;
      }
    }
  }

  @override
  Future<void> clear() async {
    _headers = <MailMessageHeader>[];
    _messages.clear();
    _addresses.clear();
    _storedAt.clear();
  }
}

List<MailMessageHeader> _retainedHeaders(
  List<MailMessageHeader> headers,
  MailCachePolicy policy,
  DateTime now,
) {
  if (headers.isEmpty) return <MailMessageHeader>[];
  final DateTime cutoff = now.toUtc().subtract(policy.headerRetention);
  final List<MailMessageHeader> retained = <MailMessageHeader>[
    headers.first,
    ...headers
        .skip(1)
        .where(
          (MailMessageHeader header) =>
              header.date == null || !header.date!.toUtc().isBefore(cutoff),
        ),
  ];
  return retained.take(policy.maxHeaders).toList(growable: false);
}

/// Mail cache serialization on top of the app's only at-rest crypto primitive.
class EncryptedMailCache implements MailCacheStore {
  EncryptedMailCache(
    this._box, {
    this.policy = const MailCachePolicy(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const String _headersKey = 'headers';
  static const String _addressesKey = 'addresses';
  static const String _metadataKey = 'metadata.v1';
  static const String _searchKey = 'search.v1';
  static const String _messagePrefix = 'msg.';

  final EncryptedBox _box;
  final MailCachePolicy policy;
  final DateTime Function() _now;

  @override
  Future<List<MailMessageHeader>> readHeaders() async {
    final Object? decoded = _decode(await _box.read(_headersKey));
    if (decoded is! List) return <MailMessageHeader>[];
    try {
      return decoded
          .whereType<Map>()
          .map(
            (Map<dynamic, dynamic> value) =>
                MailCacheCodec.headerFrom(Map<String, dynamic>.from(value)),
          )
          .toList();
    } catch (_) {
      return <MailMessageHeader>[];
    }
  }

  @override
  Future<void> saveHeaders(List<MailMessageHeader> headers) => _box.write(
    _headersKey,
    jsonEncode(
      _retainedHeaders(
        headers,
        policy,
        _now(),
      ).map(MailCacheCodec.header).toList(),
    ),
  );

  @override
  Future<Set<String>> cachedMessageIds() async => (await _box.keys())
      .where((String key) => key.startsWith(_messagePrefix))
      .map((String key) => key.substring(_messagePrefix.length))
      .toSet();

  @override
  Future<MailMessageDetail?> readMessage(String id) async {
    final Object? decoded = await _decodedMessage(id);
    if (decoded is! Map) return null;
    try {
      final MailMessageDetail detail = MailCacheCodec.detailFrom(
        Map<String, dynamic>.from(decoded),
      );
      final _MailCacheIndexes indexes = await _loadIndexes();
      final Map<String, dynamic>? metadata = indexes.metadata[id];
      if (metadata != null) {
        metadata['accessedAt'] = _now().toUtc().toIso8601String();
        await _box.write(_metadataKey, jsonEncode(indexes.metadata));
      }
      return detail;
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _decodedMessage(String id) async =>
      _decode(await _box.read('$_messagePrefix$id'));

  @override
  Future<void> saveMessage(MailMessageDetail message) =>
      saveMessages(<MailMessageDetail>[message]);

  @override
  Future<void> saveMessages(List<MailMessageDetail> messages) async {
    if (messages.isEmpty) return;

    final _MailCacheIndexes indexes = await _loadIndexes();
    final DateTime storedAt = _now().toUtc();
    final Map<String, String> encoded = <String, String>{};
    for (final MailMessageDetail message in messages) {
      final String raw = jsonEncode(MailCacheCodec.detail(message));
      encoded['$_messagePrefix${message.id}'] = raw;
      indexes.metadata[message.id] = <String, dynamic>{
        'bytes': utf8.encode(raw).length,
        'storedAt': storedAt.toIso8601String(),
        'accessedAt': storedAt.toIso8601String(),
        'date': message.date?.toUtc().toIso8601String(),
      };
      indexes.search[message.id] = MailCacheCodec.searchDocument(message);
    }

    // A sync prefetches up to a page of bodies. Persist the already-encoded
    // entries with one encrypted Hive batch instead of one disk operation per
    // message. Hive still encrypts each value with the same box cipher.
    await _box.writeAll(encoded);

    // Read, merge and rewrite the address index exactly once for the whole
    // batch. Per message it was one decrypt + parse + serialise + encrypt of
    // the entire index each time, so a page of 50 prefetched bodies paid for
    // the index 50 times over — and more the larger the index had grown.
    final Map<String, MailAddressEntry> index = <String, MailAddressEntry>{
      for (final MailAddressEntry entry in await knownAddresses())
        entry.email.toLowerCase(): entry,
    };
    for (final MailMessageDetail message in messages) {
      for (final MailAddress address in addressesOf(message)) {
        _indexAddress(index, address);
      }
    }
    await _box.write(
      _addressesKey,
      jsonEncode(
        index.values
            .map(
              (MailAddressEntry entry) => <String, dynamic>{
                'email': entry.email,
                if (entry.name != null) 'name': entry.name,
              },
            )
            .toList(),
      ),
    );
    await _writeIndexes(indexes);
    await prune();
  }

  @override
  Future<void> removeMessage(String id) async {
    await saveHeaders(
      (await readHeaders())
          .where((MailMessageHeader header) => header.id != id)
          .toList(growable: false),
    );
    await _box.delete('$_messagePrefix$id');

    final Map<String, MailAddressEntry> index = <String, MailAddressEntry>{};
    for (final String remainingId in await cachedMessageIds()) {
      final Object? decoded = await _decodedMessage(remainingId);
      if (decoded is! Map) continue;
      try {
        final MailMessageDetail message = MailCacheCodec.detailFrom(
          Map<String, dynamic>.from(decoded),
        );
        for (final MailAddress address in addressesOf(message)) {
          _indexAddress(index, address);
        }
      } catch (_) {}
    }
    await _box.write(
      _addressesKey,
      jsonEncode(
        index.values
            .map(
              (MailAddressEntry entry) => <String, dynamic>{
                'email': entry.email,
                if (entry.name != null) 'name': entry.name,
              },
            )
            .toList(),
      ),
    );
  }

  @override
  Future<List<MailMessageHeader>> searchHeaders(String query) async {
    final String term = normalizeMailSearchTerm(query);
    if (term.isEmpty) return <MailMessageHeader>[];

    final List<MailMessageHeader> headers = await readHeaders();
    final Map<String, MailMessageHeader> byId = <String, MailMessageHeader>{
      for (final MailMessageHeader h in headers) h.id: h,
    };
    final Map<String, MailMessageHeader> hits = <String, MailMessageHeader>{};
    for (final MailMessageHeader h in headers) {
      if (mailTextMatches(mailHeaderSearchFields(h), term)) hits[h.id] = h;
    }

    // One compact encrypted document replaces one decrypt+JSON parse per body.
    // It contains only normalised searchable text and a small header; base64
    // attachment bytes are neither decoded nor copied during search.
    final _MailCacheIndexes indexes = await _loadIndexes();
    for (final MapEntry<String, Map<String, dynamic>> candidate
        in indexes.search.entries) {
      final String id = candidate.key;
      if (hits.containsKey(id)) continue;
      final String text = candidate.value['text'] as String? ?? '';
      if (!text.contains(term)) continue;
      final Object? rawHeader = candidate.value['header'];
      if (rawHeader is! Map) continue;
      hits[id] =
          byId[id] ??
          MailCacheCodec.headerFrom(Map<String, dynamic>.from(rawHeader));
    }
    return sortMailSearchHits(hits.values.toList());
  }

  @override
  Future<List<MailAddressEntry>> knownAddresses() async {
    final Object? decoded = _decode(await _box.read(_addressesKey));
    if (decoded is! List) return <MailAddressEntry>[];
    try {
      return decoded
          .whereType<Map>()
          .map((Map<dynamic, dynamic> value) {
            final Map<String, dynamic> json = Map<String, dynamic>.from(value);
            return MailAddressEntry(
              email: (json['email'] as String?) ?? '',
              name: json['name'] as String?,
            );
          })
          .where((MailAddressEntry entry) => entry.email.isNotEmpty)
          .toList();
    } catch (_) {
      return <MailAddressEntry>[];
    }
  }

  @override
  Future<MailCacheStats> stats() async {
    final _MailCacheIndexes indexes = await _loadIndexes();
    final Iterable<String> keys = await _box.keys();
    int bytes = indexes.metadata.values.fold<int>(
      0,
      (int total, Map<String, dynamic> value) =>
          total + (value['bytes'] as int? ?? 0),
    );
    for (final String key in keys) {
      if (key.startsWith(_messagePrefix)) continue;
      final String? raw = await _box.read(key);
      if (raw != null) bytes += utf8.encode(raw).length;
    }
    return MailCacheStats(
      headerCount: (await readHeaders()).length,
      bodyCount: indexes.metadata.length,
      byteCount: bytes,
    );
  }

  @override
  Future<void> clearCachedBodies() async {
    final List<String> bodyKeys = (await _box.keys())
        .where((String key) => key.startsWith(_messagePrefix))
        .toList(growable: false);
    for (final String key in <String>[
      ...bodyKeys,
      _metadataKey,
      _searchKey,
      _addressesKey,
    ]) {
      await _box.delete(key);
    }
  }

  @override
  Future<void> prune() async {
    final _MailCacheIndexes indexes = await _loadIndexes();
    final DateTime now = _now().toUtc();
    final DateTime cutoff = now.subtract(policy.bodyRetention);
    final List<_MailBodyRecord> records = <_MailBodyRecord>[];
    for (final MapEntry<String, Map<String, dynamic>> entry
        in indexes.metadata.entries) {
      final Map<String, dynamic> value = entry.value;
      records.add(
        _MailBodyRecord(
          id: entry.key,
          bytes: value['bytes'] as int? ?? 0,
          date:
              DateTime.tryParse(value['date'] as String? ?? '') ??
              DateTime.tryParse(value['storedAt'] as String? ?? '') ??
              now,
          accessedAt:
              DateTime.tryParse(value['accessedAt'] as String? ?? '') ?? now,
        ),
      );
    }
    if (records.isEmpty) return;
    records.sort(
      (_MailBodyRecord a, _MailBodyRecord b) =>
          a.accessedAt.compareTo(b.accessedAt),
    );
    final _MailBodyRecord newest = records.reduce(
      (_MailBodyRecord a, _MailBodyRecord b) => a.date.isAfter(b.date) ? a : b,
    );
    final Set<String> remove = <String>{
      for (final _MailBodyRecord record in records)
        if (record.id != newest.id && record.date.isBefore(cutoff)) record.id,
    };
    final List<_MailBodyRecord> live = records
        .where((_MailBodyRecord record) => !remove.contains(record.id))
        .toList();
    int bytes = live.fold<int>(
      0,
      (int total, _MailBodyRecord record) => total + record.bytes,
    );
    while (live.length > policy.maxBodies || bytes > policy.maxBodyBytes) {
      final _MailBodyRecord evicted = live.removeAt(0);
      remove.add(evicted.id);
      bytes -= evicted.bytes;
    }
    for (final String id in remove) {
      await _box.delete('$_messagePrefix$id');
      indexes.metadata.remove(id);
      indexes.search.remove(id);
    }
    if (remove.isNotEmpty) await _writeIndexes(indexes);
  }

  @override
  Future<void> clear() async {
    for (final String key in (await _box.keys()).toList()) {
      await _box.delete(key);
    }
  }

  Future<_MailCacheIndexes> _loadIndexes() async {
    final Map<String, Map<String, dynamic>> metadata = _mapIndex(
      _decode(await _box.read(_metadataKey)),
    );
    final Map<String, Map<String, dynamic>> search = _mapIndex(
      _decode(await _box.read(_searchKey)),
    );
    bool changed = false;
    final DateTime now = _now().toUtc();
    for (final String id in await cachedMessageIds()) {
      if (metadata.containsKey(id) && search.containsKey(id)) continue;
      final String? raw = await _box.read('$_messagePrefix$id');
      final Object? decoded = _decode(raw);
      if (raw == null || decoded is! Map) continue;
      try {
        final MailMessageDetail detail = MailCacheCodec.detailFrom(
          Map<String, dynamic>.from(decoded),
        );
        metadata[id] = <String, dynamic>{
          'bytes': utf8.encode(raw).length,
          'storedAt': now.toIso8601String(),
          'accessedAt': now.toIso8601String(),
          'date': detail.date?.toUtc().toIso8601String(),
        };
        search[id] = MailCacheCodec.searchDocument(detail);
        changed = true;
      } catch (_) {}
    }
    final _MailCacheIndexes indexes = _MailCacheIndexes(metadata, search);
    if (changed) await _writeIndexes(indexes);
    return indexes;
  }

  Future<void> _writeIndexes(_MailCacheIndexes indexes) async {
    await _box.write(_metadataKey, jsonEncode(indexes.metadata));
    await _box.write(_searchKey, jsonEncode(indexes.search));
  }

  static Map<String, Map<String, dynamic>> _mapIndex(Object? value) {
    if (value is! Map) return <String, Map<String, dynamic>>{};
    return <String, Map<String, dynamic>>{
      for (final MapEntry<dynamic, dynamic> entry in value.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: Map<String, dynamic>.from(entry.value as Map),
    };
  }

  static Object? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}

class _MailCacheIndexes {
  const _MailCacheIndexes(this.metadata, this.search);

  final Map<String, Map<String, dynamic>> metadata;
  final Map<String, Map<String, dynamic>> search;
}

class _MailBodyRecord {
  const _MailBodyRecord({
    required this.id,
    required this.bytes,
    required this.date,
    required this.accessedAt,
  });

  final String id;
  final int bytes;
  final DateTime date;
  final DateTime accessedAt;
}

enum MailCacheInitMode { encrypted, memoryOnly, wipePending }

enum MailCacheInitFailure {
  legacyCleanupFailed,
  secureStorageUnavailable,
  hiveUnavailable,
  corruptStore,
}

class MailCacheInitResult {
  const MailCacheInitResult(this.mode, {this.failure});

  final MailCacheInitMode mode;
  final MailCacheInitFailure? failure;
}

class MailWipeResult {
  const MailWipeResult({
    required this.legacyBoxAbsent,
    required this.encryptedBoxAbsent,
    required this.keyAbsent,
  });

  final bool legacyBoxAbsent;
  final bool encryptedBoxAbsent;
  final bool keyAbsent;

  bool get isComplete => legacyBoxAbsent && encryptedBoxAbsent && keyAbsent;
}

/// Lifecycle boundary for the encrypted mail cache.
///
/// It owns the plaintext-v1 cleanup, encrypted-v2 activation and a write fence.
/// Wipe locks first, waits for already-started local writes, then removes and
/// verifies all persistent artifacts. Reads and writes otherwise fail soft.
class MailCacheManager implements MailCacheStore {
  MailCacheManager({
    EncryptedBox? encryptedBox,
    HiveInterface? hive,
    Future<void> Function()? initializeHive,
  }) : _hive = hive ?? Hive,
       _initializeHive = initializeHive ?? (() => Hive.initFlutter()),
       _encryptedBox =
           encryptedBox ??
           EncryptedBox(
             boxName: secureBoxName,
             keyStorageKey: keyStorageKey,
             hive: hive,
             initializeHive: initializeHive,
           );

  static const String legacyBoxName = 'campus_mail_cache_v1';
  static const String secureBoxName = 'campus_mail_cache_secure_v2';
  static const String keyStorageKey = 'mail.cache.key.v2';

  final HiveInterface _hive;
  final Future<void> Function() _initializeHive;
  final EncryptedBox _encryptedBox;
  final MemoryMailCache _memory = MemoryMailCache();
  final Set<Future<void>> _writes = <Future<void>>{};

  MailCacheStore _delegate = MemoryMailCache();
  bool _locked = true;

  /// True when the encrypted store could not be opened and mail is only kept
  /// for this session.
  ///
  /// Fail-soft is the right behaviour — a broken cache must not take the
  /// mailbox down with it — but silently degrading leaves an empty cache
  /// looking exactly like an empty mailbox, and offline reading looking
  /// simply broken. The state has to be visible for that to be honest.
  bool get isMemoryOnly => identical(_delegate, _memory);

  Future<MailCacheInitResult> initialize({required bool accountExists}) async {
    if (!await _deleteLegacyAndConfirm()) {
      _delegate = _memory;
      _locked = false;
      return const MailCacheInitResult(
        MailCacheInitMode.memoryOnly,
        failure: MailCacheInitFailure.legacyCleanupFailed,
      );
    }
    if (!accountExists) {
      final EncryptedBoxWipeResult wiped = await _encryptedBox.wipeChecked();
      _delegate = _memory;
      _locked = false;
      return MailCacheInitResult(
        MailCacheInitMode.memoryOnly,
        failure: wiped.isComplete ? null : MailCacheInitFailure.hiveUnavailable,
      );
    }
    return activate();
  }

  Future<MailCacheInitResult> activate() async {
    if (!await _deleteLegacyAndConfirm()) {
      _delegate = _memory;
      _locked = false;
      return const MailCacheInitResult(
        MailCacheInitMode.memoryOnly,
        failure: MailCacheInitFailure.legacyCleanupFailed,
      );
    }
    final EncryptedBoxOpenResult result = await _encryptedBox.openChecked();
    if (result.isOpen) {
      _delegate = EncryptedMailCache(_encryptedBox);
      _locked = false;
      return const MailCacheInitResult(MailCacheInitMode.encrypted);
    }
    _delegate = _memory;
    _locked = false;
    return MailCacheInitResult(
      MailCacheInitMode.memoryOnly,
      failure: switch (result.failure) {
        EncryptedBoxOpenFailure.secureStorageUnavailable =>
          MailCacheInitFailure.secureStorageUnavailable,
        EncryptedBoxOpenFailure.cleanupFailed =>
          MailCacheInitFailure.corruptStore,
        _ => MailCacheInitFailure.hiveUnavailable,
      },
    );
  }

  void lock() {
    _locked = true;
  }

  Future<bool> _deleteLegacyAndConfirm() async {
    try {
      await _initializeHive();
      await _hive.deleteBoxFromDisk(legacyBoxName);
      return !await _hive.boxExists(legacyBoxName);
    } catch (_) {
      return false;
    }
  }

  Future<MailWipeResult> wipe() async {
    lock();
    await Future.wait<void>(_writes.toList());
    await _memory.clear();
    final EncryptedBoxWipeResult encrypted = await _encryptedBox.wipeChecked();
    final bool legacyAbsent = await _deleteLegacyAndConfirm();
    _delegate = _memory;
    return MailWipeResult(
      legacyBoxAbsent: legacyAbsent,
      encryptedBoxAbsent: encrypted.boxAbsent,
      keyAbsent: encrypted.keyAbsent,
    );
  }

  @override
  Future<List<MailMessageHeader>> readHeaders() async => _locked
      ? <MailMessageHeader>[]
      : _failSoft(() => _delegate.readHeaders(), <MailMessageHeader>[]);

  @override
  Future<Set<String>> cachedMessageIds() async => _locked
      ? <String>{}
      : _failSoft(() => _delegate.cachedMessageIds(), <String>{});

  @override
  Future<MailMessageDetail?> readMessage(String id) async => _locked
      ? null
      : _failSoft<MailMessageDetail?>(() => _delegate.readMessage(id), null);

  @override
  Future<List<MailMessageHeader>> searchHeaders(String query) async => _locked
      ? <MailMessageHeader>[]
      : _failSoft(() => _delegate.searchHeaders(query), <MailMessageHeader>[]);

  @override
  Future<List<MailAddressEntry>> knownAddresses() async => _locked
      ? <MailAddressEntry>[]
      : _failSoft(() => _delegate.knownAddresses(), <MailAddressEntry>[]);

  @override
  Future<MailCacheStats> stats() async => _locked
      ? const MailCacheStats(headerCount: 0, bodyCount: 0, byteCount: 0)
      : _failSoft(
          () => _delegate.stats(),
          const MailCacheStats(headerCount: 0, bodyCount: 0, byteCount: 0),
        );

  @override
  Future<void> saveHeaders(List<MailMessageHeader> headers) =>
      _write(() => _delegate.saveHeaders(headers));

  @override
  Future<void> saveMessage(MailMessageDetail message) =>
      _write(() => _delegate.saveMessage(message));

  @override
  Future<void> saveMessages(List<MailMessageDetail> messages) =>
      _write(() => _delegate.saveMessages(messages));

  @override
  Future<void> clearCachedBodies() =>
      _write(() => _delegate.clearCachedBodies());

  @override
  Future<void> removeMessage(String id) =>
      _write(() => _delegate.removeMessage(id));

  @override
  Future<void> prune() => _write(() => _delegate.prune());

  Future<void> _write(Future<void> Function() operation) async {
    if (_locked) return;
    late final Future<void> pending;
    pending = operation()
        .catchError((_) {})
        .whenComplete(() => _writes.remove(pending));
    _writes.add(pending);
    await pending;
  }

  static Future<T> _failSoft<T>(
    Future<T> Function() operation,
    T fallback,
  ) async {
    try {
      return await operation();
    } catch (_) {
      return fallback;
    }
  }

  @override
  Future<void> clear() async {
    final MailWipeResult result = await wipe();
    if (!result.isComplete) throw const MailCacheWipeIncomplete();
  }
}

class MailCacheWipeIncomplete implements Exception {
  const MailCacheWipeIncomplete();
}
