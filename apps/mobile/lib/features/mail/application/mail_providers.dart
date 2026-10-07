// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/enough_mail_gateway.dart';
import '../data/exchange_directory_gateway.dart';
import '../data/mail_cache.dart';
import '../data/mail_local_data_coordinator.dart';
import '../data/secure_mail_credential_store.dart';
import '../domain/hsa_mail_profile.dart';
import '../domain/mail_cache_store.dart';
import '../domain/mail_credential_store.dart';
import '../domain/mail_gateway.dart';
import '../domain/mail_directory_gateway.dart';

/// The pinned HSA connection profile.
final Provider<HsaMailProfile> hsaMailProfileProvider =
    Provider<HsaMailProfile>((Ref ref) => const HsaMailProfile());

/// Secure credential storage. Overridden with an in-memory fake in tests.
final Provider<MailCredentialStore> mailCredentialStoreProvider =
    Provider<MailCredentialStore>((Ref ref) => SecureMailCredentialStore());

/// The mail gateway (enough_mail behind an interface). Overridden in tests.
final Provider<MailGateway> mailGatewayProvider = Provider<MailGateway>(
  (Ref ref) => EnoughMailGateway(ref.watch(hsaMailProfileProvider)),
);

final Provider<MailDirectoryGateway> mailDirectoryGatewayProvider =
    Provider<MailDirectoryGateway>(
      (Ref ref) => ExchangeDirectoryGateway(ref.watch(hsaMailProfileProvider)),
    );

/// Last-resort UI boundary for a sign-in verification.
///
/// The concrete gateway applies tighter protocol timeouts and closes its
/// sockets. This outer limit protects the setup screen even if a future gateway
/// implementation accidentally returns a Future that never completes.
final Provider<Duration> mailSignInTimeoutProvider = Provider<Duration>(
  (Ref ref) => const Duration(seconds: 30),
);

/// Offline mail cache. Overridden in `main()` with the Hive-backed store and in
/// tests with an in-memory one; the default keeps widget tests off the disk.
final Provider<MailCacheStore> mailCacheStoreProvider =
    Provider<MailCacheStore>((Ref ref) => MemoryMailCache());

/// Persistent, non-personal marker used to finish an interrupted account wipe.
final Provider<MailWipeIntentStore> mailWipeIntentStoreProvider =
    Provider<MailWipeIntentStore>((Ref ref) => MemoryMailWipeIntentStore());

final Provider<MailLocalDataCoordinator> mailLocalDataCoordinatorProvider =
    Provider<MailLocalDataCoordinator>(
      (Ref ref) => MailLocalDataCoordinator(
        credentials: ref.watch(mailCredentialStoreProvider),
        cache: ref.watch(mailCacheStoreProvider),
        wipeIntent: ref.watch(mailWipeIntentStoreProvider),
      ),
    );

/// Whether mail is currently only cached for this session.
///
/// Reads through [mailCacheStoreProvider], so a test that swaps in a plain
/// memory cache still reports `false` — the degradation this reports is the
/// *unintended* one, not the deliberate test double.
final Provider<bool> mailCacheDegradedProvider = Provider<bool>((Ref ref) {
  ref.watch(mailSessionGenerationProvider);
  final MailCacheStore cache = ref.watch(mailCacheStoreProvider);
  return cache is MailCacheManager && cache.isMemoryOnly;
});

/// Advances before a local-data wipe so every mail-scoped provider drops its
/// in-memory state without requiring the account provider to invalidate one of
/// its own dependants (which Riverpod correctly rejects as a cycle).
class MailSessionGeneration extends Notifier<int> {
  @override
  int build() => 0;

  void advance() => state++;
}

final NotifierProvider<MailSessionGeneration, int>
mailSessionGenerationProvider = NotifierProvider<MailSessionGeneration, int>(
  MailSessionGeneration.new,
);
