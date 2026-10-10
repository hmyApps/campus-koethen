// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../core/cache/encrypted_box.dart';
import '../domain/request_drafts.dart';
import '../domain/request_store.dart';
import '../domain/submitted_case.dart';

export '../domain/request_store.dart' show RequestStoreUnavailable;

/// [RequestStore] on top of the app's encrypted box.
///
/// Everything in here is either a credential or personal data: a draft can
/// reference a student card, and a submitted case holds a status link that is
/// equivalent to a bearer token. The first version kept both in a plaintext
/// Hive box — enough for a to-do list, not for these. The AES key lives only in
/// the keychain/keystore (see [EncryptedBox]).
///
/// Writes **report their failure**. The rest of the app degrades quietly when
/// a cache is unavailable, but here the caller has to know whether a case was
/// safely recorded: if it was not, the draft that produced it must stay.
///
/// Reads **report their failure** too. "Could not read" is never folded into
/// "nothing stored": the next write would then replace every status link on
/// the device with whatever the caller happened to hold. A list that cannot be
/// decoded blocks writing and stays on disk byte for byte; single entries this
/// build cannot parse are carried through every write unchanged.
class EncryptedRequestStore implements RequestStore {
  EncryptedRequestStore({EncryptedBox? box, LegacyDraftBox? legacy})
    : _box =
          box ??
          EncryptedBox(
            boxName: 'campus_requests_secure_v1',
            keyStorageKey: 'campus_requests_secure_key_v1',
            // Not a cache: an unopenable box is kept for a retry or the
            // deliberate wipe, never recreated empty.
            discardUnreadable: false,
          ),
      _legacy = legacy ?? const LegacyDraftBox();

  static const String _draftsKey = 'drafts';
  static const String _casesKey = 'cases';

  @override
  Future<bool> wipeEverything() async {
    // The legacy plaintext box first: it is the one whose leftovers would be
    // readable without any key at all.
    await _legacy.clear();
    final EncryptedBoxWipeResult wiped = await _box.wipeChecked();
    return wiped.isComplete;
  }

  final EncryptedBox _box;
  final LegacyDraftBox _legacy;

  bool _migrated = false;

  @override
  Future<List<RequestDraft>> readDrafts() async {
    await _migrateLegacyDrafts();
    return (await _readList(_draftsKey, RequestDraft.fromJson)).items;
  }

  @override
  Future<void> writeDrafts(List<RequestDraft> drafts) => _writeList(
    _draftsKey,
    drafts.map((RequestDraft d) => d.toJson()),
    RequestDraft.fromJson,
  );

  @override
  Future<List<SubmittedCase>> readCases() async =>
      (await _readList(_casesKey, SubmittedCase.fromJson)).items;

  @override
  Future<void> writeCases(List<SubmittedCase> cases) => _writeList(
    _casesKey,
    cases.map((SubmittedCase c) => c.toJson()),
    SubmittedCase.fromJson,
  );

  /// Reads one stored list. **Throws** [RequestStoreUnavailable] when the box
  /// cannot be read or the list cannot be decoded — never an empty list.
  Future<_StoredList<T>> _readList<T>(
    String key,
    T? Function(Object?) parse,
  ) async {
    final String? raw;
    try {
      raw = await _box.readChecked(key);
    } on EncryptedBoxUnavailable {
      throw const RequestStoreUnavailable();
    }
    return _StoredList.decode(raw, parse);
  }

  Future<void> _writeList<T>(
    String key,
    Iterable<Map<String, dynamic>> entries,
    T? Function(Object?) parse,
  ) async {
    // Read what is there first: a list that cannot be read is never written
    // over, and entries this build cannot parse travel along unchanged.
    final _StoredList<T> stored = await _readList(key, parse);
    final String payload = jsonEncode(<Object?>[
      ...entries,
      ...stored.unparsed,
    ]);
    // Confirm this exact payload before the caller deletes the draft. Merely
    // seeing any value here could be a stale predecessor after a failed write.
    if (!await _box.writeChecked(key, payload)) {
      throw const RequestStoreUnavailable();
    }
  }

  /// Lenient decoding, used for the legacy plaintext box only.
  static List<T> _decode<T>(String? raw, T? Function(Object?) parse) {
    if (raw == null) return <T>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return decoded.map(parse).whereType<T>().toList();
    } catch (_) {
      return <T>[];
    }
  }

  /// Moves drafts out of the old plaintext box, once.
  ///
  /// Order matters: read, write encrypted, verify, and only then clear the old
  /// box. A crash anywhere in between leaves the plaintext copy in place — a
  /// duplicate is recoverable, a lost draft is not.
  Future<void> _migrateLegacyDrafts() async {
    if (_migrated) return;
    _migrated = true;

    final String? raw = await _legacy.read();
    if (raw == null) return;

    try {
      final List<RequestDraft> old = _decode(raw, RequestDraft.fromJson);
      if (old.isNotEmpty) {
        // Strict: an unreadable encrypted box must not look empty here
        // either, or the merge would replace its drafts with the old ones.
        final List<RequestDraft> existing = (await _readList(
          _draftsKey,
          RequestDraft.fromJson,
        )).items;
        final Set<String> known = existing
            .map((RequestDraft d) => d.id)
            .toSet();
        final List<RequestDraft> merged = <RequestDraft>[
          ...existing,
          ...old.where((RequestDraft d) => !known.contains(d.id)),
        ];
        await writeDrafts(merged);
      }
      // Only now: the encrypted copy exists and was read back.
      await _legacy.clear();
    } catch (_) {
      // Leave the plaintext box alone and try again next launch.
    }
  }
}

/// One stored list: what this build understands, and what it does not.
class _StoredList<T> {
  const _StoredList(this.items, this.unparsed);

  /// Throws [RequestStoreUnavailable] for anything that is not a JSON list.
  static _StoredList<T> decode<T>(String? raw, T? Function(Object?) parse) {
    if (raw == null) return _StoredList<T>(<T>[], const <Object?>[]);
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const RequestStoreUnavailable();
    }
    if (decoded is! List) throw const RequestStoreUnavailable();
    final List<T> items = <T>[];
    final List<Object?> unparsed = <Object?>[];
    for (final Object? entry in decoded) {
      T? parsed;
      try {
        parsed = parse(entry);
      } catch (_) {
        parsed = null;
      }
      if (parsed == null) {
        unparsed.add(entry);
      } else {
        items.add(parsed);
      }
    }
    return _StoredList<T>(items, unparsed);
  }

  final List<T> items;

  /// Raw entries kept verbatim so a write never drops them.
  final List<Object?> unparsed;
}

/// The plaintext box the first version wrote drafts to.
///
/// Kept only to migrate away from it. Never written to again.
class LegacyDraftBox {
  const LegacyDraftBox();

  static const String boxName = 'campus_requests_v1';
  static const String draftsKey = 'drafts';

  Future<Box<String>?> _open() async {
    try {
      await Hive.initFlutter();
      if (!await Hive.boxExists(boxName)) return null;
      return await Hive.openBox<String>(boxName);
    } catch (_) {
      return null;
    }
  }

  Future<String?> read() async {
    try {
      return (await _open())?.get(draftsKey);
    } catch (_) {
      return null;
    }
  }

  /// Deletes the box from disk, so the plaintext copy is really gone rather
  /// than merely emptied.
  Future<void> clear() async {
    try {
      final Box<String>? box = await _open();
      if (box == null) return;
      await box.deleteFromDisk();
    } catch (_) {}
  }
}
