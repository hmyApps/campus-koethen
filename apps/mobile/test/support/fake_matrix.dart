// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory secure storage with switchable failures for the chat tests.
class MemorySecureStorage extends FlutterSecureStorage {
  MemorySecureStorage({Map<String, String>? values})
    : values = values ?? <String, String>{};

  final Map<String, String> values;

  /// Every read throws, as a keystore that cannot be opened does.
  bool readFails = false;

  /// Writes of these keys are silently dropped, as a failed keystore write
  /// that does not report itself.
  final Set<String> droppedWrites = <String>{};

  /// Deletes of these keys are silently dropped.
  final Set<String> droppedDeletes = <String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readFails) throw StateError('secure storage unavailable');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (droppedWrites.contains(key)) return;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (droppedDeletes.contains(key)) return;
    values.remove(key);
  }
}
