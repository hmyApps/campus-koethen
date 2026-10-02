// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/application_files.dart';
import '../domain/attachment_store.dart';
import '../domain/request_drafts.dart';
import 'encrypted_attachment_store.dart';

/// What picking a file ended in.
sealed class PickResult {
  const PickResult();
}

class PickedFile extends PickResult {
  const PickedFile(this.attachment);

  final RequestAttachment attachment;
}

/// The user closed the dialog without choosing.
class PickCancelled extends PickResult {
  const PickCancelled();
}

/// The file does not belong in this slot.
class PickWrongType extends PickResult {
  const PickWrongType();
}

/// Over the endpoint's 25 MB per file.
class PickTooLarge extends PickResult {
  const PickTooLarge();
}

/// The file could not be read, or could not be stored.
class PickFailed extends PickResult {
  const PickFailed();
}

/// Port: lets the user pick one file for one slot.
///
/// Per slot rather than a free multi-select: the endpoint expects exactly four
/// named fields with different accepted types, and a generic "add files" button
/// would let a student attach something that is then silently not sent.
abstract interface class AttachmentPicker {
  Future<PickResult> pickFor(
    ApplicationFileSlot slot, {
    int currentTotalBytes = 0,
  });
}

typedef AttachmentFileOpener =
    Future<XFile?> Function(List<XTypeGroup> acceptedTypeGroups);

Future<XFile?> _openAttachmentFile(List<XTypeGroup> acceptedTypeGroups) =>
    openFile(acceptedTypeGroups: acceptedTypeGroups);

/// Picks a file and hands its bytes to the encrypted store.
///
/// Type and size are checked **before** anything is stored, so a file that
/// cannot be sent never reaches the device's storage in the first place.
class SecureAttachmentPicker implements AttachmentPicker {
  const SecureAttachmentPicker(
    this._store, [
    this._fileOpener = _openAttachmentFile,
  ]);

  final AttachmentStore _store;
  final AttachmentFileOpener _fileOpener;

  @override
  Future<PickResult> pickFor(
    ApplicationFileSlot slot, {
    int currentTotalBytes = 0,
  }) async {
    try {
      final XFile? chosen = await _fileOpener(<XTypeGroup>[
        XTypeGroup(
          label: slot.field,
          // Android filters by extension. iOS ignores extensions and
          // requires UTIs instead, so both representations must stay here.
          extensions: slot.extensions.toList(growable: false),
          uniformTypeIdentifiers: switch (slot) {
            ApplicationFileSlot.studentCard => const <String>[
              'com.adobe.pdf',
              'public.png',
              'public.jpeg',
            ],
            _ => const <String>['com.adobe.pdf'],
          },
        ),
      ]);
      if (chosen == null) return const PickCancelled();

      // The dialog's own filter is a convenience, not a guarantee — on both
      // platforms the user can still end up with something else.
      if (!slot.accepts(chosen.name)) return const PickWrongType();

      // XFile.length() reads metadata, not contents. This guard must happen
      // before readAsBytes/openRead so a wildly oversized selection cannot
      // allocate its way to the error message.
      final int declaredLength = await chosen.length();
      if (!slot.acceptsSize(declaredLength) ||
          !ApplicationFileLimits.acceptsTotal(
            currentTotalBytes + declaredLength,
          )) {
        return const PickTooLarge();
      }

      if (_store case final StreamingAttachmentStore streaming) {
        final RequestAttachment? stored = await streaming.putStream(
          chosen.name,
          declaredLength,
          chosen.openRead(),
        );
        return stored == null ? const PickFailed() : PickedFile(stored);
      }

      final Uint8List bytes = await chosen.readAsBytes();
      if (!slot.acceptsSize(bytes.length) ||
          bytes.length != declaredLength ||
          !ApplicationFileLimits.acceptsTotal(
            currentTotalBytes + bytes.length,
          )) {
        return const PickTooLarge();
      }
      final RequestAttachment? stored = await _store.put(chosen.name, bytes);
      return stored == null ? const PickFailed() : PickedFile(stored);
    } on AttachmentLimitExceeded {
      return const PickTooLarge();
    } catch (_) {
      return const PickFailed();
    }
  }
}

/// Overridable so tests never open a platform dialog.
final Provider<AttachmentStore> attachmentStoreProvider =
    Provider<AttachmentStore>((Ref ref) => EncryptedAttachmentStore());

final Provider<AttachmentPicker> attachmentPickerProvider =
    Provider<AttachmentPicker>(
      (Ref ref) => SecureAttachmentPicker(ref.watch(attachmentStoreProvider)),
    );
