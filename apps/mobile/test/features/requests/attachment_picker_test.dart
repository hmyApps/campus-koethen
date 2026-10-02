// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:campus_koethen/features/requests/data/attachment_picker.dart';
import 'package:campus_koethen/features/requests/domain/application_files.dart';
import 'package:campus_koethen/features/requests/domain/attachment_store.dart';
import 'package:campus_koethen/features/requests/domain/request_drafts.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryAttachmentStore implements AttachmentStore {
  @override
  Future<void> delete(RequestAttachment attachment) async {}

  @override
  Future<void> deleteAll(Iterable<RequestAttachment> attachments) async {}

  @override
  Future<RequestAttachment?> put(String fileName, Uint8List bytes) async =>
      RequestAttachment(
        fileName: fileName,
        path: 'attachment:test',
        sizeBytes: bytes.length,
      );

  @override
  Future<Uint8List?> read(RequestAttachment attachment) async => null;

  @override
  Future<bool> wipeEverything() async => true;
}

class _SizedXFile extends XFile {
  _SizedXFile({required this.reportedLength, required this.bytes})
    : super('oversized.pdf');

  final int reportedLength;
  final Uint8List bytes;
  bool wasRead = false;

  @override
  Future<int> length() async => reportedLength;

  @override
  Future<Uint8List> readAsBytes() async {
    wasRead = true;
    return bytes;
  }
}

void main() {
  test(
    'keeps Android extensions and supplies the iOS PDF identifier',
    () async {
      List<XTypeGroup>? capturedGroups;
      final SecureAttachmentPicker picker = SecureAttachmentPicker(
        _MemoryAttachmentStore(),
        (List<XTypeGroup> acceptedTypeGroups) async {
          capturedGroups = acceptedTypeGroups;
          return null;
        },
      );

      expect(
        await picker.pickFor(ApplicationFileSlot.financeRequest),
        isA<PickCancelled>(),
      );
      expect(capturedGroups, hasLength(1));
      expect(capturedGroups!.single.extensions, <String>['pdf']);
      expect(capturedGroups!.single.uniformTypeIdentifiers, <String>[
        'com.adobe.pdf',
      ]);
    },
  );

  test('supplies all supported iOS identifiers for the student card', () async {
    List<XTypeGroup>? capturedGroups;
    final SecureAttachmentPicker picker = SecureAttachmentPicker(
      _MemoryAttachmentStore(),
      (List<XTypeGroup> acceptedTypeGroups) async {
        capturedGroups = acceptedTypeGroups;
        return null;
      },
    );

    await picker.pickFor(ApplicationFileSlot.studentCard);

    expect(
      capturedGroups!.single.extensions,
      containsAll(<String>['pdf', 'png', 'jpg', 'jpeg']),
    );
    expect(capturedGroups!.single.uniformTypeIdentifiers, <String>[
      'com.adobe.pdf',
      'public.png',
      'public.jpeg',
    ]);
  });

  test('turns a platform picker exception into a typed failure', () async {
    final SecureAttachmentPicker picker = SecureAttachmentPicker(
      _MemoryAttachmentStore(),
      (List<XTypeGroup> acceptedTypeGroups) =>
          throw ArgumentError('platform rejected the type group'),
    );

    expect(
      await picker.pickFor(ApplicationFileSlot.financeRequest),
      isA<PickFailed>(),
    );
  });

  test('rejects an oversized file before materializing its bytes', () async {
    final _SizedXFile file = _SizedXFile(
      reportedLength: ApplicationFileLimits.maxFileBytes + 1,
      bytes: Uint8List(1),
    );
    final SecureAttachmentPicker picker = SecureAttachmentPicker(
      _MemoryAttachmentStore(),
      (_) async => file,
    );

    expect(
      await picker.pickFor(ApplicationFileSlot.financeRequest),
      isA<PickTooLarge>(),
    );
    expect(file.wasRead, isFalse);
  });
}
