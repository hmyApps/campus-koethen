// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_koethen/features/hsa_ki/crypto/hawki_crypto.dart';
import 'package:campus_koethen/features/hsa_ki/crypto/symmetric_crypto_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SymmetricCryptoValue wire format', () {
    test('round-trips through serialize/parse', () {
      final SymmetricCryptoValue value = SymmetricCryptoValue(
        iv: Uint8List.fromList(List<int>.generate(12, (int i) => i)),
        tag: Uint8List.fromList(List<int>.generate(16, (int i) => i + 100)),
        ciphertext: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      );
      final SymmetricCryptoValue parsed = SymmetricCryptoValue.parse(
        value.serialize(),
      );
      expect(parsed.iv, value.iv);
      expect(parsed.tag, value.tag);
      expect(parsed.ciphertext, value.ciphertext);
    });

    test('serializes as iv|tag|ciphertext, each base64 — matching HAWKI\'s '
        'own SymmetricCryptoValue.toString() field order exactly', () {
      final SymmetricCryptoValue value = SymmetricCryptoValue(
        iv: Uint8List.fromList(<int>[1]),
        tag: Uint8List.fromList(<int>[2]),
        ciphertext: Uint8List.fromList(<int>[3]),
      );
      expect(
        value.serialize(),
        '${base64Encode(<int>[1])}|${base64Encode(<int>[2])}|${base64Encode(<int>[3])}',
      );
    });

    test('rejects a wire string without exactly 3 segments', () {
      expect(
        () => SymmetricCryptoValue.parse('onlyonesegment'),
        throwsFormatException,
      );
      expect(
        () => SymmetricCryptoValue.parse('a|b|c|d'),
        throwsFormatException,
      );
    });
  });

  group('HawkiCrypto.deriveKey', () {
    test('is deterministic for the same inputs', () {
      final Uint8List a = HawkiCrypto.deriveKey(
        passphrase: 'correct horse battery staple',
        label: 'keychain_encryptor',
        serverSalt: 'some-server-salt',
      );
      final Uint8List b = HawkiCrypto.deriveKey(
        passphrase: 'correct horse battery staple',
        label: 'keychain_encryptor',
        serverSalt: 'some-server-salt',
      );
      expect(a, b);
      expect(a, hasLength(32)); // AES-256 key
    });

    test('a different label yields a different key for the same passphrase '
        'and salt — this is the whole point of mixing the label in', () {
      final Uint8List keychainKey = HawkiCrypto.deriveKey(
        passphrase: 'pw',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      final Uint8List roomKey = HawkiCrypto.deriveKey(
        passphrase: 'pw',
        label: 'some-room-slug',
        serverSalt: 'salt',
      );
      expect(keychainKey, isNot(roomKey));
    });

    test('a different passphrase yields a different key', () {
      final Uint8List a = HawkiCrypto.deriveKey(
        passphrase: 'pw1',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      final Uint8List b = HawkiCrypto.deriveKey(
        passphrase: 'pw2',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      expect(a, isNot(b));
    });
  });

  group('HawkiCrypto.encrypt / decrypt', () {
    test('round-trips plaintext through encrypt then decrypt', () {
      final Uint8List key = HawkiCrypto.deriveKey(
        passphrase: 'my-passkey',
        label: 'keychain_encryptor',
        serverSalt: 'server-salt',
      );
      final Uint8List plaintext = Uint8List.fromList(
        utf8.encode('the private RSA key, as PKCS8 base64, would go here'),
      );

      final SymmetricCryptoValue encrypted = HawkiCrypto.encrypt(
        plaintext,
        key,
      );
      final Uint8List decrypted = HawkiCrypto.decrypt(encrypted, key);

      expect(decrypted, plaintext);
    });

    test('iv is 12 bytes and tag is 16 bytes, matching AES-GCM/HAWKI\'s wire '
        'format exactly', () {
      final Uint8List key = HawkiCrypto.deriveKey(
        passphrase: 'pw',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      final SymmetricCryptoValue encrypted = HawkiCrypto.encrypt(
        Uint8List.fromList(utf8.encode('hello')),
        key,
      );
      expect(encrypted.iv, hasLength(12));
      expect(encrypted.tag, hasLength(16));
    });

    test('two encryptions of the same plaintext use different random IVs '
        'and produce different ciphertext', () {
      final Uint8List key = HawkiCrypto.deriveKey(
        passphrase: 'pw',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      final Uint8List plaintext = Uint8List.fromList(utf8.encode('hello'));
      final SymmetricCryptoValue first = HawkiCrypto.encrypt(plaintext, key);
      final SymmetricCryptoValue second = HawkiCrypto.encrypt(plaintext, key);
      expect(first.iv, isNot(second.iv));
      expect(first.ciphertext, isNot(second.ciphertext));
    });

    test('decrypting with the wrong key throws HawkiCryptoException, never '
        'returns garbage plaintext — this is what makes a wrong passkey '
        'detectable instead of silently corrupting a conversation', () {
      final Uint8List rightKey = HawkiCrypto.deriveKey(
        passphrase: 'right-passkey',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      final Uint8List wrongKey = HawkiCrypto.deriveKey(
        passphrase: 'wrong-passkey',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      final SymmetricCryptoValue encrypted = HawkiCrypto.encrypt(
        Uint8List.fromList(utf8.encode('secret')),
        rightKey,
      );

      expect(
        () => HawkiCrypto.decrypt(encrypted, wrongKey),
        throwsA(isA<HawkiCryptoException>()),
      );
    });

    test('decrypting tampered ciphertext throws HawkiCryptoException', () {
      final Uint8List key = HawkiCrypto.deriveKey(
        passphrase: 'pw',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      final SymmetricCryptoValue encrypted = HawkiCrypto.encrypt(
        Uint8List.fromList(utf8.encode('secret')),
        key,
      );
      final Uint8List tamperedCiphertext = Uint8List.fromList(
        encrypted.ciphertext,
      );
      tamperedCiphertext[0] ^= 0xFF;
      final SymmetricCryptoValue tampered = SymmetricCryptoValue(
        iv: encrypted.iv,
        tag: encrypted.tag,
        ciphertext: tamperedCiphertext,
      );

      expect(
        () => HawkiCrypto.decrypt(tampered, key),
        throwsA(isA<HawkiCryptoException>()),
      );
    });

    test('a value serialized to the wire format and parsed back still '
        'decrypts correctly — proves the wire format round-trip is lossless', () {
      final Uint8List key = HawkiCrypto.deriveKey(
        passphrase: 'pw',
        label: 'keychain_encryptor',
        serverSalt: 'salt',
      );
      final Uint8List plaintext = Uint8List.fromList(utf8.encode('hello'));
      final SymmetricCryptoValue encrypted = HawkiCrypto.encrypt(
        plaintext,
        key,
      );
      final SymmetricCryptoValue roundTripped = SymmetricCryptoValue.parse(
        encrypted.serialize(),
      );
      expect(HawkiCrypto.decrypt(roundTripped, key), plaintext);
    });
  });
}
