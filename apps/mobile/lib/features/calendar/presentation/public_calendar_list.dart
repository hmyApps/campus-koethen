// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/links/safe_link_launcher.dart';
import '../../../core/network/loaded.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/hex_color.dart';
import '../../../core/widgets/translation_fallback_notice.dart';
import '../../../l10n/l10n.dart';
import '../application/public_calendar_providers.dart';
import '../application/public_calendar_selection.dart';
import '../application/calendar_color_preferences.dart';
import '../domain/public_calendar.dart';
import 'calendar_color_picker.dart';

/// The public calendars with their individual switches and Google actions.
///
/// One widget for both places that offer the choice — the calendar's own
/// "Events" sheet and the full-screen "manage calendars" reached from the
/// onboarding. Both write the **same** [publicCalendarSelectionProvider]; a
/// second notion of "visible" would leave the reader with two switches for one
/// thing and no way to tell which of them won.
class PublicCalendarList extends ConsumerWidget {
  const PublicCalendarList({this.shrinkWrap = false, super.key});

  /// Set inside a bottom sheet, where the list sizes itself to its content.
  final bool shrinkWrap;

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final LinkLaunchResult result = await ref
        .read(linkLauncherProvider)
        .open(url);
    if (result != LinkLaunchResult.opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.calendarGoogleLinkFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Loaded<List<PublicCalendar>>> catalog = ref.watch(
      publicCalendarsCatalogProvider,
    );
    final PublicCalendarSelectionState selection = ref.watch(
      publicCalendarSelectionProvider,
    );

    return catalog.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          l10n.calendarPublicUnavailable,
          textAlign: TextAlign.center,
        ),
      ),
      data: (Loaded<List<PublicCalendar>> loaded) {
        final List<PublicCalendar> calendars = loaded.value;
        if (calendars.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l10n.calendarNoPublicCalendars,
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount:
              calendars.length + (loaded.meta.translationFallback ? 1 : 0),
          itemBuilder: (BuildContext context, int index) {
            if (loaded.meta.translationFallback && index == 0) {
              return const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: TranslationFallbackNotice(),
              );
            }
            final PublicCalendar calendar =
                calendars[index - (loaded.meta.translationFallback ? 1 : 0)];
            return PublicCalendarTile(
              calendar: calendar,
              selected: selection.isSelected(calendar.slug),
              onChanged: (bool value) => ref
                  .read(publicCalendarSelectionProvider.notifier)
                  .setSelected(calendar.slug, selected: value),
              onOpen: () => _open(context, ref, calendar.googleOpenUrl),
            );
          },
        );
      },
    );
  }
}

/// One public calendar: its name, its colour as decoration only, a switch and
/// the safe link into Google Calendar.
class PublicCalendarTile extends ConsumerWidget {
  const PublicCalendarTile({
    required this.calendar,
    required this.selected,
    required this.onChanged,
    required this.onOpen,
    super.key,
  });

  final PublicCalendar calendar;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final String styleKey = CalendarColorKeys.publicCalendar(calendar.slug);
    final int? override = ref
        .watch(calendarColorPreferencesProvider)
        .overrideFor(styleKey);
    final int? sourceArgb = parseHexColorArgb(calendar.colorHex);
    final Color dot = override == null
        ? (parseHexColor(calendar.colorHex) ?? context.colors.primary)
        : Color(override);
    final List<String> subtitleParts = <String>[
      if (calendar.dataStale) l10n.calendarDataStale,
      // The state in words, so the switch position is never the only carrier.
      selected ? l10n.calendarSourceVisible : l10n.calendarSourceHidden,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SwitchListTile.adaptive(
          secondary: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Colour is decorative; the name (title) carries the identity.
              Container(
                width: AppSizes.iconSmall,
                height: AppSizes.iconSmall,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(AppIcons.public_outlined),
            ],
          ),
          title: Text(calendar.name),
          subtitle: Text(subtitleParts.join(' · '), style: text.bodySmall),
          value: selected,
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () => showCalendarColorPicker(
                  context,
                  styleKey: styleKey,
                  label: calendar.name,
                ),
                icon: Icon(
                  AppIcons.edit_outlined,
                  color: Color(override ?? sourceArgb ?? dot.toARGB32()),
                ),
                label: Text(l10n.calendarColorTitle),
              ),
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(AppIcons.open_in_new),
                label: Text(l10n.calendarOpenInGoogle),
              ),
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }
}
