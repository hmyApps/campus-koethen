// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/cache/encrypted_box.dart';
import '../domain/application_files.dart';
import '../domain/attachment_store.dart';
import '../domain/request_drafts.dart';

/// Keeps draft attachments encrypted at rest.
///
/// The first version copied picked files into the app's documents directory as
/// plaintext. For a grocery list that would be fine; for a **student card** it
/// is not — the copy sits there for as long as the draft does, readable by
/// anything with access to the app's sandbox, and survives until someone
/// remembers to clean it up.
///
/// Here the bytes are base64-encoded into the app's encrypted box, whose AES
/// key lives only in the keychain/keystore. They come back into memory when a
/// submission needs them and are written to disk in the clear at no point —
/// so there is no temporary plaintext file for a crash to leave behind, and
/// nothing to forget to delete in a `finally`.
///
/// The user's **original file is never touched**: this store only ever owns
/// its own copy.
class EncryptedAttachmentStore
    implements AttachmentStore, StreamingAttachmentStore {
  EncryptedAttachmentStore({EncryptedBox? box, Random? random})
    : _box =
          box ??
          EncryptedBox(
            boxName: 'campus_request_files_v1',
            keyStorageKey: 'campus_request_files_key_v1',
          ),
      _random = random ?? Random.secure();

  static const String _prefix = 'attachment:';
  static const int chunkBytes = 256 * 1024;
  static const int _formatVersion = 2;

  @override
  Future<bool> wipeEverything() async {
    final EncryptedBoxWipeResult wiped = await _box.wipeChecked();
    return wiped.isComplete;
  }

  final EncryptedBox _box;
  final Random _random;

  @override
  Future<RequestAttachment?> put(String fileName, Uint8List bytes) =>
      putStream(fileName, bytes.length, Stream<List<int>>.value(bytes));

  @override
  Future<RequestAttachment?> putStream(
    String fileName,
    int expectedLength,
    Stream<List<int>> bytes,
  ) async {
    if (!ApplicationFileLimits.acceptsFile(expectedLength)) {
      throw const AttachmentLimitExceeded();
    }
    final String id = '$_prefix${_token()}';
    final Uint8List buffer = Uint8List(chunkBytes);
    int buffered = 0;
    int total = 0;
    int chunkCount = 0;

    Future<bool> flush() async {
      if (buffered == 0) return true;
      final String encoded = base64Encode(
        Uint8List.sublistView(buffer, 0, buffered),
      );
      final bool stored = await _box.writeChecked(
        _chunkKey(id, chunkCount),
        encoded,
      );
      if (!stored) return false;
      chunkCount++;
      buffered = 0;
      return true;
    }

    try {
      await for (final List<int> incoming in bytes) {
        total += incoming.length;
        if (total > expectedLength ||
            !ApplicationFileLimits.acceptsFile(total)) {
          throw const AttachmentLimitExceeded();
        }
        int offset = 0;
        while (offset < incoming.length) {
          final int take = (chunkBytes - buffered).clamp(
            0,
            incoming.length - offset,
          );
          buffer.setRange(buffered, buffered + take, incoming, offset);
          buffered += take;
          offset += take;
          if (buffered == chunkBytes && !await flush()) {
            throw const _AttachmentWriteFailed();
          }
        }
      }
      if (total != expectedLength) throw const AttachmentLimitExceeded();
      if (!await flush()) throw const _AttachmentWriteFailed();
      final String metadata = jsonEncode(<String, int>{
        'version': _formatVersion,
        'size': total,
        'chunks': chunkCount,
      });
      if (!await _box.writeChecked(id, metadata)) {
        throw const _AttachmentWriteFailed();
      }
      return RequestAttachment(fileName: fileName, path: id, sizeBytes: total);
    } on AttachmentLimitExceeded {
      await _deleteOwnedKeys(id);
      rethrow;
    } catch (_) {
      await _deleteOwnedKeys(id);
      return null;
    }
  }

  @override
  Future<Uint8List?> read(RequestAttachment attachment) async {
    final StoredAttachmentStream? source = await openRead(attachment);
    if (source == null) return null;
    final BytesBuilder result = BytesBuilder(copy: false);
    try {
      await for (final List<int> chunk in source.open()) {
        result.add(chunk);
      }
      final Uint8List bytes = result.takeBytes();
      return bytes.length == source.length ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StoredAttachmentStream?> openRead(RequestAttachment attachment) async {
    final String? raw = await _box.read(attachment.path);
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map &&
          decoded['version'] == _formatVersion &&
          decoded['size'] is int &&
          decoded['chunks'] is int) {
        final int size = decoded['size'] as int;
        final int chunks = decoded['chunks'] as int;
        if (!ApplicationFileLimits.acceptsFile(size) ||
            chunks < 0 ||
            chunks > (ApplicationFileLimits.maxFileBytes ~/ chunkBytes) + 1 ||
            (attachment.sizeBytes != null && attachment.sizeBytes != size)) {
          return null;
        }
        return StoredAttachmentStream(
          length: size,
          open: () => _readChunks(attachment.path, chunks, size),
        );
      }
    } catch (_) {
      // A v1 entry is raw base64 rather than JSON; handled below.
    }

    // Backward-compatible, one-read path for drafts created before the
    // chunked format. Every new write uses v2.
    try {
      final Uint8List legacy = base64Decode(raw);
      if (!ApplicationFileLimits.acceptsFile(legacy.length)) return null;
      return StoredAttachmentStream(
        length: legacy.length,
        open: () => Stream<List<int>>.value(legacy),
      );
    } catch (_) {
      return null;
    }
  }

  Stream<List<int>> _readChunks(
    String id,
    int chunkCount,
    int expectedLength,
  ) async* {
    int total = 0;
    for (int index = 0; index < chunkCount; index++) {
      final String? encoded = await _box.read(_chunkKey(id, index));
      if (encoded == null) throw const FormatException('missing chunk');
      final Uint8List chunk = base64Decode(encoded);
      total += chunk.length;
      if (chunk.isEmpty ||
          chunk.length > chunkBytes ||
          total > expectedLength) {
        throw const FormatException('invalid chunk');
      }
      yield chunk;
    }
    if (total != expectedLength) {
      throw const FormatException('attachment length mismatch');
    }
  }

  @override
  Future<void> delete(RequestAttachment attachment) =>
      _deleteOwnedKeys(attachment.path);

  @override
  Future<void> deleteAll(Iterable<RequestAttachment> attachments) async {
    for (final RequestAttachment attachment in attachments) {
      await delete(attachment);
    }
  }

  Future<void> _deleteOwnedKeys(String id) async {
    final List<String> owned = (await _box.keys())
        .where((String key) => key == id || key.startsWith('$id.chunk.'))
        .toList(growable: false);
    for (final String key in owned) {
      await _box.delete(key);
    }
  }

  static String _chunkKey(String id, int index) => '$id.chunk.$index';

  String _token() {
    final List<int> bytes = List<int>.generate(
      16,
      (_) => _random.nextInt(256),
      growable: false,
    );
    return bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _AttachmentWriteFailed implements Exception {
  const _AttachmentWriteFailed();
}
