// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/documents/app_document.dart';
import '../data/nextcloud_dav_gateway.dart';
import '../data/secure_nextcloud_credential_store.dart';
import '../domain/nextcloud_account.dart';
import '../domain/nextcloud_entry.dart';
import '../domain/nextcloud_failure.dart';
import '../domain/nextcloud_gateway.dart';
import '../domain/nextcloud_profile.dart';

final Provider<NextcloudProfile> nextcloudProfileProvider =
    Provider<NextcloudProfile>((Ref ref) => const NextcloudProfile());

final Provider<NextcloudCredentialStore> nextcloudCredentialStoreProvider =
    Provider<NextcloudCredentialStore>(
      (Ref ref) => SecureNextcloudCredentialStore(),
    );

final Provider<NextcloudGateway> nextcloudGatewayProvider =
    Provider<NextcloudGateway>(
      (Ref ref) =>
          NextcloudDavGateway(profile: ref.watch(nextcloudProfileProvider)),
    );

class NextcloudSessionGeneration extends Notifier<int> {
  @override
  int build() => 0;

  void advance() => state++;
}

final NotifierProvider<NextcloudSessionGeneration, int>
nextcloudSessionGenerationProvider =
    NotifierProvider<NextcloudSessionGeneration, int>(
      NextcloudSessionGeneration.new,
    );

final nextcloudFolderProvider = FutureProvider.autoDispose
    .family<List<NextcloudEntry>, String>((Ref ref, String path) async {
      ref.watch(nextcloudSessionGenerationProvider);
      final NextcloudCredential? credential = await ref
          .watch(nextcloudCredentialStoreProvider)
          .read();
      if (credential == null) {
        throw const NextcloudFailure(NextcloudFailureKind.notConnected);
      }
      return ref.watch(nextcloudGatewayProvider).listFolder(credential, path);
    });

class NextcloudFileService {
  const NextcloudFileService(this._ref);

  final Ref _ref;

  Future<AppDocument> download(NextcloudEntry entry) async {
    final int sessionGeneration = _ref.read(nextcloudSessionGenerationProvider);
    final NextcloudCredential? credential = await _ref
        .read(nextcloudCredentialStoreProvider)
        .read();
    if (credential == null) {
      throw const NextcloudFailure(NextcloudFailureKind.notConnected);
    }
    final AppDocument document = await _ref
        .read(nextcloudGatewayProvider)
        .downloadFile(credential, entry);
    if (_ref.read(nextcloudSessionGenerationProvider) != sessionGeneration) {
      throw const NextcloudFailure(NextcloudFailureKind.notConnected);
    }
    return document;
  }
}

final Provider<NextcloudFileService> nextcloudFileServiceProvider =
    Provider<NextcloudFileService>((Ref ref) => NextcloudFileService(ref));
