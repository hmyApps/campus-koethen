// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/loaded.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../application/timetable_lesson_info_filter.dart';
import '../application/timetable_providers.dart';
import '../data/timetable_models.dart';

Future<void> showTimetableLessonInfoFilterSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) =>
          const _TimetableLessonInfoFilterSheet(),
    );

class _TimetableLessonInfoFilterSheet extends ConsumerWidget {
  const _TimetableLessonInfoFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String? groupId = ref.watch(selectedTimetableGroupIdProvider);
    final AsyncValue<Loaded<TimetableLessonInfoOptions>>? options =
        groupId == null
        ? null
        : ref.watch(timetableLessonInfoOptionsProvider(groupId));
    final TimetableLessonInfoFilter filter = ref.watch(
      timetableLessonInfoFilterProvider,
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.timetableLessonInfoFilterTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(l10n.timetableLessonInfoFilterHint),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      switch (options) {
                        AsyncData<Loaded<TimetableLessonInfoOptions>>(
                          :final value,
                        ) =>
                          _Choices(options: value.value, filter: filter),
                        AsyncError<Loaded<TimetableLessonInfoOptions>>() =>
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              children: <Widget>[
                                Text(l10n.timetableLessonInfoLoadError),
                                if (groupId != null)
                                  TextButton(
                                    onPressed: () => ref.invalidate(
                                      timetableLessonInfoOptionsProvider(
                                        groupId,
                                      ),
                                    ),
                                    child: Text(l10n.actionRetry),
                                  ),
                              ],
                            ),
                          ),
                        _ => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(AppSpacing.lg),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      },
                      if (filter.hiddenCourses.isNotEmpty)
                        _HiddenCourses(filter: filter),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.actionClose),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choices extends ConsumerWidget {
  const _Choices({required this.options, required this.filter});

  final TimetableLessonInfoOptions options;
  final TimetableLessonInfoFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool hasChoices = options.values.isNotEmpty || options.hasWithoutInfo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!hasChoices)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(l10n.timetableLessonInfoNoOptions),
          )
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => ref
                      .read(timetableLessonInfoFilterProvider.notifier)
                      .setAll(options, selected: true),
                  child: Text(l10n.timetableLessonInfoSelectAll),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(timetableLessonInfoFilterProvider.notifier)
                      .setAll(options, selected: false),
                  child: Text(l10n.timetableLessonInfoDeselectAll),
                ),
              ],
            ),
          ),
          for (final String value in options.values)
            CheckboxListTile(
              value: filter.accepts(value),
              title: Text(value),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (bool? selected) => ref
                  .read(timetableLessonInfoFilterProvider.notifier)
                  .setSelected(value, selected: selected ?? false),
            ),
          if (options.hasWithoutInfo)
            CheckboxListTile(
              value: filter.accepts(null),
              title: Text(l10n.timetableLessonInfoWithout),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (bool? selected) => ref
                  .read(timetableLessonInfoFilterProvider.notifier)
                  .setWithoutInfoSelected(selected ?? false),
            ),
        ],
      ],
    );
  }
}

/// Courses hidden from a card's own "hide" action (`TimetableEntryCard`) —
/// the only place they can be restored from again, since they no longer
/// appear anywhere to offer their own un-hide control.
class _HiddenCourses extends ConsumerWidget {
  const _HiddenCourses({required this.filter});

  final TimetableLessonInfoFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final List<String> titles = filter.hiddenCourses.toList()..sort();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Text(
            l10n.timetableHiddenCoursesTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(l10n.timetableHiddenCoursesHint),
        ),
        for (final String title in titles)
          CheckboxListTile(
            value: false,
            title: Text(title),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (bool? selected) => ref
                .read(timetableLessonInfoFilterProvider.notifier)
                .setCourseHidden(title, hidden: !(selected ?? true)),
          ),
      ],
    );
  }
}
