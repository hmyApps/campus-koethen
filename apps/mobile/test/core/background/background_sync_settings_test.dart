// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/background/background_sync_settings.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the background sync is on until the reader switches it off', () async {
    final BackgroundSyncSettings settings = BackgroundSyncSettings(
      InMemoryKeyValueStore(),
    );

    expect(settings.enabled, isTrue);
    await settings.setEnabled(false);
    expect(settings.enabled, isFalse);
    await settings.setEnabled(true);
    expect(settings.enabled, isTrue);
  });

  test('a rejected mail password blocks until it is released', () async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    final BackgroundMailGuard guard = BackgroundMailGuard(store);

    expect(guard.blocked, isFalse);
    await guard.block();
    expect(BackgroundMailGuard(store).blocked, isTrue);
    await guard.release();
    expect(guard.blocked, isFalse);
  });
}
