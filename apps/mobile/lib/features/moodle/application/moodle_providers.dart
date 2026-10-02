// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/session_guard.dart';
import '../../../core/time/clock.dart';
import '../data/encrypted_moodle_cache.dart';
import '../data/moodle_file_downloader.dart';
import '../data/moodle_http_client.dart';
import '../data/moodle_repository_impl.dart';
import '../data/secure_moodle_token_store.dart';
import '../domain/moodle_account.dart';
import '../domain/moodle_api_client.dart';
import '../domain/moodle_cache.dart';
import '../domain/moodle_downloader.dart';
import '../domain/moodle_profile.dart';
import '../domain/moodle_repository.dart';

/// The pinned Moodle endpoints (host allowlist).
final Provider<MoodleProfile> moodleProfileProvider = Provider<MoodleProfile>(
  (Ref ref) => const MoodleProfile(),
);

/// The read-only Moodle Web Services client. Overridden in tests.
final Provider<MoodleApiClient> moodleApiClientProvider =
    Provider<MoodleApiClient>(
      (Ref ref) => MoodleHttpClient(profile: ref.watch(moodleProfileProvider)),
    );

/// Secure token storage (device keychain/keystore). Overridden in tests.
final Provider<MoodleTokenStore> moodleTokenStoreProvider =
    Provider<MoodleTokenStore>((Ref ref) => SecureMoodleTokenStore());

/// The encrypted on-device cache. Overridden in tests.
final Provider<MoodleCacheStore> moodleCacheStoreProvider =
    Provider<MoodleCacheStore>((Ref ref) => EncryptedMoodleCache());

/// The guarded file downloader. Overridden in tests.
final Provider<MoodleFileDownloader> moodleFileDownloaderProvider =
    Provider<MoodleFileDownloader>(
      (Ref ref) =>
          MoodleFileDownloaderImpl(profile: ref.watch(moodleProfileProvider)),
    );

/// Injectable clock so the 24-hour policy is testable.
final Provider<Clock> moodleClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// Coordinates personal Moodle operations with token/cache removal.
final Provider<SessionGuard<int>> moodleSessionGuardProvider =
    Provider<SessionGuard<int>>((Ref ref) => SessionGuard<int>());

/// The single Moodle facade. Owns the token and the cache.
final Provider<MoodleRepository> moodleRepositoryProvider =
    Provider<MoodleRepository>(
      (Ref ref) => MoodleRepositoryImpl(
        apiClient: ref.watch(moodleApiClientProvider),
        tokenStore: ref.watch(moodleTokenStoreProvider),
        cacheStore: ref.watch(moodleCacheStoreProvider),
        fileDownloader: ref.watch(moodleFileDownloaderProvider),
        clock: ref.watch(moodleClockProvider),
        sessionGuard: ref.watch(moodleSessionGuardProvider),
      ),
    );

/// Advances whenever the Moodle connection changes.
///
/// Every provider holding course, assignment, grade or announcement data
/// watches this, so disconnecting drops all of it from memory in one step.
///
/// Without it `moodleCourseDetailProvider` — a family provider, and not
/// `autoDispose` — kept each opened course's bundle, `gradeText` included,
/// alive across `disconnect()`. Connecting a second account on the same
/// device and opening the same course showed the FIRST account's grades. The
/// encrypted cache on disk was always wiped correctly; what survived was the
/// copy in Riverpod's own state.
///
/// Modelled on `mailSessionGenerationProvider`: bumping a counter the data
/// providers watch avoids having the account controller invalidate one of its
/// own dependants, which Riverpod correctly rejects as a cycle.
class MoodleSessionGeneration extends Notifier<int> {
  @override
  int build() => 0;

  void advance() => state++;
}

final NotifierProvider<MoodleSessionGeneration, int>
moodleSessionGenerationProvider =
    NotifierProvider<MoodleSessionGeneration, int>(MoodleSessionGeneration.new);
