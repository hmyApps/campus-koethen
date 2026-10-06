// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Contextual entry points C and D of the UX spec (§ 2.2).
///
/// Choosing a timetable group and connecting Moodle are the two moments at
/// which lectures and submission deadlines start existing locally. Both offer
/// the existing global opt-in; Moodle may additionally produce its own local,
/// neutral deadline reminder, without a second permission concept.
library;

import 'package:campus_koethen/features/moodle/application/moodle_providers.dart';
import 'package:campus_koethen/features/moodle/presentation/moodle_screen.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_settings_controller.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:campus_koethen/features/timetable/presentation/timetable_group_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_moodle.dart';
import '../../support/fake_notification_gateway.dart';
import '../../support/fake_timetable.dart';
import '../../support/pump_app.dart';

const String _prePromptTitle = 'Lokale Benachrichtigungen aktivieren?';

/// The setup form is built lazily inside a sliver list, so its fields only
/// exist once the viewport is tall enough to reach them.
void giveTheFormRoom(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _GroupPickerHost extends ConsumerWidget {
  const _GroupPickerHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => showTimetableGroupPickerSheet(context, ref),
        child: const Text('open'),
      ),
    ),
  );
}

List<Override> _timetableOverrides(FakeNotificationGateway gateway) =>
    <Override>[
      notificationGatewayProvider.overrideWithValue(gateway),
      timetableGroupSearchProvider('').overrideWith(
        () => FixedTimetableGroupSearchController(
          fixedTimetableGroupSearch(const <TimetableGroup>[
            TimetableGroup(id: 'inf-24', shortName: 'INF 24'),
          ]),
        ),
      ),
    ];

void main() {
  group('C · choosing a timetable group', () {
    testWidgets('offers the opt-in once the group is chosen', (
      WidgetTester tester,
    ) async {
      final FakeNotificationGateway gateway = FakeNotificationGateway(
        permission: NotificationPermissionStatus.notDetermined,
      );
      await pumpScreen(
        tester,
        const _GroupPickerHost(),
        overrides: _timetableOverrides(gateway),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('INF 24'));
      await tester.pumpAndSettle();

      expect(find.text(_prePromptTitle), findsOneWidget);
    });

    testWidgets('closing the picker without choosing asks nothing', (
      WidgetTester tester,
    ) async {
      final FakeNotificationGateway gateway = FakeNotificationGateway(
        permission: NotificationPermissionStatus.notDetermined,
      );
      await pumpScreen(
        tester,
        const _GroupPickerHost(),
        overrides: _timetableOverrides(gateway),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Dismiss the sheet by tapping the barrier above it.
      await tester.tapAt(const Offset(400, 10));
      await tester.pumpAndSettle();

      expect(find.text(_prePromptTitle), findsNothing);
    });

    testWidgets('a reader who already said "not now" is not asked again', (
      WidgetTester tester,
    ) async {
      final FakeNotificationGateway gateway = FakeNotificationGateway(
        permission: NotificationPermissionStatus.notDetermined,
      );
      final ProviderContainer container = await pumpScreen(
        tester,
        const _GroupPickerHost(),
        overrides: _timetableOverrides(gateway),
      );
      await container
          .read(notificationSettingsProvider.notifier)
          .markPrePromptDeclined();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('INF 24'));
      await tester.pumpAndSettle();

      expect(find.text(_prePromptTitle), findsNothing);
      expect(gateway.requestCount, 0);
    });
  });

  group('D · connecting Moodle', () {
    testWidgets('offers the opt-in after a successful connection', (
      WidgetTester tester,
    ) async {
      giveTheFormRoom(tester);
      final FakeNotificationGateway gateway = FakeNotificationGateway(
        permission: NotificationPermissionStatus.notDetermined,
      );
      await pumpScreen(
        tester,
        const MoodleScreen(),
        overrides: <Override>[
          notificationGatewayProvider.overrideWithValue(gateway),
          moodleApiClientProvider.overrideWithValue(FakeMoodleApiClient()),
          moodleTokenStoreProvider.overrideWithValue(
            InMemoryMoodleTokenStore(),
          ),
          moodleCacheStoreProvider.overrideWithValue(
            InMemoryMoodleCacheStore(),
          ),
          moodleClockProvider.overrideWithValue(
            MutableClock(DateTime.utc(2026, 8, 24, 12)),
          ),
        ],
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'demo');
      await tester.enterText(find.byType(TextFormField).last, 'secret');
      await tester.tap(find.text('Verbinden'));
      await tester.pumpAndSettle();

      expect(find.text(_prePromptTitle), findsOneWidget);
    });

    testWidgets('a failed connection asks nothing', (
      WidgetTester tester,
    ) async {
      final FakeNotificationGateway gateway = FakeNotificationGateway(
        permission: NotificationPermissionStatus.notDetermined,
      );
      giveTheFormRoom(tester);
      final FakeMoodleApiClient api = FakeMoodleApiClient()
        ..throwOnRequestToken = Exception('nope');
      await pumpScreen(
        tester,
        const MoodleScreen(),
        overrides: <Override>[
          notificationGatewayProvider.overrideWithValue(gateway),
          moodleApiClientProvider.overrideWithValue(api),
          moodleTokenStoreProvider.overrideWithValue(
            InMemoryMoodleTokenStore(),
          ),
          moodleCacheStoreProvider.overrideWithValue(
            InMemoryMoodleCacheStore(),
          ),
          moodleClockProvider.overrideWithValue(
            MutableClock(DateTime.utc(2026, 8, 24, 12)),
          ),
        ],
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'demo');
      await tester.enterText(find.byType(TextFormField).last, 'secret');
      await tester.tap(find.text('Verbinden'));
      await tester.pumpAndSettle();

      expect(find.text(_prePromptTitle), findsNothing);
    });
  });
}
