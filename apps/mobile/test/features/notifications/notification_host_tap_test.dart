// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/app_router.dart';
import 'package:campus_koethen/app/app_routes.dart';
import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/time/clock.dart';
import 'package:campus_koethen/features/calendar/application/calendar_providers.dart';
import 'package:campus_koethen/features/calendar/application/public_calendar_providers.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/public_calendar.dart';
import 'package:campus_koethen/features/calendar/presentation/calendar_entry_sheet.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/data/saved_events_store.dart';
import 'package:campus_koethen/features/moodle/application/moodle_providers.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:campus_koethen/features/notifications/application/moodle_deadline_candidates.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/data/device_time_zone.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_gateway.dart';
import 'package:campus_koethen/features/notifications/domain/notification_payload.dart';
import 'package:campus_koethen/features/notifications/domain/notification_plan.dart';
import 'package:campus_koethen/features/notifications/presentation/notification_host.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/fake_moodle.dart';

/// F-08 end to end: a tap on an event reminder has to open the entry's detail
/// sheet. The host sits in the `MaterialApp.router` builder, *above* the
/// router's navigator, so the sheet can only be shown through the router's
/// own root navigator — exactly the wiring this test reproduces.

final DateTime _now = DateTime(2026, 7, 1, 12);

class _FixedClock implements Clock {
  const _FixedClock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// Reports one launch payload, as a cold start from a notification does.
class _LaunchGateway extends NoopNotificationGateway {
  _LaunchGateway(this.payload);
  String? payload;

  @override
  Future<String?> takeLaunchPayload() async {
    final String? value = payload;
    payload = null;
    return value;
  }
}

const String _calendarEntryId = 'publicCalendar:hsa-events:4711';

final CalendarEntry _entry = CalendarEntry(
  id: _calendarEntryId,
  source: CalendarSource.publicCalendar,
  title: 'Demo: Campus Sommerfest',
  start: DateTime(2026, 7, 22, 16),
  calendarSlug: 'hsa-events',
  sourceLabel: 'Demo-Kalender',
);

/// Pumps the production wiring — the host in the `MaterialApp.router`
/// builder — with [payload] as the cold-start launch payload, and returns the
/// container.
Future<ProviderContainer> _pumpWithLaunchPayload(
  WidgetTester tester,
  String payload, {
  InMemoryMoodleCacheStore? moodleCache,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.news,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.news,
        builder: (BuildContext _, GoRouterState _) =>
            const Scaffold(body: Text('news')),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (BuildContext _, GoRouterState _) =>
            const Scaffold(body: Text('calendar')),
      ),
    ],
  );
  addTearDown(router.dispose);

  final GlobalKey appKey = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        appRouterProvider.overrideWithValue(router),
        notificationGatewayProvider.overrideWithValue(_LaunchGateway(payload)),
        notificationPlanProvider.overrideWithValue(
          const NotificationPlan.empty(),
        ),
        notificationClockProvider.overrideWithValue(_FixedClock(_now)),
        timeZoneResolverProvider.overrideWithValue(
          FixedTimeZoneResolver('Europe/Berlin'),
        ),
        savedEventsStoreProvider.overrideWithValue(MemorySavedEventsStore()),
        savedEventsClockProvider.overrideWithValue(() => _now),
        publicCalendarsCatalogProvider.overrideWith(
          (Ref ref) async => Loaded<List<PublicCalendar>>(
            value: const <PublicCalendar>[],
            meta: ApiMeta.empty,
          ),
        ),
        publicCalendarMonthEntriesProvider.overrideWith(
          (Ref ref, DateTime anchor) async =>
              anchor.month == 7 ? <CalendarEntry>[_entry] : <CalendarEntry>[],
        ),
        moodleApiClientProvider.overrideWithValue(FakeMoodleApiClient()),
        moodleTokenStoreProvider.overrideWithValue(
          InMemoryMoodleTokenStore()
            ..token = const MoodleToken(value: 'demo', userId: 7),
        ),
        moodleCacheStoreProvider.overrideWithValue(
          moodleCache ?? InMemoryMoodleCacheStore(),
        ),
        moodleClockProvider.overrideWithValue(MutableClock(_now)),
      ],
      child: MaterialApp.router(
        key: appKey,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        // The production wiring: the host wraps the router's output.
        builder: (BuildContext context, Widget? child) =>
            NotificationHost(child: child ?? const SizedBox.shrink()),
        routerConfig: router,
      ),
    ),
  );
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(appKey.currentContext!);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de');
    await initializeDateFormatting('en');
  });

  testWidgets('a tapped event reminder opens the entry sheet above the '
      'calendar', (WidgetTester tester) async {
    await _pumpWithLaunchPayload(
      tester,
      const NotificationPayload(
        category: NotificationCategory.eventReminder,
        target: _calendarEntryId,
      ).toStorage(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('calendar'), findsOneWidget);
    expect(find.byType(CalendarEntrySheet), findsOneWidget);
  });

  testWidgets('a tapped Moodle deadline reminder opens the calendar on the '
      'deadline day', (WidgetTester tester) async {
    final MoodleDeadline deadline = MoodleDeadline(
      id: 9,
      title: 'Demo-Abgabe',
      dueAt: DateTime(2026, 7, 14, 23, 59),
    );
    final ProviderContainer container = await _pumpWithLaunchPayload(
      tester,
      NotificationPayload(
        category: NotificationCategory.moodleDeadline,
        target: moodleDeadlineNotificationKey(deadline),
      ).toStorage(),
      moodleCache: InMemoryMoodleCacheStore()
        ..deadlines = <MoodleDeadline>[deadline],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('calendar'), findsOneWidget);
    expect(container.read(calendarFocusedDayProvider), DateTime(2026, 7, 14));
  });
}
