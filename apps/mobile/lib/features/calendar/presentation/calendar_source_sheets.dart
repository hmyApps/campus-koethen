// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/network/loaded.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../moodle/application/moodle_account_controller.dart';
import '../../moodle/domain/moodle_account.dart';
import '../../timetable/application/timetable_providers.dart';
import '../../timetable/data/timetable_models.dart';
import '../../timetable/presentation/timetable_group_picker_sheet.dart';
import '../../timetable/presentation/timetable_lesson_info_filter_sheet.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_entry.dart';
import 'public_calendar_list.dart';

/// Opens the list of everything the calendar is merged from.
///
/// The three sources used to be a permanent band of buttons above the calendar.
/// They are one action in the masthead now, and this is what it opens: each
/// source with its state spelled out, leading into the sheet that source
/// actually needs. Which calendars you are looking at is a question answered
/// once; which day you are looking at is the one asked all day, and only the
/// second one deserves standing room on the screen.
Future<void> showCalendarSourcesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const _SourcesSheet(),
  );
}

class _SourcesSheet extends ConsumerWidget {
  const _SourcesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final Set<CalendarSource> enabled = ref.watch(
      calendarEnabledSourcesProvider,
    );
    final bool moodleConnected =
        ref.watch(moodleAccountControllerProvider).value != null;

    String stateOf(CalendarSource source) {
      if (source == CalendarSource.moodle && !moodleConnected) {
        return l10n.calendarSourceNotConnected;
      }
      return enabled.contains(source)
          ? l10n.calendarSourceVisible
          : l10n.calendarSourceHidden;
    }

    /// One glyph per state, and three states — a source that has no account
    /// yet is not the same thing as one the reader switched off, so it does
    /// not get to wear the same symbol.
    IconData glyphOf(CalendarSource source) {
      if (source == CalendarSource.moodle && !moodleConnected) {
        return AppIcons.link_off;
      }
      return enabled.contains(source)
          ? calendarSourceIcon(source)
          : AppIcons.visibility_off_outlined;
    }

    return _SourceSheet(
      title: l10n.calendarSourcesLabel,
      children: <Widget>[
        for (final CalendarSource source in kMergeableCalendarSources)
          ListTile(
            leading: Icon(glyphOf(source)),
            title: Text(calendarSourceLabel(l10n, source)),
            // The state is part of the row, not a tint on it.
            subtitle: Text(stateOf(source)),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () {
              // Replaces this sheet rather than stacking on it.
              Navigator.of(context).pop();
              showCalendarSourceSheet(context, source);
            },
          ),
        const Divider(),
        const SavedEventsCalendarSwitch(),
        const CanteenFavouriteMealsSwitch(),
      ],
    );
  }
}

/// Opens the sheet behind one of the three source controls.
///
/// Each source gets its own sheet rather than one settings screen for all
/// three: what you can do with a source differs completely — the timetable
/// needs a course, Moodle needs an account, the events are a list of calendars
/// — and a single dialog trying to hold all of it would be a form, not a
/// control.
Future<void> showCalendarSourceSheet(
  BuildContext context,
  CalendarSource source,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => switch (source) {
      CalendarSource.timetable => const _TimetableSourceSheet(),
      CalendarSource.moodle => const _MoodleSourceSheet(),
      CalendarSource.publicCalendar => const _EventsSourceSheet(),
      CalendarSource.postEvent ||
      CalendarSource.savedEvents ||
      CalendarSource.canteenFavourite => throw UnsupportedError(
        '$source is not a toggleable calendar source sheet',
      ),
    },
  );
}

/// The shell every source sheet shares: a title and a scrollable body.
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Show this source in the calendar" — the one control every sheet has.
class CalendarSourceVisibilitySwitch extends ConsumerWidget {
  const CalendarSourceVisibilitySwitch({
    required this.source,
    this.sourceAsTitle = false,
    super.key,
  });

  final CalendarSource source;
  final bool sourceAsTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool visible = ref
        .watch(calendarEnabledSourcesProvider)
        .contains(source);

    return SwitchListTile.adaptive(
      value: visible,
      // The state is spelled out underneath, so the switch position is never
      // the only thing carrying it.
      title: Text(
        sourceAsTitle
            ? calendarSourceLabel(l10n, source)
            : l10n.calendarSourceShowInCalendar,
      ),
      subtitle: Text(
        visible ? l10n.calendarSourceVisible : l10n.calendarSourceHidden,
      ),
      secondary: Icon(visible ? AppIcons.visibility : AppIcons.visibility_off),
      onChanged: (bool _) =>
          ref.read(calendarEnabledSourcesProvider.notifier).toggle(source),
    );
  }
}

/// "Meine gemerkten Events" — an eigenständiger, optional switch, off by
/// default and entirely separate from the three mergeable sources above: it
/// needs no configuration of its own, so it lives directly in this sheet
/// instead of opening a further one.
class SavedEventsCalendarSwitch extends ConsumerWidget {
  const SavedEventsCalendarSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool enabled = ref.watch(calendarSavedEventsEnabledProvider);

    return SwitchListTile.adaptive(
      value: enabled,
      title: Text(l10n.calendarSourceSavedEvents),
      subtitle: Text(
        enabled ? l10n.calendarSourceVisible : l10n.calendarSourceHidden,
      ),
      secondary: Icon(enabled ? AppIcons.bookmark : AppIcons.bookmark_outlined),
      onChanged: (bool _) =>
          ref.read(calendarSavedEventsEnabledProvider.notifier).toggle(),
    );
  }
}

/// "Lieblingsspeisen im Kalender" — the same off-by-default, standalone
/// switch as [SavedEventsCalendarSwitch], and the exact same provider the canteen
/// favourites screen's own toggle reads (public for that reason), so there
/// is one setting, reachable from two places, never two that could disagree.
class CanteenFavouriteMealsSwitch extends ConsumerWidget {
  const CanteenFavouriteMealsSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool enabled = ref.watch(calendarShowFavouriteMealsProvider);

    return SwitchListTile.adaptive(
      value: enabled,
      title: Text(l10n.calendarSourceCanteenFavourite),
      subtitle: Text(
        enabled ? l10n.calendarSourceVisible : l10n.calendarSourceHidden,
      ),
      secondary: const Icon(AppIcons.soup),
      onChanged: (bool _) =>
          ref.read(calendarShowFavouriteMealsProvider.notifier).toggle(),
    );
  }
}

class _TimetableSourceSheet extends ConsumerWidget {
  const _TimetableSourceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String? groupId = ref.watch(selectedTimetableGroupIdProvider);
    final TimetableGroup? group = ref
        .watch(selectedTimetableGroupProvider)
        .value
        ?.value;

    return _SourceSheet(
      title: l10n.calendarSourceTimetable,
      children: <Widget>[
        ListTile(
          leading: const Icon(AppIcons.school_outlined),
          title: Text(
            // Falls back to the id only when the group list has not loaded —
            // never to an invented name.
            group?.shortName ?? groupId ?? l10n.calendarTimetableNoGroup,
          ),
          subtitle: Text(l10n.calendarTimetableGroupLabel),
        ),
        const CalendarSourceVisibilitySwitch(source: CalendarSource.timetable),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: OutlinedButton.icon(
            onPressed: () {
              // The picker replaces this sheet instead of stacking on it.
              Navigator.of(context).pop();
              showTimetableGroupPickerSheet(context, ref);
            },
            icon: const Icon(AppIcons.search),
            label: Text(l10n.timetableGroupPickerTitle),
          ),
        ),
        if (groupId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                showTimetableLessonInfoFilterSheet(context);
              },
              icon: const Icon(AppIcons.tune),
              label: Text(l10n.timetableLessonInfoFilterTitle),
            ),
          ),
      ],
    );
  }
}

class _MoodleSourceSheet extends ConsumerWidget {
  const _MoodleSourceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final MoodleAccount? account = ref
        .watch(moodleAccountControllerProvider)
        .value;
    final bool connected = account != null;

    void openMoodle() {
      Navigator.of(context).pop();
      // Moodle stays a direct device integration: this opens the Moodle area
      // of the app, it does not send anything anywhere.
      GoRouter.of(context).go(AppRoutes.moodle);
    }

    return _SourceSheet(
      title: l10n.calendarSourceMoodle,
      children: <Widget>[
        if (!connected) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(l10n.calendarConnectMoodleHint),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: FilledButton.icon(
              onPressed: openMoodle,
              icon: const Icon(AppIcons.link),
              label: Text(l10n.calendarConnectMoodle),
            ),
          ),
        ] else ...<Widget>[
          ListTile(
            leading: const Icon(AppIcons.account_circle_outlined),
            // The account name is optional in the Moodle contract; an empty
            // "connected as …" would look broken, so the site name stands in.
            title: Text(
              l10n.moodleConnectedAs(
                account.username ?? account.siteName ?? l10n.moodleTitle,
              ),
            ),
          ),
          const CalendarSourceVisibilitySwitch(source: CalendarSource.moodle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: OutlinedButton.icon(
              onPressed: openMoodle,
              icon: const Icon(AppIcons.open_in_new),
              label: Text(l10n.calendarOpenMoodle),
            ),
          ),
        ],
      ],
    );
  }
}

class _EventsSourceSheet extends ConsumerWidget {
  const _EventsSourceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    return _SourceSheet(
      title: l10n.calendarSectionPublic,
      children: const <Widget>[
        // The same list the manage screen shows, writing the same selection.
        PublicCalendarList(shrinkWrap: true),
      ],
    );
  }
}

/// The name of a source, for the control and its sheet.
String calendarSourceLabel(AppLocalizations l10n, CalendarSource source) =>
    switch (source) {
      CalendarSource.timetable => l10n.calendarSourceTimetable,
      CalendarSource.moodle => l10n.calendarSourceMoodle,
      CalendarSource.publicCalendar => l10n.calendarSourceEvents,
      CalendarSource.postEvent ||
      CalendarSource.savedEvents ||
      CalendarSource.canteenFavourite => throw UnsupportedError(
        '$source has no calendar-source label',
      ),
    };

/// Whether [source] is loaded from a [Loaded] response at all — kept next to
/// the labels so the control and the sheet cannot disagree about a source.
IconData calendarSourceIcon(CalendarSource source) => switch (source) {
  CalendarSource.timetable => AppIcons.schedule_outlined,
  CalendarSource.moodle => AppIcons.cast_for_education_outlined,
  CalendarSource.publicCalendar => AppIcons.public_outlined,
  CalendarSource.postEvent ||
  CalendarSource.savedEvents ||
  CalendarSource.canteenFavourite => throw UnsupportedError(
    '$source has no calendar-source icon',
  ),
};
