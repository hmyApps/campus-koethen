// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'canteen_balance_apdu.dart';

enum CanteenBalanceAvailability { available, disabled, notSupported }

enum CanteenBalanceReadOrigin { manual, externalTag }

enum CanteenBalanceFailure {
  notSupported,
  disabled,
  cancelled,
  tagLost,
  unsupportedTag,
  invalidResponse,
  busy,
  unknown,
}

/// A user-facing failure category without UID, command bytes or raw response.
class CanteenBalanceReadException implements Exception {
  const CanteenBalanceReadException(this.reason);

  final CanteenBalanceFailure reason;

  @override
  String toString() => 'CanteenBalanceReadException(${reason.name})';
}

/// Platform-neutral port for the transient NFC operation.
abstract interface class CanteenBalanceReader {
  Future<CanteenBalanceAvailability> availability();

  /// Whether Android holds a tag delivered by a TECH_DISCOVERED intent.
  /// Always false on platforms without system-wide tag dispatch.
  Future<bool> hasPendingExternalTag();

  /// Emits only an occurrence, never a UID or other tag data.
  Stream<void> get externalTagDiscovered;

  Future<CanteenBalance> read({
    required CanteenBalanceReadOrigin origin,
    required String prompt,
  });

  Future<void> cancel();
}
