// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:file_selector/file_selector.dart';

import '../../../core/documents/app_document.dart';
import '../domain/nextcloud_gateway.dart';

abstract interface class NextcloudUploadPicker {
  Future<NextcloudUploadFile?> pickFile();
}

class SystemNextcloudUploadPicker implements NextcloudUploadPicker {
  const SystemNextcloudUploadPicker();

  @override
  Future<NextcloudUploadFile?> pickFile() async {
    final XFile? selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[],
    );
    if (selected == null) return null;
    final int length = await selected.length();
    return NextcloudUploadFile(
      filename: selected.name,
      mediaType: mediaTypeFor(selected.name, declared: selected.mimeType),
      length: length,
      openRead: selected.openRead,
    );
  }
}
