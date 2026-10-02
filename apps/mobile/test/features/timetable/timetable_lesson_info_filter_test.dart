// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/prefs/settings_controller.dart';
import 'package:campus_koethen/features/timetable/application/timetable_lesson_info_filter.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

TimetableEntry _entry({String? title, String? lessonInfo}) => TimetableEntry(
  id: 'e1',
  start: DateTime.utc(2026, 10, 5, 8),
  end: DateTime.utc(2026, 10, 5, 9, 30),
  title: title,
  lessonInfo: lessonInfo,
);

void main() {
  test('all exact values and missing information are visible by default', () {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.preferredTimetableGroup: 'group-a',
    });
    final ProviderContainer container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final TimetableLessonInfoFilter filter = container.read(
      timetableLessonInfoFilterProvider,
    );
    expect(filter.accepts('P1'), isTrue);
    expect(filter.accepts('Gruppe1'), isTrue);
    expect(filter.accepts(null), isTrue);
  });

  test(
    'deselecting one exact value persists without hiding variants or new values',
    () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{PreferenceKeys.preferredTimetableGroup: 'group-a'},
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container
          .read(timetableLessonInfoFilterProvider.notifier)
          .setSelected('P1', selected: false);
      expect(
        container.read(timetableLessonInfoFilterProvider).accepts('P1'),
        isFalse,
      );
      expect(
        container.read(timetableLessonInfoFilterProvider).accepts('Gruppe1'),
        isTrue,
      );
      expect(
        container.read(timetableLessonInfoFilterProvider).accepts(' P1 '),
        isTrue,
      );
      expect(
        container.read(timetableLessonInfoFilterProvider).accepts('P2'),
        isTrue,
      );

      container.invalidate(timetableLessonInfoFilterProvider);
      expect(
        container.read(timetableLessonInfoFilterProvider).accepts('P1'),
        isFalse,
      );

      await container
          .read(settingsProvider.notifier)
          .setTimetableGroup('group-b');
      expect(
        container.read(timetableLessonInfoFilterProvider).accepts('P1'),
        isTrue,
      );
      await container
          .read(settingsProvider.notifier)
          .setTimetableGroup('group-a');
      expect(
        container.read(timetableLessonInfoFilterProvider).accepts('P1'),
        isFalse,
      );
    },
  );

  test('lessons without information can be hidden independently', () async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore(<String, Object>{
      PreferenceKeys.preferredTimetableGroup: 'group-a',
    });
    final ProviderContainer container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container
        .read(timetableLessonInfoFilterProvider.notifier)
        .setWithoutInfoSelected(false);
    expect(
      container.read(timetableLessonInfoFilterProvider).accepts(null),
      isFalse,
    );
    expect(
      container.read(timetableLessonInfoFilterProvider).accepts('P1'),
      isTrue,
    );
  });

  group('course hiding', () {
    test('every course is visible by default', () {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{PreferenceKeys.preferredTimetableGroup: 'group-a'},
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final TimetableLessonInfoFilter filter = container.read(
        timetableLessonInfoFilterProvider,
      );
      expect(
        filter.acceptsEntry(_entry(title: 'German für Professionals')),
        isTrue,
      );
    });

    test(
      'hiding a course persists per group and leaves other courses alone',
      () async {
        final InMemoryKeyValueStore store = InMemoryKeyValueStore(
          <String, Object>{PreferenceKeys.preferredTimetableGroup: 'group-a'},
        );
        final ProviderContainer container = ProviderContainer(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);

        await container
            .read(timetableLessonInfoFilterProvider.notifier)
            .setCourseHidden('German für Professionals', hidden: true);

        final TimetableLessonInfoFilter filter = container.read(
          timetableLessonInfoFilterProvider,
        );
        expect(
          filter.acceptsEntry(_entry(title: 'German für Professionals')),
          isFalse,
        );
        expect(filter.acceptsEntry(_entry(title: 'Analysis I')), isTrue);
        expect(filter.hiddenCourses, <String>{'German für Professionals'});

        container.invalidate(timetableLessonInfoFilterProvider);
        expect(
          container
              .read(timetableLessonInfoFilterProvider)
              .acceptsEntry(_entry(title: 'German für Professionals')),
          isFalse,
          reason: 'the choice survives a rebuild from storage',
        );

        await container
            .read(settingsProvider.notifier)
            .setTimetableGroup('group-b');
        expect(
          container
              .read(timetableLessonInfoFilterProvider)
              .acceptsEntry(_entry(title: 'German für Professionals')),
          isTrue,
          reason: 'the hidden set is scoped to the group that set it',
        );
      },
    );

    test('un-hiding a course restores it', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{PreferenceKeys.preferredTimetableGroup: 'group-a'},
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container
          .read(timetableLessonInfoFilterProvider.notifier)
          .setCourseHidden('German für Professionals', hidden: true);
      await container
          .read(timetableLessonInfoFilterProvider.notifier)
          .setCourseHidden('German für Professionals', hidden: false);

      expect(
        container
            .read(timetableLessonInfoFilterProvider)
            .acceptsEntry(_entry(title: 'German für Professionals')),
        isTrue,
      );
    });

    test('an entry with no title is never affected by course hiding', () {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore(
        <String, Object>{PreferenceKeys.preferredTimetableGroup: 'group-a'},
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final TimetableLessonInfoFilter filter = container.read(
        timetableLessonInfoFilterProvider,
      );
      expect(filter.acceptsEntry(_entry()), isTrue);
    });
  });
}
