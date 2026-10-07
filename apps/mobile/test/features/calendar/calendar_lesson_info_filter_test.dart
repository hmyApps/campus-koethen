// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/calendar/application/calendar_providers.dart';
import 'package:campus_koethen/features/calendar/application/public_calendar_providers.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/timetable/application/timetable_lesson_info_filter.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

void main() {
  test(
    'calendar day counts and entries follow the exact lesson information filter',
    () async {
      final DateTime monday = DateTime(2026, 10, 5);
      final Map<String, dynamic> json = timetableWeekFixture(monday);
      final List<dynamic> days = json['days'] as List<dynamic>;
      final List<dynamic> entries =
          (days.first as Map<String, dynamic>)['entries'] as List<dynamic>;
      (entries[0] as Map<String, dynamic>)['lessonInfo'] = 'P1';
      (entries[1] as Map<String, dynamic>)['lessonInfo'] = 'Gruppe1';
      final Timetable timetable = Timetable.fromJson(json)!;

      final ProviderContainer container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(
            InMemoryKeyValueStore(<String, Object>{
              PreferenceKeys.preferredTimetableGroup: timetableGroupIdFixture,
            }),
          ),
          timetableWeekProvider.overrideWith(
            (Ref ref, TimetableWeekRequest request) async =>
                Loaded<Timetable>(value: timetable, meta: ApiMeta.empty),
          ),
          publicCalendarMonthEntriesProvider.overrideWith(
            (Ref ref, DateTime anchor) async => const <CalendarEntry>[],
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(calendarDataProvider(monday), (_, _) {});
      await Future.wait([
        for (final DateTime start in monthWeekStarts(monday))
          container.read(
            timetableWeekProvider(
              TimetableWeekRequest(
                groupId: timetableGroupIdFixture,
                weekStart: start,
              ),
            ).future,
          ),
        container.read(publicCalendarMonthEntriesProvider(monday).future),
      ]);
      await container.pump();

      CalendarData data = container.read(calendarDataProvider(monday));
      expect(data.forDay(monday), hasLength(4));
      expect(data.entryCountsByDay[monday], 4);

      await container
          .read(timetableLessonInfoFilterProvider.notifier)
          .setSelected('P1', selected: false);
      await container.pump();
      data = container.read(calendarDataProvider(monday));
      expect(data.forDay(monday), hasLength(3));
      expect(data.entryCountsByDay[monday], 3);
      expect(
        data.forDay(monday).map((entry) => entry.title),
        isNot(contains('Mathematik 2')),
      );
      expect(
        data.forDay(monday).map((entry) => entry.title),
        contains('Technische Mechanik'),
      );
    },
  );

  test(
    'calendar includes only selected modules from a module-only group',
    () async {
      final DateTime monday = DateTime(2026, 10, 5);
      Timetable plan(String groupId, List<TimetableEntry> entries) => Timetable(
        group: TimetableGroup(id: groupId, shortName: groupId),
        days: <TimetableDay>[TimetableDay(date: monday, entries: entries)],
      );
      TimetableEntry lesson(String id, String code, int hour) => TimetableEntry(
        id: id,
        start: DateTime(2026, 10, 5, hour),
        end: DateTime(2026, 10, 5, hour + 1),
        title: id,
        subjectCode: code,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(
            InMemoryKeyValueStore(<String, Object>{
              PreferenceKeys.preferredTimetableGroup: 'primary',
            }),
          ),
          selectedTimetableGroupIdsProvider.overrideWithValue(const <String>[
            'primary',
            'other',
          ]),
          selectedTimetableModuleKeysByGroupProvider.overrideWithValue(
            const <String, Set<String>>{
              'other': <String>{'code:MATH2'},
            },
          ),
          timetableWeekProvider.overrideWith((Ref ref, request) async {
            return Loaded<Timetable>(
              value: request.groupId == 'primary'
                  ? plan('primary', <TimetableEntry>[
                      lesson('primary', 'MAIN', 12),
                    ])
                  : plan('other', <TimetableEntry>[
                      lesson('math', 'MATH2', 8),
                      lesson('physics', 'PHYS2', 10),
                    ]),
              meta: ApiMeta.empty,
            );
          }),
          publicCalendarMonthEntriesProvider.overrideWith(
            (Ref ref, DateTime anchor) async => const <CalendarEntry>[],
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(calendarDataProvider(monday), (_, _) {});
      await Future.wait([
        for (final DateTime start in monthWeekStarts(monday))
          for (final String groupId in const <String>['primary', 'other'])
            container.read(
              timetableWeekProvider(
                TimetableWeekRequest(groupId: groupId, weekStart: start),
              ).future,
            ),
        container.read(publicCalendarMonthEntriesProvider(monday).future),
      ]);
      await container.pump();

      expect(
        container
            .read(calendarDataProvider(monday))
            .forDay(monday)
            .map((entry) => entry.title),
        <String>['math', 'primary'],
      );
    },
  );
}
