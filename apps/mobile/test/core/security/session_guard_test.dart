// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/core/security/session_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalidation waits for work that already owns a lease', () async {
    final SessionGuard<int> guard = SessionGuard<int>()..activate(7);
    final SessionLease<int> lease = guard.capture(7)!;
    final Completer<void> response = Completer<void>();
    final Future<void> operation = guard.track<void>(lease, () async {
      await response.future;
    });

    bool invalidated = false;
    final Future<void> invalidation = guard.invalidateAndWait().whenComplete(
      () => invalidated = true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(invalidated, isFalse);
    expect(guard.isCurrent(lease), isFalse);

    response.complete();
    await Future.wait(<Future<void>>[operation, invalidation]);
    expect(invalidated, isTrue);
  });

  test(
    'first-use initialization never revives an invalidated session',
    () async {
      final SessionGuard<int> guard = SessionGuard<int>()..activate(7);
      await guard.invalidateAndWait();

      guard.initializeIfNeeded(7);

      expect(guard.capture(7), isNull);
    },
  );
}
