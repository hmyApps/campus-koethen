// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../campusmap/application/campus_map_providers.dart';
import '../../campusmap/domain/map_catalog.dart';
import '../../campusmap/domain/room.dart';
import '../../campusmap/domain/room_mention.dart';
import '../../campusmap/presentation/room_link.dart';
import '../../events/application/event_providers.dart';
import '../../events/data/event_posts_repository.dart';
import '../../news/data/news_models.dart';
import '../../news/presentation/article_block.dart';
import '../../timetable/presentation/timetable_entry_card.dart';
import '../domain/calendar_entry.dart';
import '../domain/calendar_entry_details.dart';
import '../domain/entry_rooms.dart';

/// Opens the detail view of one calendar entry.
///
/// A sheet rather than a screen: the entry is a detail *of* the day being
/// looked at, and coming back to the same day, the same week and the same
/// scroll position is the whole point.
Future<void> showCalendarEntrySheet(
  BuildContext context,
  CalendarEntry entry,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (BuildContext context) => _CalendarEntryPopup(entry: entry),
);

/// Selects the richer post popup only for a bookmarked post event.
///
/// Saved calendar occurrences use the same `savedEvents` calendar source, so
/// the source enum alone is insufficient. Their stable ids preserve the
/// original `post:<slug>` / `calendar:<id>` event reference and keep the two
/// cases unambiguous.
class _CalendarEntryPopup extends ConsumerWidget {
  const _CalendarEntryPopup({required this.entry});

  final CalendarEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? postSlug = _savedPostSlug(entry);
    if (postSlug == null) return CalendarEntrySheet(entry: entry);

    final AsyncValue<EventPostsResult> posts = ref.watch(
      eventPostsOverviewProvider,
    );
    final NewsArticle? article = posts.value?.articles
        .where((NewsArticle article) => article.slug == postSlug)
        .firstOrNull;
    if (article != null) {
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: ArticleBlock(article: article, showFullContent: true),
        ),
      );
    }

    if (posts.isLoading) {
      return const SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.minTouchTarget * 3,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Offline, orphaned or outside the server's event window: the saved
    // snapshot still has its date, title and source and remains useful.
    return CalendarEntrySheet(entry: entry);
  }
}

String? _savedPostSlug(CalendarEntry entry) {
  if (entry.source != CalendarSource.savedEvents) return null;
  const String prefix = 'savedEvent:post:';
  if (!entry.id.startsWith(prefix)) return null;
  final String slug = entry.id.substring(prefix.length);
  return slug.isEmpty ? null : slug;
}

/// Everything one calendar entry knows, including a way to its room.
///
/// The agenda shows a line per entry; this is where the rest of it lives —
/// teachers, groups, the note, the calendar it came from, and the room. Which
/// text may become a room link is decided by [CalendarEntryDetails], not here:
/// a timetable's room field is a room, an event description is prose.
class CalendarEntrySheet extends ConsumerWidget {
  const CalendarEntrySheet({required this.entry, super.key});

  final CalendarEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String locale = Localizations.localeOf(context).languageCode;

    final String sourceLabel = switch (entry.source) {
      CalendarSource.moodle => l10n.calendarSourceMoodle,
      CalendarSource.timetable => l10n.calendarSourceTimetable,
      CalendarSource.canteenFavourite =>
        entry.sourceLabel ?? l10n.calendarSourceCanteenFavourite,
      CalendarSource.publicCalendar ||
      CalendarSource.postEvent ||
      CalendarSource.savedEvents =>
        entry.sourceLabel ?? l10n.calendarSourcePublic,
    };
    final IconData sourceIcon = switch (entry.source) {
      CalendarSource.moodle => AppIcons.assignment_outlined,
      CalendarSource.timetable => AppIcons.schedule_outlined,
      CalendarSource.canteenFavourite => AppIcons.soup,
      CalendarSource.publicCalendar ||
      CalendarSource.postEvent ||
      CalendarSource.savedEvents => AppIcons.public_outlined,
    };

    final RoomResolver? resolver = entryMayNameRoom(entry)
        ? ref.watch(roomResolverProvider)
        : null;
    final List<Room> rooms = resolver == null
        ? const <Room>[]
        : roomsForEntry(resolver, entry);
    final MapCatalog? catalog = entry.details is TimetableCalendarDetails
        ? ref.watch(mapCatalogProvider).value
        : null;
    final Set<String> unmappedTimetableRooms = switch (entry.details) {
      TimetableCalendarDetails(:final List<String> rooms) => rooms.where((
        String designation,
      ) {
        final Room? room = resolver?.resolveDesignation(designation);
        return room == null || catalog?.geometryFor(room.roomKey) == null;
      }).toSet(),
      _ => const <String>{},
    };

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  entry.title.isEmpty ? sourceLabel : entry.title,
                  style: text.titleLarge?.copyWith(
                    decoration: entry.isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              if (entry.isCancelled) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                // Icon and words, never the strikethrough alone.
                Row(
                  children: <Widget>[
                    Icon(
                      AppIcons.event_busy_outlined,
                      size: AppSizes.icon,
                      color: colors.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      l10n.timetableStatusCancelled,
                      style: text.titleSmall?.copyWith(color: colors.error),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              _DetailRow(
                icon: AppIcons.event_outlined,
                label: l10n.calendarDetailWhen,
                values: <String>[
                  // `entry.day`, not `start.toLocal()`. An all-day entry is a
                  // calendar DATE encoded as UTC midnight so no device zone
                  // can shift it; converting it to local time moves it a day
                  // in every zone behind UTC, and the sheet then contradicted
                  // the grid that placed the entry.
                  AppDateFormats.weekdayDate(entry.day, locale),
                  _timeLabel(l10n, locale),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _DetailRow(
                icon: sourceIcon,
                label: l10n.calendarDetailSource,
                values: <String>[sourceLabel],
              ),

              ..._sourceRows(context, l10n, unmappedTimetableRooms),

              if (rooms.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(l10n.contactRoomsLabel, style: text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                for (final Room room in rooms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: RoomLinkButton(room: RoomLinkTarget.fromRoom(room)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _timeLabel(AppLocalizations l10n, String locale) {
    if (entry.allDay) return l10n.calendarWeekAllDay;
    final String start = AppDateFormats.time(entry.start.toLocal(), locale);
    if (entry.end == null) return start;
    return l10n.timetableTimeRange(
      start,
      AppDateFormats.time(entry.end!.toLocal(), locale),
    );
  }

  /// The rows only one kind of entry has.
  List<Widget> _sourceRows(
    BuildContext context,
    AppLocalizations l10n,
    Set<String> unmappedTimetableRooms,
  ) {
    final TextTheme text = Theme.of(context).textTheme;

    return switch (entry.details) {
      TimetableCalendarDetails(
        :final List<String> teachers,
        :final List<String> rooms,
        :final List<String> groups,
        :final String? note,
        :final String? lessonInfo,
        :final type,
      ) =>
        <Widget>[
          const SizedBox(height: AppSpacing.sm),
          _DetailRow(
            icon: AppIcons.category_outlined,
            label: l10n.timetableTypeLabel,
            values: <String>[timetableTypeLabel(l10n, type)],
          ),
          if (teachers.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _DetailRow(
              icon: AppIcons.person_outline,
              label: l10n.timetableTeachersLabel,
              values: teachers,
            ),
          ],
          if (rooms.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _DetailRow(
              icon: AppIcons.meeting_room_outlined,
              label: l10n.timetableRoomsLabel,
              values: rooms,
              searchForValues: unmappedTimetableRooms,
            ),
          ],
          if (groups.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _DetailRow(
              icon: AppIcons.groups_outlined,
              label: l10n.timetableGroupsLabel,
              values: groups,
            ),
          ],
          if (note != null && note.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(note, style: text.bodyMedium),
          ],
          if (lessonInfo != null && lessonInfo.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _DetailRow(
              icon: AppIcons.info_outline,
              label: l10n.timetableLessonInfoLabel,
              values: <String>[lessonInfo],
            ),
          ],
        ],
      MoodleCalendarDetails(:final String? courseName) => <Widget>[
        if (courseName != null && courseName.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _DetailRow(
            icon: AppIcons.menu_book_outlined,
            label: l10n.moodleCourseLabel,
            values: <String>[courseName],
          ),
        ],
      ],
      // Nothing beyond the flattened fields: the top "Quelle" row above
      // already names the canteen via `entry.sourceLabel`.
      CanteenFavouriteMealCalendarDetails() => const <Widget>[],
      PublicCalendarDetails(
        :final String? location,
        :final String? description,
      ) =>
        <Widget>[
          if (location != null && location.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _DetailRow(
              icon: AppIcons.place_outlined,
              label: l10n.calendarDetailLocation,
              values: <String>[location],
            ),
          ],
          if (description != null && description.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(description, style: text.bodyMedium),
          ],
        ],
      // An entry built before the details existed, or from a source that has
      // none: the flattened fields still say everything the agenda showed.
      null => <Widget>[
        if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(entry.subtitle!, style: text.bodyMedium),
        ],
        if (entry.location != null && entry.location!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _DetailRow(
            icon: AppIcons.place_outlined,
            label: l10n.calendarDetailLocation,
            values: <String>[entry.location!],
          ),
        ],
      ],
    };
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.values,
    this.searchForValues = const <String>{},
  });

  final IconData icon;
  final String label;
  final List<String> values;
  final Set<String> searchForValues;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: AppSizes.icon, color: colors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
              for (final String value in values)
                if (searchForValues.contains(value))
                  UnmappedRoomSearchRow(
                    label: value,
                    textStyle: text.bodyMedium,
                    closeSheet: true,
                  )
                else
                  Text(value, style: text.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
