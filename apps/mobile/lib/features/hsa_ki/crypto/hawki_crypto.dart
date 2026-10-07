// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'symmetric_crypto_value.dart';

/// Thrown when AES-GCM authentication fails: a wrong key (e.g. a mistyped
/// chat-history passkey) or tampered/corrupted ciphertext. GCM's tag check
/// IS the correctness check — this is never thrown for "decrypted fine but
/// the content was nonsense".
class HawkiCryptoException implements Exception {
  const HawkiCryptoException(this.message);

  final String message;

  @override
  String toString() => 'HawkiCryptoException: $message';
}

/// Byte-exact reimplementation of HAWKI's own WebCrypto-based frontend
/// cryptography, confirmed 2026-10-07 against the HAWKI source
/// (`resources/js/kernel/encryption/{utils,symmetric}.ts`) and backend
/// documentation (`_documentation/500-Backend/800-Encryption-and-Security/`).
///
/// Every parameter here — iteration count, hash, salt construction, IV/tag
/// length — must match exactly, or decryption of real, already-encrypted
/// HAWKI data (an existing user's real chat history) silently fails rather
/// than producing a classified, explainable error. Nothing here is guessed;
/// each constant is cited against the real source in the doc comments below.
abstract final class HawkiCrypto {
  static const int _pbkdf2Iterations = 100000;
  static const int _ivLength = 12;
  static const int _macSizeBits = 128; // 16-byte tag

  /// Derives an AES-256-GCM key from [passphrase] via PBKDF2-HMAC-SHA256,
  /// 100k iterations — matches `deriveKey()` in HAWKI's `encryption/utils.ts`
  /// exactly.
  ///
  /// [label] is mixed into the salt ahead of [serverSalt] so the same
  /// passphrase yields a different key per purpose; HAWKI uses
  /// `'keychain_encryptor'` to derive the keychain-unlock key
  /// (`keychainHandle.ts`) — pass the same label here for that purpose.
  ///
  /// [serverSalt] is the raw salt string as delivered by HAWKI's connection
  /// bootstrap payload (`crypto_salt`). It is treated as a sequence of
  /// Latin-1 code units, NOT base64-decoded — matching `loadServerSalt()`
  /// exactly, which maps each character to its code point directly.
  static Uint8List deriveKey({
    required String passphrase,
    required String label,
    required String serverSalt,
  }) {
    final Uint8List labelBytes = Uint8List.fromList(utf8.encode(label));
    final Uint8List saltBytes = Uint8List.fromList(serverSalt.codeUnits);
    final Uint8List combinedSalt =
        Uint8List(labelBytes.length + saltBytes.length)
          ..setRange(0, labelBytes.length, labelBytes)
          ..setRange(
            labelBytes.length,
            labelBytes.length + saltBytes.length,
            saltBytes,
          );

    final PBKDF2KeyDerivator derivator =
        PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
          ..init(Pbkdf2Parameters(combinedSalt, _pbkdf2Iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Encrypts [plaintext] with [key] (a 32-byte AES-256 key, e.g. from
  /// [deriveKey]), generating a fresh random 12-byte IV per call — matches
  /// `encryptArrayBufferSymmetric()` in HAWKI's `encryption/symmetric.ts`.
  static SymmetricCryptoValue encrypt(Uint8List plaintext, Uint8List key) {
    final Uint8List iv = _randomBytes(_ivLength);
    final GCMBlockCipher cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _macSizeBits, iv, Uint8List(0)),
      );
    // WebCrypto's AES-GCM (and pointycastle's) both return
    // `ciphertext || tag` concatenated; HAWKI slices them apart for the wire
    // format, so we do the same.
    final Uint8List output = cipher.process(plaintext);
    final int tagStart = output.length - 16;
    return SymmetricCryptoValue(
      iv: iv,
      tag: output.sublist(tagStart),
      ciphertext: output.sublist(0, tagStart),
    );
  }

  /// Decrypts [value] with [key]. Throws [HawkiCryptoException] — never
  /// returns garbage — if the key is wrong or the ciphertext was tampered
  /// with.
  static Uint8List decrypt(SymmetricCryptoValue value, Uint8List key) {
    final Uint8List combined =
        Uint8List(value.ciphertext.length + value.tag.length)
          ..setRange(0, value.ciphertext.length, value.ciphertext)
          ..setRange(
            value.ciphertext.length,
            value.ciphertext.length + value.tag.length,
            value.tag,
          );
    final GCMBlockCipher cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          _macSizeBits,
          value.iv,
          Uint8List(0),
        ),
      );
    try {
      return cipher.process(combined);
    } on InvalidCipherTextException catch (e) {
      throw HawkiCryptoException(e.message);
    }
  }

  static Uint8List _randomBytes(int length) {
    final Random random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
