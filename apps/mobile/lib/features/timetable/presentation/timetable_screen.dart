// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/locale/formatters.dart';
import '../../../core/network/loaded.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/offline_notice.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../core/widgets/translation_fallback_notice.dart';
import '../../../l10n/l10n.dart';
import '../application/timetable_pending_poller.dart';
import '../application/timetable_providers.dart';
import '../application/timetable_lesson_info_filter.dart';
import '../application/timetable_week.dart';
import '../data/timetable_models.dart';
import 'timetable_entry_card.dart';
import 'timetable_group_picker_sheet.dart';
import 'timetable_lesson_info_filter_sheet.dart';
import 'timetable_subscriptions_sheet.dart';
import '../application/semester_assistant.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// The timetable screen: course selection, week navigation, day selection and
/// the agenda of the selected day.
///
/// The app only ever talks to the Campus API. It knows no upstream address, no
/// upstream header and no upstream identifier, and it never polls aggressively:
/// a range that is still being prepared is re-checked by
/// [TimetablePendingPoller] with a backoff and a hard upper bound.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen>
    with WidgetsBindingObserver {
  late final TimetablePendingPoller _poller;

  @override
  void initState() {
    super.initState();
    _poller = TimetablePendingPoller(onRetry: _refresh);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _poller.handleLifecycleState(state);
  }

  Future<void> _refresh() async {
    ref.invalidate(timetableGroupsProvider);
    ref.invalidate(timetablePeriodsProvider);
    final List<String> groupIds = ref.read(selectedTimetableGroupIdsProvider);
    if (groupIds.isEmpty) return;
    ref.invalidate(
      aggregatedTimetableWeekProvider(
        AggregatedTimetableWeekRequest(
          groupIds: groupIds,
          weekStart: ref.read(selectedTimetableDayProvider),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String? groupId = ref.watch(selectedTimetableGroupIdProvider);
    final TimetableLessonInfoFilter lessonInfoFilter = ref.watch(
      timetableLessonInfoFilterProvider,
    );

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.timetableTitle,
      actions: <Widget>[
        if (groupId != null)
          IconButton(
            tooltip: l10n.timetableLessonInfoFilterTitle,
            onPressed: () => showTimetableLessonInfoFilterSheet(context),
            isSelected:
                lessonInfoFilter.disabledValues.isNotEmpty ||
                lessonInfoFilter.hideWithoutInfo,
            icon: const Icon(AppIcons.tune),
          ),
        IconButton(
          tooltip: l10n.timetableGroupPickerTooltip,
          onPressed: () => showTimetableGroupPickerSheet(context, ref),
          icon: const Icon(AppIcons.school_outlined),
        ),
        IconButton(
          tooltip: l10n.actionRefresh,
          onPressed: _refresh,
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      body: groupId == null
          ? _OnboardingView(l10n: l10n)
          : _buildTimetable(context, l10n),
    );
  }

  Widget _buildTimetable(BuildContext context, AppLocalizations l10n) {
    final DateTime selectedDay = ref.watch(selectedTimetableDayProvider);
    final AggregatedTimetableWeekRequest request =
        AggregatedTimetableWeekRequest(
          groupIds: ref.watch(selectedTimetableGroupIdsProvider),
          weekStart: selectedDay,
        );
    final AsyncValue<Loaded<Timetable>> week = ref.watch(
      aggregatedTimetableWeekProvider(request),
    );
    final Loaded<Timetable>? loaded = week.value;

    // Feeding the poller only with settled states keeps a refresh from
    // resetting the backoff, which is what would turn it into a poll.
    if (!week.isLoading && loaded != null) {
      _poller.update(
        isPending:
            (loaded.meta.featureEnabled ?? true) &&
            TimetableDataState.fromWire(loaded.meta.dataState) ==
                TimetableDataState.pending,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: switch (week) {
        AsyncLoading<Loaded<Timetable>>() when loaded == null =>
          const LoadingView(),
        AsyncError<Loaded<Timetable>>(:final Object error)
            when loaded == null =>
          ErrorView(
            failure: error,
            onRetry: () =>
                ref.invalidate(aggregatedTimetableWeekProvider(request)),
          ),
        // TIME-2: a refresh that fails over a plan already on screen was
        // completely silent — pull-to-refresh in flight mode simply put the
        // old week back. The banner keeps the data and says it is not fresh.
        AsyncError<Loaded<Timetable>>(:final Object error) => _TimetableContent(
          loaded: loaded!,
          selectedDay: selectedDay,
          onRefresh: _refresh,
          refreshError: error,
        ),
        _ => _TimetableContent(
          loaded: loaded!,
          selectedDay: selectedDay,
          onRefresh: _refresh,
        ),
      },
    );
  }
}

/// Shown until the user has chosen a course. Deliberately not an error state:
/// nothing went wrong, a decision is simply still missing.
class _OnboardingView extends ConsumerWidget {
  const _OnboardingView({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmptyView(
      icon: AppIcons.calendar_month_outlined,
      title: l10n.timetableNoSelectionTitle,
      message: l10n.timetableNoSelectionMessage,
      action: FilledButton.icon(
        onPressed: () => showTimetableGroupPickerSheet(context, ref),
        icon: const Icon(AppIcons.school_outlined),
        label: Text(l10n.timetableChooseGroupAction),
      ),
    );
  }
}

class _TimetableContent extends ConsumerWidget {
  const _TimetableContent({
    required this.loaded,
    required this.selectedDay,
    required this.onRefresh,
    this.refreshError,
  });

  final Loaded<Timetable> loaded;
  final DateTime selectedDay;
  final Future<void> Function() onRefresh;

  /// Set when the last refresh failed while this plan was already on screen.
  final Object? refreshError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final Timetable timetable = loaded.value;
    final List<String> additionalGroupIds = ref
        .watch(settingsProvider)
        .timetableAdditionalGroupIds;
    final int additionalModuleCount = ref
        .watch(settingsProvider)
        .timetableAdditionalModules
        .length;
    final TimetableLessonInfoFilter lessonInfoFilter = ref.watch(
      timetableLessonInfoFilterProvider,
    );
    final bool featureEnabled = loaded.meta.featureEnabled ?? true;
    final TimetableDataState dataState = TimetableDataState.fromWire(
      loaded.meta.dataState,
    );
    final DateTime? lastSync = loaded.meta.lastSuccessfulSyncAt;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        if (ref.watch(timetableSemesterSuggestionProvider)
            case final TimetableSemesterSuggestion suggestion) ...<Widget>[
          StatusBanner(
            tone: StatusTone.info,
            icon: AppIcons.update,
            title: l10n.timetableSemesterAssistantTitle,
            message: l10n.timetableSemesterAssistantMessage(
              suggestion.next.name,
            ),
            action: Wrap(
              spacing: AppSpacing.xs,
              children: <Widget>[
                TextButton(
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .dismissTimetablePeriod(suggestion.next.id),
                  child: Text(l10n.actionNotNow),
                ),
                FilledButton.tonal(
                  onPressed: () =>
                      showSemesterSuggestionSheet(context, suggestion),
                  child: Text(l10n.timetableSemesterAssistantSelect),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _GroupHeader(group: timetable.group),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            onTap: () => showAdditionalTimetableGroupsSheet(context),
            leading: const Icon(AppIcons.add_circle_outline),
            title: Text(
              l10n.timetableSubscriptionsAction(
                additionalGroupIds.length,
                additionalModuleCount,
              ),
            ),
            trailing: const Icon(AppIcons.chevron_right),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (refreshError != null) ...<Widget>[
          StatusBanner(
            tone: StatusTone.warning,
            icon: AppIcons.sync_problem,
            title: l10n.timetableRefreshFailed,
            message: ErrorView.messageFor(l10n, refreshError),
            action: TextButton(
              onPressed: onRefresh,
              child: Text(l10n.actionRetry),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (!featureEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: EmptyView(
              icon: AppIcons.schedule_outlined,
              title: l10n.timetableDisabledTitle,
              message: l10n.timetableDisabledMessage,
            ),
          )
        else ...<Widget>[
          const _WeekNavigator(),
          const SizedBox(height: AppSpacing.md),
          _DaySelector(selectedDay: selectedDay),
          const SizedBox(height: AppSpacing.md),
          if (loaded.fromCache) ...<Widget>[
            OfflineNotice(cachedAt: loaded.cachedAt),
            const SizedBox(height: AppSpacing.md),
          ],
          if (loaded.meta.translationFallback) ...<Widget>[
            const TranslationFallbackNotice(),
            const SizedBox(height: AppSpacing.md),
          ],
          if (loaded.meta.dataStale) ...<Widget>[
            StatusBanner(
              tone: StatusTone.warning,
              icon: AppIcons.update_disabled_outlined,
              title: l10n.timetableStaleTitle,
              message: l10n.timetableStaleMessage,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            lastSync == null
                ? l10n.timetableNeverSynced
                : l10n.timetableLastSyncAt(
                    AppDateFormats.dateTime(lastSync, locale),
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          switch (dataState) {
            TimetableDataState.pending => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: EmptyView(
                icon: AppIcons.hourglass_empty_outlined,
                title: l10n.timetablePendingTitle,
                message: l10n.timetablePendingMessage,
                action: FilledButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(AppIcons.refresh),
                  label: Text(l10n.actionRefresh),
                ),
              ),
            ),
            TimetableDataState.unavailable => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: EmptyView(
                icon: AppIcons.event_note_outlined,
                title: l10n.timetableUnavailableTitle,
                message: l10n.timetableUnavailableMessage,
              ),
            ),
            _ => _DayAgenda(
              timetable: timetable,
              selectedDay: selectedDay,
              filter: lessonInfoFilter,
            ),
          },
        ],
        const SizedBox(height: AppSpacing.xl),
        if (locale != 'de')
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l10n.timetableSourceLanguageHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Text(
          l10n.timetableSourceNotice,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The chosen course, and the shortest way to change it.
class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({required this.group});

  final TimetableGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final String details = <String?>[
      group.longName,
      group.department,
    ].whereType<String>().join(' · ');

    return Semantics(
      button: true,
      label: l10n.timetableGroupSemanticLabel(group.shortName, details),
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: () => showTimetableGroupPickerSheet(context, ref),
        icon: const Icon(AppIcons.school_outlined),
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              group.shortName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (details.isNotEmpty)
              Text(
                details,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekNavigator extends ConsumerWidget {
  const _WeekNavigator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final DateTime day = ref.watch(selectedTimetableDayProvider);
    final SelectedTimetableDayController controller = ref.read(
      selectedTimetableDayProvider.notifier,
    );
    final String range =
        '${AppDateFormats.dayAndMonth(TimetableWeek.startOf(day), locale)} – '
        '${AppDateFormats.dayAndMonth(TimetableWeek.endOf(day), locale)}';

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: l10n.timetablePreviousWeek,
              onPressed: controller.previousWeek,
              icon: const Icon(AppIcons.chevron_left),
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.timetableWeekRange(range),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.timetableNextWeek,
              onPressed: controller.nextWeek,
              icon: const Icon(AppIcons.chevron_right),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: controller.today,
          icon: const Icon(AppIcons.today_outlined),
          label: Text(l10n.timetableCurrentWeek),
        ),
      ],
    );
  }
}

/// Horizontal day picker of the visible week.
class _DaySelector extends ConsumerWidget {
  const _DaySelector({required this.selectedDay});

  final DateTime selectedDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final DateTime day in TimetableWeek.daysOf(selectedDay))
            _TimetableDayChip(
              date: day,
              isSelected: TimetableWeek.dayOf(selectedDay) == day,
              onTap: () =>
                  ref.read(selectedTimetableDayProvider.notifier).select(day),
            ),
        ],
      ),
    );
  }
}

class _TimetableDayChip extends StatelessWidget {
  const _TimetableDayChip({
    required this.date,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String locale = Localizations.localeOf(context).languageCode;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: l10n.timetableDaySemanticLabel(
          AppDateFormats.weekdayDate(date, locale),
        ),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: AppSizes.minTouchTarget,
              minHeight: AppSizes.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isSelected ? colors.primaryContainer : colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: isSelected ? colors.primary : colors.outline,
                width: isSelected ? AppSizes.beam / 2 : AppSizes.hairline,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  AppDateFormats.shortWeekday(date, locale),
                  style: text.labelMedium?.copyWith(
                    color: isSelected
                        ? colors.onPrimaryContainer
                        : colors.textSecondary,
                  ),
                ),
                Text(
                  AppDateFormats.dayOfMonth(date, locale),
                  style: text.titleSmall?.copyWith(
                    color: isSelected
                        ? colors.onPrimaryContainer
                        : colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The appointments of one day. An empty list is a real free day — the contract
/// delivers every day of the range, so this is never a hidden loading failure.
class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.timetable,
    required this.selectedDay,
    required this.filter,
  });

  final Timetable timetable;
  final DateTime selectedDay;
  final TimetableLessonInfoFilter filter;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final TimetableDay? day = timetable.dayFor(selectedDay);
    final List<TimetableEntry> allEntries =
        day?.entries ?? const <TimetableEntry>[];
    final List<TimetableEntry> entries = allEntries
        .where(
          (TimetableEntry entry) =>
              !entry.groups.any((group) => group.id == filter.groupId) ||
              filter.accepts(entry.lessonInfo),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            l10n.timetableDayHeading(
              AppDateFormats.weekdayDate(selectedDay, locale),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: EmptyView(
              icon: AppIcons.event_available_outlined,
              title: allEntries.isEmpty
                  ? l10n.timetableEmptyDayTitle
                  : l10n.timetableFilteredDayTitle,
              message: allEntries.isEmpty
                  ? l10n.timetableEmptyDayMessage
                  : l10n.timetableFilteredDayMessage,
            ),
          )
        else
          for (final TimetableEntry entry in entries) ...<Widget>[
            TimetableEntryCard(
              key: ValueKey<String>('timetable-entry-${entry.id}'),
              entry: entry,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }
}
