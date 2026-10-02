// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/documents/app_document.dart';
import '../domain/mail_message.dart';

/// One file picked for a compose draft, not yet turned into a domain
/// `OutgoingAttachment`.
///
/// Only a filename, a best-effort media type and a size are known right
/// after picking. The bytes are read fresh at send time via [readBytes], so
/// a file that vanished or became unreadable in between surfaces as a
/// distinct, typed failure instead of silently sending stale content.
abstract interface class PickedMailFile {
  String get filename;

  /// e.g. `image/png`, `application/pdf`. Guessed from the filename when the
  /// platform does not supply one.
  String get mediaType;

  /// Best-effort size for display. Null when it could not be determined —
  /// never throws.
  Future<int?> sizeBytes();

  /// Reads the file's current content. May throw if the file is gone or
  /// otherwise unreadable; the caller must convert that into a typed
  /// `MailFailure` rather than let the raw error escape.
  Future<Uint8List> readBytes({
    int maxBytes = MailAttachmentLimits.maxFileBytes,
  });
}

class _XFilePickedMailFile implements PickedMailFile {
  _XFilePickedMailFile(this._file);

  final XFile _file;

  @override
  String get filename => _file.name;

  @override
  String get mediaType => mediaTypeFor(_file.name, declared: _file.mimeType);

  @override
  Future<int?> sizeBytes() async {
    try {
      return await _file.length();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List> readBytes({
    int maxBytes = MailAttachmentLimits.maxFileBytes,
  }) async {
    final BytesBuilder result = BytesBuilder(copy: false);
    int total = 0;
    await for (final Uint8List chunk in _file.openRead()) {
      total += chunk.length;
      if (total > maxBytes) {
        throw const MailAttachmentLimitException(
          MailAttachmentBudgetIssue.fileTooLarge,
        );
      }
      result.add(chunk);
    }
    return result.takeBytes();
  }
}

/// What a pick attempt ended in.
sealed class MailFilePickResult {
  const MailFilePickResult();
}

/// One or more files were chosen.
class MailFilesPicked extends MailFilePickResult {
  const MailFilesPicked(this.files);

  final List<PickedMailFile> files;
}

/// The user closed the dialog without choosing anything. The draft — and any
/// already-picked attachments — must stay exactly as it was.
class MailFilePickCancelled extends MailFilePickResult {
  const MailFilePickCancelled();
}

/// Port: lets the user pick one or more files of any type to attach to a
/// message being composed.
///
/// Wrapped behind a port (rather than the compose screen calling
/// `file_selector` directly) so widget tests never open a real OS dialog —
/// see [mailAttachmentPickerProvider] and its test override, analogous to how
/// `AttachmentPicker` (`features/requests/data/attachment_picker.dart`) is
/// already wrapped for the same reason.
abstract interface class MailAttachmentPicker {
  Future<MailFilePickResult> pickFiles();
}

/// Opens the OS "open file(s)" dialog with no type restriction, since the
/// compose screen accepts any regular file.
class SystemMailAttachmentPicker implements MailAttachmentPicker {
  const SystemMailAttachmentPicker();

  @override
  Future<MailFilePickResult> pickFiles() async {
    final List<XFile> chosen = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[],
    );
    if (chosen.isEmpty) return const MailFilePickCancelled();
    return MailFilesPicked(
      chosen
          .map((XFile file) => _XFilePickedMailFile(file))
          .toList(growable: false),
    );
  }
}

/// Overridable so tests never open a platform dialog.
final Provider<MailAttachmentPicker> mailAttachmentPickerProvider =
    Provider<MailAttachmentPicker>(
      (Ref ref) => const SystemMailAttachmentPicker(),
    );
