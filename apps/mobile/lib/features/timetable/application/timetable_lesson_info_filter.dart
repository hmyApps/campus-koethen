// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/preference_keys.dart';
import '../../../core/prefs/settings_controller.dart';
import '../data/timetable_models.dart';
import 'timetable_providers.dart';

/// Per-group exclusions. Exact source strings are keys; no name or group
/// heuristics are applied. A new source string is always visible by default.
///
/// Two independent dimensions, deliberately not conflated: [disabledValues]/
/// [hideWithoutInfo] filter by the lesson-info remark (room/group notes),
/// while [hiddenCourses] filters by the course itself
/// (`TimetableEntry.displayTitle`) — hiding a course the reader is not
/// enrolled in, e.g. a cross-listed elective, is a different question from
/// hiding a specific remark on a course they keep.
class TimetableLessonInfoFilter {
  TimetableLessonInfoFilter({
    required this.groupId,
    Set<String> disabledValues = const <String>{},
    this.hideWithoutInfo = false,
    Set<String> hiddenCourses = const <String>{},
  }) : disabledValues = Set<String>.unmodifiable(disabledValues),
       hiddenCourses = Set<String>.unmodifiable(hiddenCourses);

  final String? groupId;
  final Set<String> disabledValues;
  final bool hideWithoutInfo;
  final Set<String> hiddenCourses;

  bool accepts(String? value) => value == null || value.trim().isEmpty
      ? !hideWithoutInfo
      : !disabledValues.contains(value);

  bool acceptsCourse(String? title) =>
      title == null || !hiddenCourses.contains(title);

  /// The combined verdict a calendar/agenda entry needs: both the lesson-info
  /// remark and the course itself must be accepted.
  bool acceptsEntry(TimetableEntry entry) =>
      accepts(entry.lessonInfo) && acceptsCourse(entry.displayTitle);
}

class TimetableLessonInfoFilterController
    extends Notifier<TimetableLessonInfoFilter> {
  @override
  TimetableLessonInfoFilter build() {
    final String? groupId = ref.watch(selectedTimetableGroupIdProvider);
    final store = ref.watch(keyValueStoreProvider);
    return TimetableLessonInfoFilter(
      groupId: groupId,
      disabledValues: groupId == null
          ? const <String>{}
          : (store.getStringList(
                      PreferenceKeys.timetableLessonInfoDisabled(groupId),
                    ) ??
                    const <String>[])
                .toSet(),
      hideWithoutInfo:
          groupId != null &&
          store.getInt(
                PreferenceKeys.timetableLessonInfoWithoutHidden(groupId),
              ) ==
              1,
      hiddenCourses: groupId == null
          ? const <String>{}
          : (store.getStringList(
                      PreferenceKeys.timetableHiddenCourses(groupId),
                    ) ??
                    const <String>[])
                .toSet(),
    );
  }

  Future<void> setSelected(String value, {required bool selected}) async {
    final String? groupId = state.groupId;
    if (groupId == null) return;
    final Set<String> next = <String>{...state.disabledValues};
    if (selected) {
      next.remove(value);
    } else {
      next.add(value);
    }
    state = TimetableLessonInfoFilter(
      groupId: groupId,
      disabledValues: next,
      hideWithoutInfo: state.hideWithoutInfo,
      hiddenCourses: state.hiddenCourses,
    );
    await ref
        .read(keyValueStoreProvider)
        .setStringList(
          PreferenceKeys.timetableLessonInfoDisabled(groupId),
          next.toList()..sort(),
        );
  }

  Future<void> setWithoutInfoSelected(bool selected) async {
    final String? groupId = state.groupId;
    if (groupId == null) return;
    state = TimetableLessonInfoFilter(
      groupId: groupId,
      disabledValues: state.disabledValues,
      hideWithoutInfo: !selected,
      hiddenCourses: state.hiddenCourses,
    );
    await ref
        .read(keyValueStoreProvider)
        .setInt(
          PreferenceKeys.timetableLessonInfoWithoutHidden(groupId),
          selected ? 0 : 1,
        );
  }

  Future<void> setAll(
    TimetableLessonInfoOptions options, {
    required bool selected,
  }) async {
    final String? groupId = state.groupId;
    if (groupId == null) return;
    final Set<String> next = <String>{...state.disabledValues};
    if (selected) {
      next.removeAll(options.values);
    } else {
      next.addAll(options.values);
    }
    final bool hideWithoutInfo = options.hasWithoutInfo
        ? !selected
        : state.hideWithoutInfo;
    state = TimetableLessonInfoFilter(
      groupId: groupId,
      disabledValues: next,
      hideWithoutInfo: hideWithoutInfo,
      hiddenCourses: state.hiddenCourses,
    );
    final store = ref.read(keyValueStoreProvider);
    await store.setStringList(
      PreferenceKeys.timetableLessonInfoDisabled(groupId),
      next.toList()..sort(),
    );
    if (options.hasWithoutInfo) {
      await store.setInt(
        PreferenceKeys.timetableLessonInfoWithoutHidden(groupId),
        hideWithoutInfo ? 1 : 0,
      );
    }
  }

  /// Hides or restores one course by its exact displayed title, for the
  /// currently selected group only.
  Future<void> setCourseHidden(String title, {required bool hidden}) async {
    final String? groupId = state.groupId;
    if (groupId == null) return;
    final Set<String> next = <String>{...state.hiddenCourses};
    if (hidden) {
      next.add(title);
    } else {
      next.remove(title);
    }
    state = TimetableLessonInfoFilter(
      groupId: groupId,
      disabledValues: state.disabledValues,
      hideWithoutInfo: state.hideWithoutInfo,
      hiddenCourses: next,
    );
    await ref
        .read(keyValueStoreProvider)
        .setStringList(
          PreferenceKeys.timetableHiddenCourses(groupId),
          next.toList()..sort(),
        );
  }
}

final NotifierProvider<
  TimetableLessonInfoFilterController,
  TimetableLessonInfoFilter
>
timetableLessonInfoFilterProvider =
    NotifierProvider<
      TimetableLessonInfoFilterController,
      TimetableLessonInfoFilter
    >(TimetableLessonInfoFilterController.new);
