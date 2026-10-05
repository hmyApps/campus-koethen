// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/documents/app_document.dart';
import '../data/nextcloud_dav_gateway.dart';
import '../data/nextcloud_public_link_sharer.dart';
import '../data/nextcloud_upload_picker.dart';
import '../data/secure_nextcloud_credential_store.dart';
import '../data/secure_nextcloud_favourite_store.dart';
import '../domain/nextcloud_account.dart';
import '../domain/nextcloud_entry.dart';
import '../domain/nextcloud_failure.dart';
import '../domain/nextcloud_favourite_store.dart';
import '../domain/nextcloud_gateway.dart';
import '../domain/nextcloud_profile.dart';

final Provider<NextcloudProfile> nextcloudProfileProvider =
    Provider<NextcloudProfile>((Ref ref) => const NextcloudProfile());

final Provider<NextcloudCredentialStore> nextcloudCredentialStoreProvider =
    Provider<NextcloudCredentialStore>(
      (Ref ref) => SecureNextcloudCredentialStore(),
    );

final Provider<NextcloudFavouriteStore> nextcloudFavouriteStoreProvider =
    Provider<NextcloudFavouriteStore>(
      (Ref ref) => SecureNextcloudFavouriteStore(),
    );

final Provider<NextcloudGateway> nextcloudGatewayProvider =
    Provider<NextcloudGateway>(
      (Ref ref) =>
          NextcloudDavGateway(profile: ref.watch(nextcloudProfileProvider)),
    );

final Provider<NextcloudUploadPicker> nextcloudUploadPickerProvider =
    Provider<NextcloudUploadPicker>(
      (Ref ref) => const SystemNextcloudUploadPicker(),
    );

final Provider<NextcloudPublicLinkSharer> nextcloudPublicLinkSharerProvider =
    Provider<NextcloudPublicLinkSharer>(
      (Ref ref) => const SystemNextcloudPublicLinkSharer(),
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

  Future<AppDocument> download(
    NextcloudEntry entry, {
    NextcloudDownloadProgress? onProgress,
    Future<void>? canceled,
  }) async {
    final int sessionGeneration = _ref.read(nextcloudSessionGenerationProvider);
    final NextcloudCredential? credential = await _ref
        .read(nextcloudCredentialStoreProvider)
        .read();
    if (credential == null) {
      throw const NextcloudFailure(NextcloudFailureKind.notConnected);
    }
    final AppDocument document = await _ref
        .read(nextcloudGatewayProvider)
        .downloadFile(
          credential,
          entry,
          onProgress: onProgress,
          canceled: canceled,
        );
    if (_ref.read(nextcloudSessionGenerationProvider) != sessionGeneration) {
      throw const NextcloudFailure(NextcloudFailureKind.notConnected);
    }
    return document;
  }

  Future<void> upload(
    String directoryPath,
    NextcloudUploadFile file, {
    NextcloudUploadProgress? onProgress,
    Future<void>? canceled,
  }) async {
    final (int generation, NextcloudCredential credential) = await _session();
    await _ref
        .read(nextcloudGatewayProvider)
        .uploadFile(
          credential,
          directoryPath: directoryPath,
          file: file,
          onProgress: onProgress,
          canceled: canceled,
        );
    _ensureCurrent(generation);
  }

  Future<void> delete(NextcloudEntry entry) async {
    final (int generation, NextcloudCredential credential) = await _session();
    await _ref.read(nextcloudGatewayProvider).deleteEntry(credential, entry);
    _ensureCurrent(generation);
  }

  Future<Uri> createPublicShare(NextcloudEntry entry) async {
    final (int generation, NextcloudCredential credential) = await _session();
    final Uri result = await _ref
        .read(nextcloudGatewayProvider)
        .createPublicShare(credential, entry);
    _ensureCurrent(generation);
    return result;
  }

  Future<(int, NextcloudCredential)> _session() async {
    final int generation = _ref.read(nextcloudSessionGenerationProvider);
    final NextcloudCredential? credential = await _ref
        .read(nextcloudCredentialStoreProvider)
        .read();
    if (credential == null) {
      throw const NextcloudFailure(NextcloudFailureKind.notConnected);
    }
    return (generation, credential);
  }

  void _ensureCurrent(int generation) {
    if (_ref.read(nextcloudSessionGenerationProvider) != generation) {
      throw const NextcloudFailure(NextcloudFailureKind.notConnected);
    }
  }
}

final Provider<NextcloudFileService> nextcloudFileServiceProvider =
    Provider<NextcloudFileService>((Ref ref) => NextcloudFileService(ref));
