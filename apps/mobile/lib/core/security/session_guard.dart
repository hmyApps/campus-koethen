// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

/// Identifies one authenticated session at one monotonic generation.
final class SessionLease<I> {
  const SessionLease({required this.generation, required this.identity});

  final int generation;
  final I identity;
}

/// Coordinates in-flight personal-data work with account replacement/logout.
///
/// Invalidating first prevents new work from starting. Waiting for every
/// tracked operation before wiping guarantees that a write already underway
/// cannot recreate sensitive cache data after a reported logout.
final class SessionGuard<I> {
  int _generation = 0;
  I? _identity;
  bool _active = false;
  bool _initialized = false;
  final Set<Completer<void>> _operations = <Completer<void>>{};

  void activate(I identity) {
    if (_active && _identity == identity) return;
    _initialized = true;
    _generation++;
    _identity = identity;
    _active = true;
  }

  /// Activates a token restored on first use, but never revives an invalidated
  /// session whose secure-storage deletion is still in progress or failed.
  void initializeIfNeeded(I identity) {
    if (!_initialized) activate(identity);
  }

  SessionLease<I>? capture(I identity) {
    if (!_active || _identity != identity) return null;
    return SessionLease<I>(generation: _generation, identity: identity);
  }

  bool isCurrent(SessionLease<I> lease) =>
      _active && lease.generation == _generation && lease.identity == _identity;

  Future<T> track<T>(
    SessionLease<I> lease,
    Future<T> Function() operation,
  ) async {
    if (!isCurrent(lease)) throw const SessionInvalidated();

    final Completer<void> settled = Completer<void>();
    _operations.add(settled);
    try {
      if (!isCurrent(lease)) throw const SessionInvalidated();
      return await operation();
    } finally {
      _operations.remove(settled);
      if (!settled.isCompleted) settled.complete();
    }
  }

  Future<void> invalidateAndWait() async {
    _initialized = true;
    _active = false;
    _identity = null;
    _generation++;
    while (_operations.isNotEmpty) {
      await Future.wait<void>(
        _operations.map((Completer<void> operation) => operation.future),
      );
    }
  }
}

final class SessionInvalidated implements Exception {
  const SessionInvalidated();

  @override
  String toString() => 'SessionInvalidated';
}
