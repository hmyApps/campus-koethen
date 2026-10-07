// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:typed_data';

/// HAWKI's own AES-256-GCM wire format: `base64(iv)|base64(tag)|base64(ciphertext)`.
///
/// Matches `SymmetricCryptoValue` in HAWKI's frontend (`resources/js/kernel/
/// encryption/symmetric.ts`) and the backend's `AsSymmetricCryptoValueCast`
/// field-for-field — this is not a Campus Köthen invention, and the field
/// order is load-bearing: swapping `tag`/`ciphertext` here would make every
/// value this app writes unreadable by the real HAWKI, and vice versa.
class SymmetricCryptoValue {
  const SymmetricCryptoValue({
    required this.iv,
    required this.tag,
    required this.ciphertext,
  });

  /// Parses the pipe-delimited `iv|tag|ciphertext` wire format, as stored in
  /// `user_keychain_values.value` and other HAWKI-encrypted columns.
  factory SymmetricCryptoValue.parse(String wire) {
    final List<String> parts = wire.split('|');
    if (parts.length != 3) {
      throw const FormatException(
        'Invalid HAWKI symmetric crypto value: expected 3 pipe-delimited '
        'base64 segments (iv|tag|ciphertext)',
      );
    }
    return SymmetricCryptoValue(
      iv: base64Decode(parts[0]),
      tag: base64Decode(parts[1]),
      ciphertext: base64Decode(parts[2]),
    );
  }

  /// 12-byte AES-GCM initialization vector.
  final Uint8List iv;

  /// 16-byte AES-GCM authentication tag.
  final Uint8List tag;

  /// Ciphertext bytes with the authentication tag already sliced off.
  final Uint8List ciphertext;

  String serialize() =>
      '${base64Encode(iv)}|${base64Encode(tag)}|${base64Encode(ciphertext)}';
}
