// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The wiring of the 08:00 overview to the app's own local sources
/// (LEVIORA-164).
///
/// Everything below the provider is already covered by
/// `daily_summary_test.dart` and `daily_summary_content_test.dart`. What is
/// checked here is what only the provider can get wrong: which sources it
/// reads, when it reads them at all, and that a change in any of them
/// replaces the plan instead of adding to it.
library;

import 'dart:ui' show Locale;

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/time/clock.dart';
import 'package:campus_koethen/features/calendar/application/public_calendar_providers.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/calendar/domain/public_calendar.dart';
import 'package:campus_koethen/features/canteen/application/canteen_filter_controller.dart';
import 'package:campus_koethen/features/canteen/application/canteen_providers.dart';
import 'package:campus_koethen/features/canteen/data/canteen_models.dart';
import 'package:campus_koethen/features/canteen/domain/canteen_filter.dart';
import 'package:campus_koethen/features/events/application/saved_events_controller.dart';
import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:campus_koethen/features/events/domain/unified_event.dart';
import 'package:campus_koethen/features/moodle/application/moodle_account_controller.dart';
import 'package:campus_koethen/features/moodle/application/moodle_controller.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_account.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:campus_koethen/features/notifications/application/daily_summary_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_planner.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/application/notification_settings_controller.dart';
import 'package:campus_koethen/features/notifications/application/notification_tap_router.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_permission.dart';
import 'package:campus_koethen/features/notifications/domain/notification_preferences.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:campus_koethen/features/notifications/domain/planned_notification.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../support/fake_notification_gateway.dart';

const String kGroupId = 'inf-24';
final DateTime kToday = DateTime(2026, 8, 24);

// --- doubles -----------------------------------------------------------------

class _FixedClock implements Clock {
  const _FixedClock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

class _FakeSavedEvents extends SavedEventsController {
  _FakeSavedEvents(this.events);
  final List<SavedEventSnapshot> events;
  @override
  Future<List<SavedEventSnapshot>> build() async => events;
}

class _FakeMoodleAccount extends MoodleAccountController {
  _FakeMoodleAccount(this.account);
  final MoodleAccount? account;
  @override
  Future<MoodleAccount?> build() async => account;
}

class _FakeMoodle extends MoodleController {
  _FakeMoodle(this.deadlines);
  final List<MoodleDeadline> deadlines;
  @override
  Future<MoodleOverviewState> build() async =>
      MoodleOverviewState(deadlines: deadlines);
}

class _FakeCanteenFilter extends CanteenFilterController {
  _FakeCanteenFilter(this.favourites);
  final Set<String> favourites;
  @override
  CanteenFilter build() => CanteenFilter(favourites: favourites);
}

// --- fixtures ----------------------------------------------------------------

Loaded<T> loaded<T>(T value) => Loaded<T>(value: value, meta: const ApiMeta());

Timetable timetableWith(List<DateTime> starts) => Timetable(
  group: const TimetableGroup(id: kGroupId, shortName: 'INF 24'),
  days: <TimetableDay>[
    for (final DateTime start in starts)
      TimetableDay(
        date: DateTime(start.year, start.month, start.day),
        entries: <TimetableEntry>[
          TimetableEntry(
            id: start.toIso8601String(),
            start: start,
            end: start.add(const Duration(minutes: 90)),
            title: 'Analysis I',
          ),
        ],
      ),
  ],
);

CalendarEntry publicEvent(DateTime start, {String id = 'pc1'}) => CalendarEntry(
  id: 'publicCalendar:campus:$id',
  source: CalendarSource.publicCalendar,
  title: 'Campus Sommerfest',
  start: start,
  calendarSlug: 'campus',
);

SavedEventSnapshot savedEvent(DateTime start, {String ref = 'calendar:s1'}) =>
    SavedEventSnapshot(
      eventRef: ref,
      kind: UnifiedEventKind.calendarEvent,
      title: 'Gemerkter Vortrag',
      start: start,
      savedAt: kToday,
    );

CanteenMenu menuWith(Map<DateTime, List<String>> mealsByDay) => CanteenMenu(
  canteenSlug: 'fasanerieallee',
  displayName: 'Mensa Fasanerieallee',
  days: <MenuDay>[
    for (final MapEntry<DateTime, List<String>> day in mealsByDay.entries)
      MenuDay(
        date: day.key,
        meals: <Meal>[
          for (final String name in day.value) Meal(id: name, name: name),
        ],
      ),
  ],
);

// --- container ---------------------------------------------------------------

Future<ProviderContainer> harness({
  bool optedIn = true,
  bool categoryEnabled = true,
  NotificationPermissionStatus permission =
      NotificationPermissionStatus.granted,
  String? groupId = kGroupId,
  Timetable? timetable,
  List<CalendarEntry> publicEntries = const <CalendarEntry>[],
  List<SavedEventSnapshot> saved = const <SavedEventSnapshot>[],
  MoodleAccount? moodleAccount,
  List<MoodleDeadline> deadlines = const <MoodleDeadline>[],
  CanteenMenu? menu,
  Set<String> favourites = const <String>{},
  Locale locale = const Locale('de'),
  DateTime? now,
  Set<String> hiddenCourses = const <String>{},
}) async {
  final KeyValueStore store = InMemoryKeyValueStore(<String, Object>{
    PreferenceKeys.preferredTimetableGroup: ?groupId,
    if (groupId != null && hiddenCourses.isNotEmpty)
      PreferenceKeys.timetableHiddenCourses(groupId): hiddenCourses.toList(),
  });
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      keyValueStoreProvider.overrideWithValue(store),
      notificationGatewayProvider.overrideWithValue(
        FakeNotificationGateway(permission: permission),
      ),
      notificationClockProvider.overrideWithValue(
        _FixedClock(now ?? DateTime(2026, 8, 24, 6)),
      ),
      selectedTimetableGroupIdProvider.overrideWithValue(groupId),
      // Returned as plain values, not futures: the candidate provider is
      // synchronous and reads whatever these already hold, exactly as it does
      // in the app once a fetch has resolved.
      timetableWeekProvider.overrideWith(
        (Ref ref, TimetableWeekRequest request) =>
            loaded(timetable ?? timetableWith(const <DateTime>[])),
      ),
      publicCalendarMonthEntriesProvider.overrideWith(
        (Ref ref, DateTime anchor) => publicEntries,
      ),
      publicCalendarsCatalogProvider.overrideWith(
        (Ref ref) => loaded(const <PublicCalendar>[]),
      ),
      savedEventsControllerProvider.overrideWith(() => _FakeSavedEvents(saved)),
      moodleAccountControllerProvider.overrideWith(
        () => _FakeMoodleAccount(moodleAccount),
      ),
      moodleControllerProvider.overrideWith(() => _FakeMoodle(deadlines)),
      selectedCanteenSlugProvider.overrideWithValue(menu?.canteenSlug),
      canteenMenuProvider.overrideWith(
        (Ref ref, String slug) =>
            loaded(menu ?? menuWith(const <DateTime, List<String>>{})),
      ),
      canteenFilterProvider.overrideWith(() => _FakeCanteenFilter(favourites)),
      activeLocaleProviderOverride(locale),
    ],
  );
  addTearDown(container.dispose);

  if (optedIn) {
    await container
        .read(notificationSettingsProvider.notifier)
        .setOptedIn(true);
  }
  if (!categoryEnabled) {
    await container
        .read(notificationSettingsProvider.notifier)
        .setCategoryEnabled(NotificationCategory.dailySummary, false);
  }
  // Everything the provider reads asynchronously, resolved before it is asked.
  await container.read(notificationPermissionProvider.future);
  await container.read(savedEventsControllerProvider.future);
  await container.read(moodleAccountControllerProvider.future);
  await container.read(moodleControllerProvider.future);
  await container.read(publicCalendarsCatalogProvider.future);
  return container;
}

Override activeLocaleProviderOverride(Locale locale) =>
    settingsProvider.overrideWith(() => _FixedSettings(locale));

class _FixedSettings extends SettingsController {
  _FixedSettings(this.locale);
  final Locale locale;
  @override
  AppSettings build() => super.build().copyWith(
    localeMode: locale.languageCode == 'en'
        ? LocaleMode.english
        : LocaleMode.german,
  );
}

List<NotificationRequest> candidatesOf(ProviderContainer container) =>
    container.read(dailySummaryCandidatesProvider);

void main() {
  setUpAll(() {
    initializeDateFormatting();
    tz_data.initializeTimeZones();
  });

  group('the overview is only planned when it may be delivered', () {
    test('nothing before the reader has opted in', () async {
      final ProviderContainer container = await harness(
        optedIn: false,
        timetable: timetableWith(<DateTime>[DateTime(2026, 8, 25, 8, 30)]),
      );
      expect(candidatesOf(container), isEmpty);
    });

    test('nothing while the category is switched off', () async {
      final ProviderContainer container = await harness(
        categoryEnabled: false,
        timetable: timetableWith(<DateTime>[DateTime(2026, 8, 25, 8, 30)]),
      );
      expect(candidatesOf(container), isEmpty);
    });

    test('nothing while the operating system refuses', () async {
      final ProviderContainer container = await harness(
        permission: NotificationPermissionStatus.denied,
        timetable: timetableWith(<DateTime>[DateTime(2026, 8, 25, 8, 30)]),
      );
      expect(candidatesOf(container), isEmpty);
    });
  });

  group('one candidate per non-empty day, and none for the empty ones', () {
    test('two days with lectures produce exactly two overviews', () async {
      final ProviderContainer container = await harness(
        timetable: timetableWith(<DateTime>[
          DateTime(2026, 8, 25, 8, 30),
          DateTime(2026, 8, 27, 10),
        ]),
      );

      final List<NotificationRequest> candidates = candidatesOf(container);
      expect(candidates.map((NotificationRequest r) => r.target), <String>[
        '2026-08-25',
        '2026-08-27',
      ]);
      expect(
        candidates.every(
          (NotificationRequest r) =>
              r.category == NotificationCategory.dailySummary,
        ),
        isTrue,
      );
    });

    test('a day never produces two overviews, whatever it holds', () async {
      final ProviderContainer container = await harness(
        timetable: timetableWith(<DateTime>[DateTime(2026, 8, 25, 8, 30)]),
        publicEntries: <CalendarEntry>[publicEvent(DateTime(2026, 8, 25, 16))],
        moodleAccount: const MoodleAccount(userId: 1),
        deadlines: <MoodleDeadline>[
          MoodleDeadline(
            id: 1,
            title: 'Übungsblatt 4',
            dueAt: DateTime(2026, 8, 25, 23, 59),
            courseName: 'Datenbanken II',
          ),
        ],
        menu: menuWith(<DateTime, List<String>>{
          DateTime(2026, 8, 25): <String>['Käsespätzle'],
        }),
        favourites: const <String>{'Käsespätzle'},
      );

      final List<NotificationRequest> candidates = candidatesOf(container);
      expect(candidates, hasLength(1));
      expect(candidates.single.key, 'n2:2026-08-25');
      expect(
        candidates.single.body,
        'Heute 1 Vorlesung (erste um 08:30 Uhr), »Campus Sommerfest« um '
        '16:00 Uhr, 1 Moodle-Abgabefrist und »Käsespätzle« in der Mensa.',
      );
      expect(candidates.single.visibility, NotificationVisibility.neutral);
      expect(
        candidates.single.body,
        isNot(contains('Übungsblatt')),
        reason: 'P10: no assignment title on a lock screen.',
      );
    });

    test('an empty horizon plans nothing at all', () async {
      final ProviderContainer container = await harness();
      expect(candidatesOf(container), isEmpty);
    });
  });

  group('every source is actually read', () {
    test('no timetable group means no lectures in the overview', () async {
      final ProviderContainer container = await harness(
        groupId: null,
        timetable: timetableWith(<DateTime>[DateTime(2026, 8, 25, 8, 30)]),
      );
      expect(candidatesOf(container), isEmpty);
    });

    test('a hidden timetable course is absent from the overview', () async {
      final DateTime day = DateTime(2026, 8, 25);
      final ProviderContainer container = await harness(
        timetable: Timetable(
          group: const TimetableGroup(id: kGroupId, shortName: 'INF 24'),
          days: <TimetableDay>[
            TimetableDay(
              date: day,
              entries: <TimetableEntry>[
                TimetableEntry(
                  id: 'analysis',
                  start: DateTime(2026, 8, 25, 8, 30),
                  end: DateTime(2026, 8, 25, 10),
                  title: 'Analysis I',
                ),
                TimetableEntry(
                  id: 'databases',
                  start: DateTime(2026, 8, 25, 10, 15),
                  end: DateTime(2026, 8, 25, 11, 45),
                  title: 'Datenbanken II',
                ),
              ],
            ),
          ],
        ),
        hiddenCourses: const <String>{'Analysis I'},
      );

      expect(
        candidatesOf(container).single.body,
        'Heute 1 Vorlesung (erste um 10:15 Uhr).',
      );
    });

    test('a saved event alone fills a day', () async {
      final ProviderContainer container = await harness(
        saved: <SavedEventSnapshot>[savedEvent(DateTime(2026, 8, 26, 18))],
      );

      final List<NotificationRequest> candidates = candidatesOf(container);
      expect(candidates, hasLength(1));
      expect(candidates.single.target, '2026-08-26');
      expect(candidates.single.body, contains('Gemerkter Vortrag'));
    });

    test('a bookmark of a live calendar entry is not counted twice', () async {
      final ProviderContainer container = await harness(
        publicEntries: <CalendarEntry>[
          publicEvent(DateTime(2026, 8, 26, 18), id: 'live'),
        ],
        saved: <SavedEventSnapshot>[
          savedEvent(DateTime(2026, 8, 26, 18), ref: 'calendar:live'),
        ],
      );

      expect(
        candidatesOf(container).single.body,
        'Heute »Campus Sommerfest« um 18:00 Uhr.',
      );
    });

    test(
      'Moodle deadlines are ignored while no account is connected',
      () async {
        final ProviderContainer container = await harness(
          deadlines: <MoodleDeadline>[
            MoodleDeadline(
              id: 1,
              title: 'Übungsblatt 4',
              dueAt: DateTime(2026, 8, 26, 23, 59),
            ),
          ],
        );
        expect(candidatesOf(container), isEmpty);
      },
    );

    test('a plain menu and a favourite dish both fill their day', () async {
      final ProviderContainer withMenuOnly = await harness(
        menu: menuWith(<DateTime, List<String>>{
          DateTime(2026, 8, 26): <String>['Linseneintopf'],
        }),
      );
      expect(
        candidatesOf(withMenuOnly).single.body,
        'Heute Speiseplan verfügbar.',
      );

      final ProviderContainer withFavourite = await harness(
        menu: menuWith(<DateTime, List<String>>{
          DateTime(2026, 8, 26): <String>['Linseneintopf', 'Käsespätzle'],
        }),
        favourites: const <String>{'Käsespätzle'},
      );
      expect(
        candidatesOf(withFavourite).single.body,
        'Heute »Käsespätzle« in der Mensa.',
      );
    });
  });

  group('changes replace the plan rather than adding to it', () {
    test('switching the category off empties the list', () async {
      final ProviderContainer container = await harness(
        timetable: timetableWith(<DateTime>[DateTime(2026, 8, 25, 8, 30)]),
      );
      expect(candidatesOf(container), hasLength(1));

      await container
          .read(notificationSettingsProvider.notifier)
          .setCategoryEnabled(NotificationCategory.dailySummary, false);

      expect(candidatesOf(container), isEmpty);
    });

    test('the language of the text follows the app language', () async {
      final ProviderContainer container = await harness(
        locale: const Locale('en'),
        timetable: timetableWith(<DateTime>[DateTime(2026, 8, 25, 8, 30)]),
      );

      expect(
        candidatesOf(container).single.title,
        'Good morning! Your campus day',
      );
    });
  });

  group('the horizon moves with the day', () {
    test('today is planned, yesterday is not', () async {
      final ProviderContainer container = await harness(
        now: DateTime(2026, 8, 24, 6),
        timetable: timetableWith(<DateTime>[
          DateTime(2026, 8, 23, 8, 30),
          DateTime(2026, 8, 24, 8, 30),
        ]),
      );

      expect(
        candidatesOf(container).map((NotificationRequest r) => r.target),
        <String>['2026-08-24'],
      );
    });

    test('the planning day refreshes to the current date', () async {
      final ProviderContainer container = await harness();
      expect(container.read(notificationPlanningDayProvider), kToday);

      container.read(notificationPlanningDayProvider.notifier).refresh();
      expect(container.read(notificationPlanningDayProvider), kToday);
    });
  });

  group('08:00 stays 08:00 on the dial', () {
    /// The candidates, planned in a real zone — the full path from the
    /// sources to what the operating system would hold.
    Future<List<PlannedNotification>> planIn(
      String zone,
      DateTime firstLecture,
    ) async {
      final tz.Location location = tz.getLocation(zone);
      final ProviderContainer container = await harness(
        now: firstLecture.subtract(const Duration(days: 7)),
        timetable: timetableWith(<DateTime>[firstLecture]),
      );
      return planNotifications(
        candidates: candidatesOf(container),
        preferences: const NotificationPreferences(optedIn: true),
        permission: NotificationPermissionStatus.granted,
        now: tz.TZDateTime.from(
          firstLecture.subtract(const Duration(days: 7)),
          location,
        ),
      ).notifications;
    }

    test(
      'the overview lands at 08:00 local on both sides of the DST change',
      () async {
        // Germany turns the clocks back in the small hours of 25 October 2026.
        for (final DateTime day in <DateTime>[
          DateTime(2026, 10, 24, 10),
          DateTime(2026, 10, 26, 10),
        ]) {
          final List<PlannedNotification> planned = await planIn(
            'Europe/Berlin',
            day,
          );

          expect(planned, hasLength(1), reason: '$day');
          expect(planned.single.scheduledAt.hour, 8, reason: '$day');
          expect(planned.single.scheduledAt.minute, 0, reason: '$day');
          expect(planned.single.scheduledAt.day, day.day, reason: '$day');
        }
      },
    );

    test('a different device zone plans the same wall-clock time', () async {
      final List<PlannedNotification> planned = await planIn(
        'Australia/Sydney',
        DateTime(2026, 8, 27, 10),
      );

      expect(planned.single.scheduledAt.hour, 8);
      expect(planned.single.scheduledAt.location.name, 'Australia/Sydney');
    });
  });

  group('the tap target names the day the overview is about', () {
    test('the payload round-trips into the calendar day view', () async {
      final ProviderContainer container = await harness(
        timetable: timetableWith(<DateTime>[DateTime(2026, 8, 27, 8, 30)]),
      );

      final NotificationRequest request = candidatesOf(container).single;
      final NotificationTapTarget? target = const NotificationTapRouter()
          .resolve(request.payload.toStorage());

      expect(target?.resolved, isTrue);
      expect(target?.focusDay, DateTime(2026, 8, 27));
    });
  });
}
