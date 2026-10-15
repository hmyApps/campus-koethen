// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../prefs/key_value_store.dart';
import '../prefs/preference_keys.dart';

/// The reader's switch for the periodic background sync. On unless switched
/// off; what actually runs still depends on the connected sources and the
/// notification categories the reader opted into.
class BackgroundSyncSettings {
  const BackgroundSyncSettings(this._store);

  final KeyValueStore _store;

  bool get enabled => _store.getInt(PreferenceKeys.backgroundSyncEnabled) != 0;

  Future<void> setEnabled(bool value) =>
      _store.setInt(PreferenceKeys.backgroundSyncEnabled, value ? 1 : 0);
}

/// Remembers, across runs, that the mail server refused the stored password.
///
/// Every refused login counts against the central university account. A
/// background run that logs in again every fifteen minutes with a password
/// the server already refused would lock it within hours.
class BackgroundMailGuard {
  const BackgroundMailGuard(this._store);

  final KeyValueStore _store;

  bool get blocked => _store.getInt(PreferenceKeys.backgroundMailRejected) == 1;

  Future<void> block() =>
      _store.setInt(PreferenceKeys.backgroundMailRejected, 1);

  /// A new sign-in, a sign-out or a successful sync lifts the block.
  Future<void> release() async {
    if (blocked) await _store.remove(PreferenceKeys.backgroundMailRejected);
  }
}
