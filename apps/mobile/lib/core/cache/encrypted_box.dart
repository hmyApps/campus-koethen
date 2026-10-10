// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../security/app_secure_storage.dart';

enum EncryptedBoxOpenFailure {
  secureStorageUnavailable,
  hiveUnavailable,
  cleanupFailed,
}

class EncryptedBoxOpenResult {
  const EncryptedBoxOpenResult._({this.failure});

  const EncryptedBoxOpenResult.opened() : this._();

  const EncryptedBoxOpenResult.failed(EncryptedBoxOpenFailure failure)
    : this._(failure: failure);

  final EncryptedBoxOpenFailure? failure;

  bool get isOpen => failure == null;
}

class EncryptedBoxWipeResult {
  const EncryptedBoxWipeResult({
    required this.keyAbsent,
    required this.boxAbsent,
  });

  final bool keyAbsent;
  final bool boxAbsent;

  bool get isComplete => keyAbsent && boxAbsent;
}

/// Thrown by [EncryptedBox.readChecked] when the box could not be opened or
/// read.
///
/// Carries neither the platform error nor anything that was stored: callers
/// only need to know that "nothing there" is **not** what happened.
class EncryptedBoxUnavailable implements Exception {
  const EncryptedBoxUnavailable();

  @override
  String toString() => 'EncryptedBoxUnavailable';
}

/// A string key/value store backed by an encrypted `hive_ce` box.
///
/// Normal reads and writes fail soft. Security-sensitive initialization and
/// deletion use [openChecked] and [wipeChecked], which verify key material and
/// artifact absence without exposing raw platform errors or stored values.
///
/// Opening and wiping run **one at a time** per instance. Two callers that
/// reach a fresh box in the same frame share a single open attempt: separate
/// attempts would each generate a key, Hive would keep the box opened with
/// the first one and ignore the second, while the keystore ended up holding
/// the second — and the next start would silently truncate the box.
class EncryptedBox {
  EncryptedBox({
    required this.boxName,
    required this.keyStorageKey,
    FlutterSecureStorage? storage,
    HiveInterface? hive,
    Future<void> Function()? initializeHive,
    this.discardUnreadable = true,
  }) : _storage = storage ?? deviceSecureStorage(),
       _hive = hive ?? Hive,
       _initializeHive = initializeHive ?? (() => Hive.initFlutter());

  final String boxName;
  final String keyStorageKey;

  /// Whether a box that its valid key cannot open may be deleted and
  /// recreated empty.
  ///
  /// Right for a cache, which is rebuilt from its source. Wrong for user data
  /// that exists nowhere else — the status links of submitted requests are
  /// the only access to those cases — so such stores pass `false`: an
  /// unopenable box is left on disk untouched and reported as unavailable,
  /// and only the explicit [wipeChecked] removes it.
  ///
  /// A box whose key is **missing** is discarded either way: without the key
  /// (gone after a keystore reset, or never restored onto a new device) the
  /// ciphertext cannot be decrypted by anyone, and keeping it would only
  /// lock the feature.
  final bool discardUnreadable;

  final FlutterSecureStorage _storage;
  final HiveInterface _hive;
  final Future<void> Function() _initializeHive;

  Box<String>? _box;

  /// The open attempt in flight, shared by every caller arriving meanwhile.
  Future<EncryptedBoxOpenResult>? _opening;

  /// Tail of the open/wipe queue: lifecycle steps never overlap.
  Future<void> _lifecycle = Future<void>.value();

  /// Set by [wipeAndSeal]: implicit opens behind [read], [write] and the
  /// other accessors are refused until [openChecked] is called again.
  bool _sealed = false;

  /// The app-wide keychain/keystore configuration — see
  /// [appSecureStorage]. Kept as a named member because the box's
  /// constructor reads it as a default.
  static FlutterSecureStorage deviceSecureStorage() => appSecureStorage();

  /// Opens the box, creating and verifying its key on first use.
  ///
  /// An explicit open: it also lifts the seal a [wipeAndSeal] put in place.
  Future<EncryptedBoxOpenResult> openChecked() {
    _sealed = false;
    return _openShared();
  }

  Future<EncryptedBoxOpenResult> _openShared() {
    final Box<String>? box = _box;
    if (box != null && box.isOpen) {
      return Future<EncryptedBoxOpenResult>.value(
        const EncryptedBoxOpenResult.opened(),
      );
    }
    return _opening ??= _openOnce();
  }

  Future<EncryptedBoxOpenResult> _openOnce() async {
    try {
      return await _exclusive(_openFresh);
    } finally {
      // Cleared either way, so a failed attempt can be retried later.
      _opening = null;
    }
  }

  /// Runs [action] after every open or wipe queued before it.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final Future<T> result = _lifecycle.then((_) => action());
    _lifecycle = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<EncryptedBoxOpenResult> _openFresh() async {
    final Box<String>? box = _box;
    if (box != null && box.isOpen) {
      return const EncryptedBoxOpenResult.opened();
    }
    // Sealed after this attempt was queued: the wipe that sealed it wins, and
    // nothing may recreate the key or the box behind its back.
    if (_sealed) {
      return const EncryptedBoxOpenResult.failed(
        EncryptedBoxOpenFailure.hiveUnavailable,
      );
    }
    try {
      return await _openUnguarded();
    } catch (_) {
      _box = null;
      return const EncryptedBoxOpenResult.failed(
        EncryptedBoxOpenFailure.hiveUnavailable,
      );
    }
  }

  Future<EncryptedBoxOpenResult> _openUnguarded() async {
    try {
      await _initializeHive();
    } catch (_) {
      return const EncryptedBoxOpenResult.failed(
        EncryptedBoxOpenFailure.hiveUnavailable,
      );
    }

    String? encodedKey;
    try {
      encodedKey = await _storage.read(key: keyStorageKey);
    } catch (_) {
      return const EncryptedBoxOpenResult.failed(
        EncryptedBoxOpenFailure.secureStorageUnavailable,
      );
    }

    List<int>? key = _validKey(encodedKey);
    if (key == null) {
      if (!await _deleteBoxAndConfirm()) {
        return const EncryptedBoxOpenResult.failed(
          EncryptedBoxOpenFailure.cleanupFailed,
        );
      }
      key = _hive.generateSecureKey();
      if (key.length != 32) {
        return const EncryptedBoxOpenResult.failed(
          EncryptedBoxOpenFailure.secureStorageUnavailable,
        );
      }
      final String generated = base64Encode(key);
      try {
        await _storage.write(key: keyStorageKey, value: generated);
        final String? written = await _storage.read(key: keyStorageKey);
        if (written != generated || _validKey(written) == null) {
          return const EncryptedBoxOpenResult.failed(
            EncryptedBoxOpenFailure.secureStorageUnavailable,
          );
        }
      } catch (_) {
        return const EncryptedBoxOpenResult.failed(
          EncryptedBoxOpenFailure.secureStorageUnavailable,
        );
      }
    }

    if (await _openWithKey(key)) {
      return const EncryptedBoxOpenResult.opened();
    }

    // User data stays exactly where it is: the failure may be transient, and
    // retrying — or the explicit wipe — is the caller's decision.
    if (!discardUnreadable) {
      return const EncryptedBoxOpenResult.failed(
        EncryptedBoxOpenFailure.hiveUnavailable,
      );
    }

    // A cache is disposable. A valid key with an unreadable box is recovered
    // once by deleting the corrupt/incompatible ciphertext and reopening empty.
    if (!await _deleteBoxAndConfirm() || !await _openWithKey(key)) {
      return const EncryptedBoxOpenResult.failed(
        EncryptedBoxOpenFailure.hiveUnavailable,
      );
    }
    return const EncryptedBoxOpenResult.opened();
  }

  Future<bool> _openWithKey(List<int> key) async {
    try {
      _box = await _hive.openBox<String>(
        boxName,
        encryptionCipher: HiveAesCipher(key),
      );
      return true;
    } catch (_) {
      _box = null;
      return false;
    }
  }

  static List<int>? _validKey(String? encoded) {
    if (encoded == null) return null;
    try {
      final List<int> decoded = base64Decode(encoded);
      return decoded.length == 32 ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _deleteBoxAndConfirm() async {
    try {
      if (_box?.isOpen ?? false) await _box!.close();
      _box = null;
      await _hive.deleteBoxFromDisk(boxName);
      return !await _hive.boxExists(boxName);
    } catch (_) {
      return false;
    }
  }

  /// The implicit open behind every read and write. Refused while sealed.
  Future<Box<String>?> _open() async {
    if (_sealed) return null;
    final EncryptedBoxOpenResult result = await _openShared();
    // Sealed while this open was running: the box is about to be wiped.
    if (_sealed || !result.isOpen) return null;
    return _box;
  }

  Future<String?> read(String key) async {
    try {
      return (await _open())?.get(key);
    } catch (_) {
      return null;
    }
  }

  /// Like [read], but an unavailable box **throws** [EncryptedBoxUnavailable]
  /// instead of reading as absent.
  ///
  /// For data that is not a cache: a caller that took "could not open" for
  /// "nothing stored" would write its next update over everything that is
  /// still on disk.
  Future<String?> readChecked(String key) async {
    final Box<String>? box = await _open();
    if (box == null) throw const EncryptedBoxUnavailable();
    try {
      return box.get(key);
    } catch (_) {
      throw const EncryptedBoxUnavailable();
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await (await _open())?.put(key, value);
    } catch (_) {}
  }

  /// Persists [value] and confirms that this exact payload can be read back.
  ///
  /// Security-sensitive callers must not infer success merely from a
  /// non-null read: an older value may still be present after a failed write.
  Future<bool> writeChecked(String key, String value) async {
    try {
      final Box<String>? box = await _open();
      if (box == null) return false;
      await box.put(key, value);
      return box.get(key) == value;
    } catch (_) {
      return false;
    }
  }

  /// Writes a related group with one Hive operation.
  ///
  /// Values still pass through the box's [HiveAesCipher]; this only avoids a
  /// separate persistence round trip for every entry in an already prepared
  /// batch. Like [write], cache failures remain best-effort.
  Future<void> writeAll(Map<String, String> entries) async {
    if (entries.isEmpty) return;
    try {
      await (await _open())?.putAll(entries);
    } catch (_) {}
  }

  Future<void> delete(String key) async {
    try {
      await (await _open())?.delete(key);
    } catch (_) {}
  }

  Future<Iterable<String>> keys() async {
    try {
      return (await _open())?.keys.whereType<String>().toList() ??
          const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  /// Deletes the key and the box and verifies both are gone.
  ///
  /// Waits for an open that is already running. Afterwards the next read or
  /// write opens a fresh, empty box on demand — the behaviour every cache
  /// relies on. See [wipeAndSeal] for a store that must stay closed.
  Future<EncryptedBoxWipeResult> wipeChecked() => _exclusive(_wipeUnguarded);

  /// [wipeChecked], and keeps the box closed afterwards.
  ///
  /// Until [openChecked] is called again, implicit opens are refused: a read
  /// path that was already running when the wipe began cannot recreate the
  /// key and the box — and then write into them — behind the wipe's back.
  /// Opt-in, because the other stores rely on reopening on demand.
  Future<EncryptedBoxWipeResult> wipeAndSeal() {
    _sealed = true;
    return wipeChecked();
  }

  Future<EncryptedBoxWipeResult> _wipeUnguarded() async {
    try {
      await _initializeHive();
    } catch (_) {}

    bool keyAbsent = false;
    try {
      await _storage.delete(key: keyStorageKey);
      keyAbsent = await _storage.read(key: keyStorageKey) == null;
    } catch (_) {}

    final bool boxAbsent = await _deleteBoxAndConfirm();
    return EncryptedBoxWipeResult(keyAbsent: keyAbsent, boxAbsent: boxAbsent);
  }

  /// Best-effort compatibility API for existing non-mail caches.
  Future<void> wipe() async {
    await wipeChecked();
  }
}
