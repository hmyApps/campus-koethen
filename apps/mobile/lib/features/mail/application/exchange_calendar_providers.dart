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
import 'mail_suggestions.dart';
import 'mail_sync_controller.dart';

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
        // Every EWS call is a Basic-auth login against the central university
        // account. Once IMAP or EWS rejected the stored password in this mail
        // session, no further request is sent: failed logins can lock the
        // account. The IMAP rejection is watched, so a successful manual sync
        // loads the window again; the EWS lock is only read (this provider
        // sets it itself) and lifts with a new sign-in, which is watched above.
        final bool rejected =
            ref.watch(mailCredentialsRejectionProvider) != null ||
            ref.read(mailDirectoryAuthLockProvider);
        if (rejected) {
          throw const ExchangeCalendarFailure(
            ExchangeCalendarFailureKind.invalidCredentials,
          );
        }
        final MailAccountController controller = ref.read(
          mailAccountControllerProvider.notifier,
        );
        final MailDirectoryAuthLock authLock = ref.read(
          mailDirectoryAuthLockProvider.notifier,
        );
        final int generation = controller.sessionGeneration;
        final MailCredentials credentials = await controller
            .requireCredentials();
        final ExchangeCalendarGateway gateway = ref.watch(
          exchangeCalendarGatewayProvider,
        );

        // Smaller requests avoid EWS's 1000-occurrence page ceiling. A page
        // that is still truncated is rejected by the parser, never accepted as
        // an apparently complete calendar. The windows run one after another
        // so a rejected password costs exactly one failed login.
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
          final DateTime endExclusive = DateTime(
            endInclusive.year,
            endInclusive.month,
            endInclusive.day + 1,
          );
          final List<ExchangeCalendarEvent> chunk;
          try {
            chunk = await gateway.fetchEvents(
              credentials,
              from: cursor,
              to: endExclusive,
            );
          } on ExchangeCalendarFailure catch (failure) {
            if (failure.kind ==
                    ExchangeCalendarFailureKind.invalidCredentials &&
                controller.isSessionCurrent(generation)) {
              authLock.lock();
            }
            rethrow;
          }
          if (!controller.isSessionCurrent(generation)) {
            throw const ExchangeCalendarFailure(
              ExchangeCalendarFailureKind.invalidCredentials,
            );
          }
          for (final ExchangeCalendarEvent event in chunk) {
            byId[event.id] = event;
          }
          cursor = endExclusive;
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
