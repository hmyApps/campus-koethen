// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/api_meta.dart';
import '../../../core/network/loaded.dart';
import '../../../core/prefs/settings_controller.dart';
import '../data/timetable_models.dart';
import '../data/timetable_repository.dart';
import 'timetable_week.dart';
import 'timetable_change.dart';
import 'timetable_change_controller.dart';

/// One progressively loaded result set of the server-side group search.
@immutable
class TimetableGroupSearchState {
  const TimetableGroupSearchState({
    required this.groups,
    required this.page,
    required this.totalPages,
    required this.meta,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.fromCache = false,
    this.cachedAt,
  });

  final List<TimetableGroup> groups;
  final int page;
  final int totalPages;
  final ApiMeta meta;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final bool fromCache;
  final DateTime? cachedAt;

  bool get hasMore => page < totalPages;

  TimetableGroupSearchState copyWith({
    List<TimetableGroup>? groups,
    int? page,
    int? totalPages,
    ApiMeta? meta,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => TimetableGroupSearchState(
    groups: groups ?? this.groups,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    meta: meta ?? this.meta,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    fromCache: fromCache,
    cachedAt: cachedAt,
  );
}

class TimetableGroupSearchController
    extends AsyncNotifier<TimetableGroupSearchState> {
  TimetableGroupSearchController(this.query);

  final String query;
  int _generation = 0;
  ({int generation, String locale, String query})? _scope;

  TimetableRepository get _repository => ref.read(timetableRepositoryProvider);

  @override
  Future<TimetableGroupSearchState> build() async {
    final int generation = ++_generation;
    _scope = null;
    final String locale = ref.watch(localeCodeProvider);
    final String normalizedQuery = query.trim();
    final Loaded<List<TimetableGroup>> first = await _repository.fetchGroups(
      locale: locale,
      query: normalizedQuery,
    );
    _scope = (generation: generation, locale: locale, query: normalizedQuery);
    final ApiPagination? pagination = first.meta.pagination;
    return TimetableGroupSearchState(
      groups: List<TimetableGroup>.unmodifiable(first.value),
      page: pagination?.page ?? 1,
      totalPages: pagination?.totalPages ?? 1,
      meta: first.meta,
      fromCache: first.fromCache,
      cachedAt: first.cachedAt,
    );
  }

  Future<void> loadMore() async {
    final TimetableGroupSearchState? current = state.value;
    final ({int generation, String locale, String query})? scope = _scope;
    if (current == null ||
        scope == null ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }
    state = AsyncData<TimetableGroupSearchState>(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );
    try {
      final Loaded<List<TimetableGroup>> next = await _repository.fetchGroups(
        locale: scope.locale,
        query: scope.query,
        page: current.page + 1,
      );
      if (_scope != scope || scope.generation != _generation) return;
      final TimetableGroupSearchState base = state.value ?? current;
      final Set<String> seen = base.groups
          .map((TimetableGroup group) => group.id)
          .toSet();
      final List<TimetableGroup> merged = <TimetableGroup>[...base.groups];
      for (final TimetableGroup group in next.value) {
        if (seen.add(group.id)) merged.add(group);
      }
      final ApiPagination? pagination = next.meta.pagination;
      state = AsyncData<TimetableGroupSearchState>(
        base.copyWith(
          groups: List<TimetableGroup>.unmodifiable(merged),
          page: pagination?.page ?? current.page + 1,
          totalPages: pagination?.totalPages ?? current.totalPages,
          isLoadingMore: false,
          loadMoreFailed: false,
        ),
      );
    } on Object {
      if (_scope != scope || scope.generation != _generation) return;
      final TimetableGroupSearchState base = state.value ?? current;
      state = AsyncData<TimetableGroupSearchState>(
        base.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }
}

final timetableGroupSearchProvider =
    AsyncNotifierProvider.family<
      TimetableGroupSearchController,
      TimetableGroupSearchState,
      String
    >(TimetableGroupSearchController.new, isAutoDispose: true);

final FutureProvider<Loaded<TimetableStatus>> timetableStatusProvider =
    FutureProvider<Loaded<TimetableStatus>>((Ref ref) {
      final String locale = ref.watch(localeCodeProvider);
      return ref.watch(timetableRepositoryProvider).fetchStatus(locale: locale);
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

/// Metadata for the selected UUID, resolved independently of the picker.
///
/// A hidden legacy alias may resolve to its public representative. In that
/// case the stored Campus UUID is migrated immediately; no upstream id is
/// involved.
final FutureProvider<Loaded<TimetableGroup>?> selectedTimetableGroupProvider =
    FutureProvider<Loaded<TimetableGroup>?>((Ref ref) async {
      final String? groupId = ref.watch(selectedTimetableGroupIdProvider);
      if (groupId == null) return null;
      final String locale = ref.watch(localeCodeProvider);
      final Loaded<TimetableGroup> loaded = await ref
          .watch(timetableRepositoryProvider)
          .fetchGroup(locale: locale, groupId: groupId);
      if (loaded.value.id != groupId) {
        await ref
            .read(settingsProvider.notifier)
            .setTimetableGroup(loaded.value.id);
      }
      return loaded;
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
      final Loaded<Timetable> loaded = await ref
          .watch(timetableRepositoryProvider)
          .fetchEntries(
            locale: locale,
            groupId: request.groupId,
            from: request.weekStart,
            to: request.weekEnd,
          );
      if (!loaded.fromCache &&
          (loaded.meta.featureEnabled ?? true) &&
          TimetableDataState.fromWire(loaded.meta.dataState) ==
              TimetableDataState.ready) {
        // The encrypted hint store is supplementary local state. A slow or
        // unavailable keystore must never hold the actual timetable response
        // on the loading screen.
        unawaited(
          ref
              .read(timetableChangeControllerProvider.notifier)
              .observe(
                scope: TimetableChangeScope(
                  groupId: request.groupId,
                  rangeKey: request.weekStart.toIso8601String(),
                ),
                timetable: loaded.value,
              ),
        );
      }
      return loaded;
    });

typedef TimetableForegroundRefresh = Future<void> Function();

/// Refreshes only availability, the selected group and its current week.
///
/// In particular, a cold start with no selection never downloads the picker
/// catalogue. The catalogue belongs to the picker and onboarding only.
final Provider<TimetableForegroundRefresh> timetableForegroundRefreshProvider =
    Provider<TimetableForegroundRefresh>((Ref ref) {
      return () async {
        ref.invalidate(timetableStatusProvider);
        ref.invalidate(selectedTimetableGroupProvider);
        ref.invalidate(timetableWeekProvider);
        await ref.read(timetableStatusProvider.future);

        String? groupId = ref.read(selectedTimetableGroupIdProvider);
        if (groupId == null) return;
        await ref.read(selectedTimetableGroupProvider.future);
        final String? migratedGroupId = ref.read(
          selectedTimetableGroupIdProvider,
        );
        if (migratedGroupId == null) return;
        await ref.read(
          timetableWeekProvider(
            TimetableWeekRequest(
              groupId: migratedGroupId,
              weekStart: TimetableWeek.startOf(DateTime.now()),
            ),
          ).future,
        );
      };
    });
