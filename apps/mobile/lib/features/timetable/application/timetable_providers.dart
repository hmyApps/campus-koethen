// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/loaded.dart';
import '../../../core/prefs/settings_controller.dart';
import '../data/timetable_models.dart';
import '../data/timetable_repository.dart';
import 'timetable_week.dart';
import 'semester_assistant.dart';
import 'timetable_aggregation.dart';

/// All selectable study groups. Comes exclusively from the Campus API.
final FutureProvider<Loaded<List<TimetableGroup>>> timetableGroupsProvider =
    FutureProvider<Loaded<List<TimetableGroup>>>((Ref ref) async {
      final String locale = ref.watch(localeCodeProvider);
      return ref.watch(timetableRepositoryProvider).fetchGroups(locale: locale);
    });

final FutureProvider<Loaded<List<TimetablePeriod>>> timetablePeriodsProvider =
    FutureProvider<Loaded<List<TimetablePeriod>>>((Ref ref) async {
      final String locale = ref.watch(localeCodeProvider);
      return ref
          .watch(timetableRepositoryProvider)
          .fetchPeriods(locale: locale);
    }, retry: (_, _) => null);

final timetableModulesProvider =
    FutureProvider.family<Loaded<List<TimetableModule>>, String>((
      Ref ref,
      String groupId,
    ) {
      final String locale = ref.watch(localeCodeProvider);
      return ref
          .watch(timetableRepositoryProvider)
          .fetchModules(locale: locale, groupId: groupId);
    });

final timetableLessonInfoOptionsProvider =
    FutureProvider.family<Loaded<TimetableLessonInfoOptions>, String>((
      Ref ref,
      String groupId,
    ) async {
      final String locale = ref.watch(localeCodeProvider);
      return ref
          .watch(timetableRepositoryProvider)
          .fetchLessonInfo(locale: locale, groupId: groupId);
    }, isAutoDispose: true);

/// The group the user chose, or `null` when they have not chosen yet.
///
/// There is deliberately **no** automatic default: a wrong timetable is worse
/// than none, so the screen shows an onboarding state instead.
final Provider<String?> selectedTimetableGroupIdProvider = Provider<String?>(
  (Ref ref) => ref.watch(
    settingsProvider.select(
      (AppSettings settings) => settings.timetableGroupId,
    ),
  ),
);

/// Primary group first, followed by the independently subscribed groups.
final Provider<List<String>> selectedTimetableGroupIdsProvider =
    Provider<List<String>>((Ref ref) {
      final String? primary = ref.watch(selectedTimetableGroupIdProvider);
      if (primary == null) return const <String>[];
      final List<String> additional = ref.watch(
        settingsProvider.select(
          (AppSettings settings) => settings.timetableAdditionalGroupIds,
        ),
      );
      final List<TimetableModuleSubscription> modules = ref.watch(
        settingsProvider.select(
          (AppSettings settings) => settings.timetableAdditionalModules,
        ),
      );
      final Set<String> ids = <String>{primary, ...additional};
      ids.addAll(modules.map((module) => module.groupId));
      return List<String>.unmodifiable(ids);
    });

final Provider<Map<String, Set<String>>>
selectedTimetableModuleKeysByGroupProvider = Provider<Map<String, Set<String>>>(
  (Ref ref) {
    final Map<String, Set<String>> result = <String, Set<String>>{};
    for (final TimetableModuleSubscription subscription
        in ref.watch(settingsProvider).timetableAdditionalModules) {
      result
          .putIfAbsent(subscription.groupId, () => <String>{})
          .add(subscription.moduleKey);
    }
    return Map<String, Set<String>>.unmodifiable(
      result.map(
        (groupId, keys) => MapEntry(groupId, Set<String>.unmodifiable(keys)),
      ),
    );
  },
);

final Provider<DateTime> timetableAssistantClockProvider = Provider<DateTime>(
  (Ref ref) => DateTime.now(),
);

final Provider<TimetableSemesterSuggestion?>
timetableSemesterSuggestionProvider = Provider<TimetableSemesterSuggestion?>((
  Ref ref,
) {
  final AppSettings settings = ref.watch(settingsProvider);
  final List<TimetablePeriod>? periods = ref
      .watch(timetablePeriodsProvider)
      .value
      ?.value;
  if (periods == null) return null;
  return semesterSuggestion(
    periods: periods,
    selectedGroupId: settings.timetableGroupId,
    now: ref.watch(timetableAssistantClockProvider),
    dismissedPeriodId: settings.dismissedTimetablePeriodId,
  );
});

/// The day the timetable screen currently shows. Defaults to today.
///
/// The visible week is derived from this single value, so week navigation and
/// day selection can never drift apart.
class SelectedTimetableDayController extends Notifier<DateTime> {
  @override
  DateTime build() => TimetableWeek.dayOf(DateTime.now());

  void select(DateTime date) => state = TimetableWeek.dayOf(date);

  void today() => select(DateTime.now());

  void previousWeek() =>
      state = TimetableWeek.shift(state, -TimetableWeek.lengthInDays);

  void nextWeek() =>
      state = TimetableWeek.shift(state, TimetableWeek.lengthInDays);
}

final NotifierProvider<SelectedTimetableDayController, DateTime>
selectedTimetableDayProvider =
    NotifierProvider<SelectedTimetableDayController, DateTime>(
      SelectedTimetableDayController.new,
    );

/// One timetable request: a group and a calendar week.
///
/// A value type, so the provider family keeps one independent entry per group
/// and per week instead of overwriting a single one.
@immutable
class TimetableWeekRequest {
  TimetableWeekRequest({required this.groupId, required DateTime weekStart})
    : weekStart = TimetableWeek.startOf(weekStart);

  final String groupId;
  final DateTime weekStart;

  DateTime get weekEnd =>
      TimetableWeek.shift(weekStart, TimetableWeek.lengthInDays - 1);

  @override
  bool operator ==(Object other) =>
      other is TimetableWeekRequest &&
      other.groupId == groupId &&
      other.weekStart == weekStart;

  @override
  int get hashCode => Object.hash(groupId, weekStart);

  @override
  String toString() => 'TimetableWeekRequest($groupId, $weekStart)';
}

@immutable
class AggregatedTimetableWeekRequest {
  AggregatedTimetableWeekRequest({
    required Iterable<String> groupIds,
    required DateTime weekStart,
  }) : groupIds = List<String>.unmodifiable(groupIds),
       weekStart = TimetableWeek.startOf(weekStart);

  final List<String> groupIds;
  final DateTime weekStart;

  @override
  bool operator ==(Object other) =>
      other is AggregatedTimetableWeekRequest &&
      other.weekStart == weekStart &&
      listEquals(other.groupIds, groupIds);

  @override
  int get hashCode => Object.hash(weekStart, Object.hashAll(groupIds));
}

/// A bounded date range used when the calendar list covers several months.
@immutable
class TimetableRangeRequest {
  TimetableRangeRequest({
    required this.groupId,
    required DateTime from,
    required DateTime to,
  }) : from = TimetableWeek.dayOf(from),
       to = TimetableWeek.dayOf(to);

  final String groupId;
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is TimetableRangeRequest &&
      other.groupId == groupId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(groupId, from, to);
}

final timetableRangeProvider =
    FutureProvider.family<Loaded<Timetable>, TimetableRangeRequest>((
      Ref ref,
      TimetableRangeRequest request,
    ) async {
      final String locale = ref.watch(localeCodeProvider);
      return ref
          .watch(timetableRepositoryProvider)
          .fetchEntries(
            locale: locale,
            groupId: request.groupId,
            from: request.from,
            to: request.to,
          );
    });

/// The timetable of one group for one week.
final timetableWeekProvider =
    FutureProvider.family<Loaded<Timetable>, TimetableWeekRequest>((
      Ref ref,
      TimetableWeekRequest request,
    ) async {
      final String locale = ref.watch(localeCodeProvider);
      return ref
          .watch(timetableRepositoryProvider)
          .fetchEntries(
            locale: locale,
            groupId: request.groupId,
            from: request.weekStart,
            to: request.weekEnd,
          );
    });

/// Loads subscribed groups concurrently. A broken optional group does not hide
/// the primary timetable; the primary group remains the required anchor.
final aggregatedTimetableWeekProvider =
    FutureProvider.family<Loaded<Timetable>, AggregatedTimetableWeekRequest>((
      Ref ref,
      AggregatedTimetableWeekRequest request,
    ) async {
      if (request.groupIds.isEmpty) {
        throw ArgumentError.value(
          request.groupIds,
          'groupIds',
          'must not be empty',
        );
      }
      final results = await Future.wait(
        request.groupIds.map((String groupId) async {
          try {
            return (
              loaded: await ref.watch(
                timetableWeekProvider(
                  TimetableWeekRequest(
                    groupId: groupId,
                    weekStart: request.weekStart,
                  ),
                ).future,
              ),
              error: null,
              stackTrace: null,
            );
          } catch (error, stackTrace) {
            return (loaded: null, error: error, stackTrace: stackTrace);
          }
        }),
      );
      final loaded = results
          .map((result) => result.loaded)
          .whereType<Loaded<Timetable>>()
          .toList(growable: false);
      // The aggregate is anchored in the explicitly chosen primary group. If
      // that request fails, showing only an optional course under its header
      // would silently mislabel the timetable. Optional failures may degrade
      // to the primary plan; the reverse is not safe.
      final primary = results.first;
      if (primary.loaded == null) {
        Error.throwWithStackTrace(primary.error!, primary.stackTrace!);
      }
      final Map<String, Set<String>> moduleKeysByGroup = ref.watch(
        selectedTimetableModuleKeysByGroupProvider,
      );
      final List<Timetable> visibleTimetables = <Timetable>[];
      for (int index = 0; index < results.length; index++) {
        final Loaded<Timetable>? item = results[index].loaded;
        if (item == null) continue;
        final Set<String>? moduleKeys =
            moduleKeysByGroup[request.groupIds[index]];
        visibleTimetables.add(
          moduleKeys == null
              ? item.value
              : filterTimetableModules(item.value, moduleKeys),
        );
      }
      final DateTime? cachedAt = loaded
          .map((item) => item.cachedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (oldest, value) =>
                oldest == null || value.isBefore(oldest) ? value : oldest,
          );
      return Loaded<Timetable>(
        value: mergeTimetables(visibleTimetables),
        meta: loaded.first.meta,
        fromCache: loaded.any((item) => item.fromCache),
        cachedAt: cachedAt,
      );
    });
