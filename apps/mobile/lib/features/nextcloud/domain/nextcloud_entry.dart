// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

@immutable
class NextcloudEntry {
  const NextcloudEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.sizeBytes,
    this.mediaType,
    this.modifiedAt,
  });

  /// Normalized path relative to the account's DAV root, starting with `/`.
  final String path;
  final String name;
  final bool isDirectory;
  final int? sizeBytes;
  final String? mediaType;
  final DateTime? modifiedAt;
}
