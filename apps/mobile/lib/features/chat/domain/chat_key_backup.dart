// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Whether this device can read encrypted history after a sign-out or on a
/// new device: the account's key backup with its recovery key.
enum ChatKeyBackupState {
  /// No end-to-end encryption on this device. Never the case on a device
  /// build, where the chat refuses to run without it.
  unavailable,

  /// The account has no key backup yet. Setting it up creates the recovery
  /// key, shown once.
  notSetUp,

  /// The account has one, but this device does not hold its keys yet: it
  /// needs the recovery key.
  locked,

  /// Set up and unlocked on this device.
  ready,
}
