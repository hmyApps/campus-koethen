// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal key/value abstraction for **small scalar settings only**.
///
/// Content caching happens in `core/cache` (hive_ce). Nothing large or
/// structured is ever written through this interface.
abstract interface class KeyValueStore {
  String? getString(String key);

  List<String>? getStringList(String key);

  int? getInt(String key);

  Future<void> setString(String key, String value);

  Future<void> setStringList(String key, List<String> value);

  Future<void> setInt(String key, int value);

  /// Removes [key]. Returns false when the removal could not be persisted.
  Future<bool> remove(String key);
}

/// [KeyValueStore] backed by `shared_preferences`.
///
/// Every read is defensive: a corrupted or type-mismatched entry degrades to
/// `null` instead of throwing, so a broken preference can never crash the app.
class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPreferencesStore> open() async {
    return SharedPreferencesStore(await SharedPreferences.getInstance());
  }

  @override
  String? getString(String key) {
    try {
      return _prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  @override
  List<String>? getStringList(String key) {
    try {
      return _prefs.getStringList(key);
    } catch (_) {
      return null;
    }
  }

  @override
  int? getInt(String key) {
    try {
      return _prefs.getInt(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setString(String key, String value) async {
    try {
      await _prefs.setString(key, value);
    } catch (_) {
      // Persisting a preference is best effort; the in-memory state stays valid.
    }
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    try {
      await _prefs.setStringList(key, value);
    } catch (_) {
      // See setString.
    }
  }

  @override
  Future<void> setInt(String key, int value) async {
    try {
      await _prefs.setInt(key, value);
    } catch (_) {
      // See setString.
    }
  }

  @override
  Future<bool> remove(String key) async {
    try {
      return await _prefs.remove(key);
    } catch (_) {
      // Still never thrown (see setString), but reported: a reset has to know
      // whether it actually took hold (SET-6).
      return false;
    }
  }
}

/// In-memory [KeyValueStore]. Used by tests and as a last-resort fallback when
/// `shared_preferences` cannot be initialised at all.
class InMemoryKeyValueStore implements KeyValueStore {
  InMemoryKeyValueStore([Map<String, Object>? initialValues])
    : _values = <String, Object>{...?initialValues};

  final Map<String, Object> _values;

  @override
  String? getString(String key) {
    final Object? value = _values[key];
    return value is String ? value : null;
  }

  @override
  List<String>? getStringList(String key) {
    final Object? value = _values[key];
    return value is List<String> ? List<String>.of(value) : null;
  }

  @override
  int? getInt(String key) {
    final Object? value = _values[key];
    return value is int ? value : null;
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _values[key] = List<String>.of(value);
  }

  @override
  Future<void> setInt(String key, int value) async {
    _values[key] = value;
  }

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }
}
