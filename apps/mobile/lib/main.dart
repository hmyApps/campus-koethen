// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'app/campus_app.dart';
import 'core/cache/encrypted_box.dart';
import 'core/cache/cache_providers.dart';
import 'core/cache/content_cache.dart';
import 'core/cache/hive_content_cache.dart';
import 'core/prefs/key_value_store.dart';
import 'core/prefs/settings_controller.dart';
import 'features/mail/application/mail_providers.dart';
import 'features/mail/data/mail_cache.dart';
import 'features/mail/data/mail_local_data_coordinator.dart';
import 'features/mail/data/secure_mail_credential_store.dart';
import 'features/mail/domain/mail_credential_store.dart';
import 'features/grades/application/grades_providers.dart';
import 'features/student_service/application/student_service_providers.dart';
import 'features/document_wallet/application/document_wallet_controller.dart';

/// Entry point.
///
/// The API base URL comes exclusively from
/// `--dart-define=API_BASE_URL=…` (see `core/network/api_config.dart`).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every store fails soft: a broken cache or preferences backend degrades the
  // app to "network only", it never prevents the app from starting. None of
  // these three stores depends on another's result, so their I/O runs
  // concurrently instead of serially to shorten the delay before first frame.
  final secureStorage = EncryptedBox.deviceSecureStorage();
  final MailCredentialStore mailCredentials = SecureMailCredentialStore(
    secureStorage,
  );
  final MailCacheManager mailCache = MailCacheManager(
    encryptedBox: EncryptedBox(
      boxName: MailCacheManager.secureBoxName,
      keyStorageKey: MailCacheManager.keyStorageKey,
      storage: secureStorage,
    ),
  );
  final MailWipeIntentStore wipeIntent = SecureMailWipeIntentStore(
    secureStorage,
  );
  final MailLocalDataCoordinator mailLocalData = MailLocalDataCoordinator(
    credentials: mailCredentials,
    cache: mailCache,
    wipeIntent: wipeIntent,
  );

  final (KeyValueStore keyValueStore, ContentCache contentCache, _) = await (
    _openKeyValueStore(),
    HiveContentCache.open(),
    mailLocalData.initialize(),
  ).wait;

  runApp(
    ProviderScope(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(keyValueStore),
        contentCacheProvider.overrideWithValue(contentCache),
        mailCacheStoreProvider.overrideWithValue(mailCache),
        mailCredentialStoreProvider.overrideWithValue(mailCredentials),
        mailWipeIntentStoreProvider.overrideWithValue(wipeIntent),
        mailLocalDataCoordinatorProvider.overrideWithValue(mailLocalData),
        gradeLinkedPersonalDataWipersProvider.overrideWith((Ref ref) {
          return <GradeLinkedPersonalDataWiper>[
            () async {
              await ref
                  .read(studentServiceSessionGuardProvider)
                  .invalidateAndWait();
              await ref.read(studentServiceCacheStoreProvider).clear();
            },
            () async {
              await ref
                  .read(documentWalletSessionGuardProvider)
                  .invalidateAndWait();
              await ref.read(documentWalletStoreProvider).clear();
            },
          ];
        }),
      ],
      child: const CampusApp(),
    ),
  );
}

Future<KeyValueStore> _openKeyValueStore() async {
  try {
    return await SharedPreferencesStore.open();
  } catch (_) {
    return InMemoryKeyValueStore();
  }
}
