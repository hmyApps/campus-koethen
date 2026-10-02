// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../core/cache/encrypted_box.dart';
import '../domain/request_drafts.dart';
import '../domain/request_store.dart';
import '../domain/submitted_case.dart';

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
class EncryptedRequestStore implements RequestStore {
  EncryptedRequestStore({EncryptedBox? box, LegacyDraftBox? legacy})
    : _box =
          box ??
          EncryptedBox(
            boxName: 'campus_requests_secure_v1',
            keyStorageKey: 'campus_requests_secure_key_v1',
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
    final String? raw = await _box.read(_draftsKey);
    return _decode(raw, RequestDraft.fromJson);
  }

  @override
  Future<void> writeDrafts(List<RequestDraft> drafts) async {
    final String payload = jsonEncode(
      drafts.map((RequestDraft d) => d.toJson()).toList(),
    );
    if (!await _box.writeChecked(_draftsKey, payload)) {
      throw const RequestStoreUnavailable();
    }
  }

  @override
  Future<List<SubmittedCase>> readCases() async {
    final String? raw = await _box.read(_casesKey);
    return _decode(raw, SubmittedCase.fromJson);
  }

  @override
  Future<void> writeCases(List<SubmittedCase> cases) async {
    final String payload = jsonEncode(
      cases.map((SubmittedCase c) => c.toJson()).toList(),
    );
    // Confirm this exact payload before the caller deletes the draft. Merely
    // seeing any value here could be a stale predecessor after a failed write.
    if (!await _box.writeChecked(_casesKey, payload)) {
      throw const RequestStoreUnavailable();
    }
  }

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
        final List<RequestDraft> existing = _decode(
          await _box.read(_draftsKey),
          RequestDraft.fromJson,
        );
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

/// Thrown when local storage could not keep what it was given.
class RequestStoreUnavailable implements Exception {
  const RequestStoreUnavailable();

  @override
  String toString() => 'RequestStoreUnavailable';
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
