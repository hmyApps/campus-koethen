// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/core/network/loaded.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/timetable/application/timetable_aggregation.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Timetable timetable(String groupId, List<TimetableEntry> entries) => Timetable(
  group: TimetableGroup(id: groupId, shortName: groupId),
  days: <TimetableDay>[
    TimetableDay(date: DateTime(2026, 10, 12), entries: entries),
  ],
);

TimetableEntry entry(String id, int hour) => TimetableEntry(
  id: id,
  start: DateTime(2026, 10, 12, hour),
  end: DateTime(2026, 10, 12, hour + 1),
  title: id,
);

TimetableEntry moduleEntry(String id, String subjectCode, int hour) =>
    TimetableEntry(
      id: id,
      start: DateTime(2026, 10, 12, hour),
      end: DateTime(2026, 10, 12, hour + 1),
      title: id,
      subjectCode: subjectCode,
    );

void main() {
  test(
    'merges primary and additional groups and deduplicates shared lessons',
    () {
      final Timetable merged = mergeTimetables(<Timetable>[
        timetable('primary', <TimetableEntry>[entry('shared', 10)]),
        timetable('additional', <TimetableEntry>[
          entry('extra', 8),
          entry('shared', 10),
        ]),
      ]);

      expect(merged.group.id, 'primary');
      expect(merged.days.single.entries.map((item) => item.id), <String>[
        'extra',
        'shared',
      ]);
    },
  );

  test('keeps only subscribed modules from a module-only group', () {
    final Timetable filtered = filterTimetableModules(
      timetable('other', <TimetableEntry>[
        moduleEntry('math', 'MATH2', 8),
        moduleEntry('physics', 'PHYS2', 10),
      ]),
      const <String>{'code:MATH2'},
    );

    expect(filtered.days.single.entries.map((item) => item.id), <String>[
      'math',
    ]);
  });

  test('the aggregate provider applies module-only subscriptions', () async {
    const TimetableModuleSubscription subscription =
        TimetableModuleSubscription(groupId: 'other', moduleKey: 'code:MATH2');
    final ProviderContainer container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(
          InMemoryKeyValueStore(<String, Object>{
            PreferenceKeys.preferredTimetableGroup: 'primary',
            PreferenceKeys.additionalTimetableModules: <String>[
              subscription.storageValue,
            ],
          }),
        ),
        timetableWeekProvider.overrideWith((Ref ref, request) async {
          return Loaded<Timetable>(
            value: request.groupId == 'primary'
                ? timetable('primary', <TimetableEntry>[entry('primary', 12)])
                : timetable('other', <TimetableEntry>[
                    moduleEntry('math', 'MATH2', 8),
                    moduleEntry('physics', 'PHYS2', 10),
                  ]),
            meta: ApiMeta.empty,
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final List<String> groupIds = container.read(
      selectedTimetableGroupIdsProvider,
    );
    final Loaded<Timetable> result = await container.read(
      aggregatedTimetableWeekProvider(
        AggregatedTimetableWeekRequest(
          groupIds: groupIds,
          weekStart: DateTime(2026, 10, 12),
        ),
      ).future,
    );

    expect(result.value.days.single.entries.map((item) => item.id), <String>[
      'math',
      'primary',
    ]);
  });

  test(
    'an optional group failure keeps the primary timetable visible',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          timetableWeekProvider.overrideWith((Ref ref, request) async {
            if (request.groupId == 'additional') {
              throw StateError('optional group unavailable');
            }
            return Loaded<Timetable>(
              value: timetable('primary', <TimetableEntry>[
                entry('primary', 10),
              ]),
              meta: ApiMeta.empty,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final Loaded<Timetable> result = await container.read(
        aggregatedTimetableWeekProvider(
          AggregatedTimetableWeekRequest(
            groupIds: const <String>['primary', 'additional'],
            weekStart: DateTime(2026, 10, 12),
          ),
        ).future,
      );

      expect(result.value.group.id, 'primary');
      expect(result.value.days.single.entries.single.id, 'primary');
    },
  );

  test(
    'a primary group failure never exposes a mislabeled optional plan',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          timetableWeekProvider.overrideWith((Ref ref, request) async {
            if (request.groupId == 'primary') {
              throw StateError('primary group unavailable');
            }
            return Loaded<Timetable>(
              value: timetable('additional', <TimetableEntry>[
                entry('additional', 8),
              ]),
              meta: ApiMeta.empty,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(
          aggregatedTimetableWeekProvider(
            AggregatedTimetableWeekRequest(
              groupIds: const <String>['primary', 'additional'],
              weekStart: DateTime(2026, 10, 12),
            ),
          ).future,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
