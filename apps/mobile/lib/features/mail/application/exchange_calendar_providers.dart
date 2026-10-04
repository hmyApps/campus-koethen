// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../data/ews_exchange_calendar_gateway.dart';
import '../domain/exchange_calendar_event.dart';
import '../domain/exchange_calendar_gateway.dart';
import '../domain/mail_credentials.dart';
import 'mail_account_controller.dart';
import 'mail_providers.dart';

final Provider<ExchangeCalendarGateway> exchangeCalendarGatewayProvider =
    Provider<ExchangeCalendarGateway>(
      (Ref ref) => EwsExchangeCalendarGateway(
        profile: ref.watch(hsaMailProfileProvider),
      ),
    );

@immutable
class ExchangeCalendarQuery {
  ExchangeCalendarQuery({required DateTime from, required DateTime to})
    : from = DateTime(from.year, from.month, from.day),
      to = DateTime(to.year, to.month, to.day);

  /// Inclusive local calendar bounds. The transport converts [to] to an
  /// exclusive next-day instant when it calls EWS.
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is ExchangeCalendarQuery && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Personal Exchange occurrences for one bounded calendar window.
///
/// Results are intentionally memory-only and auto-disposed. Credentials are
/// read from the secure store just in time and never enter provider state.
final exchangeCalendarEventsProvider =
    FutureProvider.family<List<ExchangeCalendarEvent>, ExchangeCalendarQuery>(
      (Ref ref, ExchangeCalendarQuery query) async {
        ref.watch(mailSessionGenerationProvider);
        final MailAccountState account = await ref.watch(
          mailAccountControllerProvider.future,
        );
        if (!account.isSignedIn || query.to.isBefore(query.from)) {
          return const <ExchangeCalendarEvent>[];
        }
        final MailAccountController controller = ref.read(
          mailAccountControllerProvider.notifier,
        );
        final int generation = controller.sessionGeneration;
        final MailCredentials credentials = await controller
            .requireCredentials();
        final ExchangeCalendarGateway gateway = ref.watch(
          exchangeCalendarGatewayProvider,
        );

        // Smaller requests avoid EWS's 1000-occurrence page ceiling. A page
        // that is still truncated is rejected by the parser, never accepted as
        // an apparently complete calendar.
        const int maximumDaysPerRequest = 92;
        final Map<String, ExchangeCalendarEvent> byId =
            <String, ExchangeCalendarEvent>{};
        DateTime cursor = query.from;
        while (!cursor.isAfter(query.to)) {
          final DateTime candidate = DateTime(
            cursor.year,
            cursor.month,
            cursor.day + maximumDaysPerRequest - 1,
          );
          final DateTime endInclusive = candidate.isAfter(query.to)
              ? query.to
              : candidate;
          final List<ExchangeCalendarEvent> chunk = await gateway.fetchEvents(
            credentials,
            from: cursor,
            to: DateTime(
              endInclusive.year,
              endInclusive.month,
              endInclusive.day + 1,
            ),
          );
          if (!controller.isSessionCurrent(generation)) {
            throw const ExchangeCalendarFailure(
              ExchangeCalendarFailureKind.invalidCredentials,
            );
          }
          for (final ExchangeCalendarEvent event in chunk) {
            byId[event.id] = event;
          }
          cursor = DateTime(
            endInclusive.year,
            endInclusive.month,
            endInclusive.day + 1,
          );
        }
        final List<ExchangeCalendarEvent> events = byId.values.toList()
          ..sort((a, b) {
            final int byStart = a.start.compareTo(b.start);
            return byStart != 0 ? byStart : a.id.compareTo(b.id);
          });
        return List<ExchangeCalendarEvent>.unmodifiable(events);
      },
      retry: (_, _) => null,
      isAutoDispose: true,
    );
