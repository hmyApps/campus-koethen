// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'exchange_calendar_event.dart';
import 'mail_credentials.dart';

enum ExchangeCalendarFailureKind {
  invalidRequest,
  invalidCredentials,
  permissionDenied,
  networkUnavailable,
  timeout,
  serviceUnavailable,
  tlsOrHostRejected,
  invalidResponse,
}

class ExchangeCalendarFailure implements Exception {
  const ExchangeCalendarFailure(this.kind);

  final ExchangeCalendarFailureKind kind;

  @override
  bool operator ==(Object other) =>
      other is ExchangeCalendarFailure && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'ExchangeCalendarFailure($kind)';
}

abstract interface class ExchangeCalendarGateway {
  /// Reads occurrences overlapping `[from, to)`. Implementations request only
  /// the fields used by the local merged calendar and never persist results.
  Future<List<ExchangeCalendarEvent>> fetchEvents(
    MailCredentials credentials, {
    required DateTime from,
    required DateTime to,
  });
}
