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

/// A string key/value store backed by an encrypted `hive_ce` box.
///
/// Normal reads and writes fail soft. Security-sensitive initialization and
/// deletion use [openChecked] and [wipeChecked], which verify key material and
/// artifact absence without exposing raw platform errors or stored values.
class EncryptedBox {
  EncryptedBox({
    required this.boxName,
    required this.keyStorageKey,
    FlutterSecureStorage? storage,
    HiveInterface? hive,
    Future<void> Function()? initializeHive,
  }) : _storage = storage ?? deviceSecureStorage(),
       _hive = hive ?? Hive,
       _initializeHive = initializeHive ?? (() => Hive.initFlutter());

  final String boxName;
  final String keyStorageKey;

  final FlutterSecureStorage _storage;
  final HiveInterface _hive;
  final Future<void> Function() _initializeHive;

  Box<String>? _box;

  /// The app-wide keychain/keystore configuration — see
  /// [appSecureStorage]. Kept as a named member because the box's
  /// constructor reads it as a default.
  static FlutterSecureStorage deviceSecureStorage() => appSecureStorage();

  Future<EncryptedBoxOpenResult> openChecked() async {
    if (_box != null && _box!.isOpen) {
      return const EncryptedBoxOpenResult.opened();
    }

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

  Future<Box<String>?> _open() async {
    final EncryptedBoxOpenResult result = await openChecked();
    return result.isOpen ? _box : null;
  }

  Future<String?> read(String key) async {
    try {
      return (await _open())?.get(key);
    } catch (_) {
      return null;
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

  Future<EncryptedBoxWipeResult> wipeChecked() async {
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
