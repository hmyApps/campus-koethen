// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/secure_nextcloud_favourite_store.dart';
import '../domain/nextcloud_account.dart';
import '../domain/nextcloud_failure.dart';
import '../domain/nextcloud_favourite_store.dart';
import 'nextcloud_account_controller.dart';
import 'nextcloud_providers.dart';

class NextcloudFavouritesController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final NextcloudAccount? account = await ref.watch(
      nextcloudAccountControllerProvider.future,
    );
    if (account == null) return const <String>{};
    return ref.read(nextcloudFavouriteStoreProvider).read(account);
  }

  Future<void> toggle(String path) async {
    final NextcloudAccount? account = await ref.read(
      nextcloudAccountControllerProvider.future,
    );
    if (account == null) {
      throw const NextcloudFailure(NextcloudFailureKind.notConnected);
    }
    final Set<String> previous = state.value ?? await future;
    final Set<String> next = <String>{...previous};
    if (!next.remove(path)) {
      if (next.length >= SecureNextcloudFavouriteStore.maximumFavourites) {
        throw const NextcloudFailure(
          NextcloudFailureKind.favouriteLimitReached,
        );
      }
      next.add(path);
    }
    state = AsyncData<Set<String>>(Set<String>.unmodifiable(next));
    try {
      final NextcloudFavouriteStore store = ref.read(
        nextcloudFavouriteStoreProvider,
      );
      await store.write(account, next);
    } catch (_) {
      state = AsyncData<Set<String>>(previous);
      rethrow;
    }
  }
}

final AsyncNotifierProvider<NextcloudFavouritesController, Set<String>>
nextcloudFavouritesControllerProvider =
    AsyncNotifierProvider<NextcloudFavouritesController, Set<String>>(
      NextcloudFavouritesController.new,
      retry: (_, _) => null,
    );
