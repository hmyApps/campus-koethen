// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import '../../../core/documents/app_document.dart';
import 'nextcloud_account.dart';
import 'nextcloud_entry.dart';

typedef NextcloudDownloadProgress = void Function(int received, int? total);
typedef NextcloudUploadProgress = void Function(int sent, int total);

class NextcloudUploadFile {
  const NextcloudUploadFile({
    required this.filename,
    required this.mediaType,
    required this.length,
    required this.openRead,
  });

  final String filename;
  final String mediaType;
  final int length;
  final Stream<Uint8List> Function() openRead;
}

class NextcloudLoginStart {
  const NextcloudLoginStart({
    required this.loginUri,
    required this.pollUri,
    required this.pollToken,
  });

  final Uri loginUri;
  final Uri pollUri;
  final String pollToken;

  @override
  String toString() => 'NextcloudLoginStart(«redacted»)';
}

abstract interface class NextcloudGateway {
  Future<NextcloudLoginStart> startLogin();

  Future<NextcloudCredential> completeLogin(
    NextcloudLoginStart start, {
    required Future<void> canceled,
  });

  Future<void> revoke(NextcloudCredential credential);

  Future<List<NextcloudEntry>> listFolder(
    NextcloudCredential credential,
    String path,
  );

  Future<AppDocument> downloadFile(
    NextcloudCredential credential,
    NextcloudEntry entry, {
    NextcloudDownloadProgress? onProgress,
    Future<void>? canceled,
  });

  Future<void> uploadFile(
    NextcloudCredential credential, {
    required String directoryPath,
    required NextcloudUploadFile file,
    NextcloudUploadProgress? onProgress,
    Future<void>? canceled,
  });

  Future<void> deleteEntry(
    NextcloudCredential credential,
    NextcloudEntry entry,
  );

  Future<Uri> createPublicShare(
    NextcloudCredential credential,
    NextcloudEntry entry,
  );
}
