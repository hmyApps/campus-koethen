// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Holds the key of the encrypted Matrix database (AGENTS.md §2).
///
/// The SDK database carries the session token, the device and room keys and
/// the messages. It is only ever opened with this key, and the key only ever
/// lives in the Keychain/Keystore.
abstract interface class MatrixDatabaseKeyStore {
  /// The stored key, or `null` when none exists yet.
  Future<String?> read();

  /// The stored key, creating and verifiably storing a new one if needed.
  Future<String> readOrCreate();

  /// Removes the key and verifies it is gone.
  Future<void> clear();
}
