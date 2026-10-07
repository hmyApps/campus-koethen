// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/calendar_palette.dart';
import '../../../l10n/l10n.dart';
import '../application/calendar_color_preferences.dart';

class CalendarColorTile extends ConsumerWidget {
  const CalendarColorTile({
    required this.styleKey,
    required this.label,
    this.defaultArgb,
    super.key,
  });

  final String styleKey;
  final String label;
  final int? defaultArgb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? override = ref
        .watch(calendarColorPreferencesProvider)
        .overrideFor(styleKey);
    final Color dot = Color(
      override ??
          defaultArgb ??
          Theme.of(context).colorScheme.primary.toARGB32(),
    );
    return ListTile(
      leading: Container(
        width: AppSizes.icon,
        height: AppSizes.icon,
        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
      ),
      title: Text(context.l10n.calendarColorTitle),
      subtitle: Text(label),
      trailing: const Icon(AppIcons.chevron_right),
      onTap: () =>
          showCalendarColorPicker(context, styleKey: styleKey, label: label),
    );
  }
}

Future<void> showCalendarColorPicker(
  BuildContext context, {
  required String styleKey,
  required String label,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => _CalendarColorPicker(styleKey: styleKey, label: label),
);

class _CalendarColorPicker extends ConsumerWidget {
  const _CalendarColorPicker({required this.styleKey, required this.label});

  final String styleKey;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final int? selected = ref
        .watch(calendarColorPreferencesProvider)
        .overrideFor(styleKey);
    Future<void> select(int? color) async {
      await ref
          .read(calendarColorPreferencesProvider.notifier)
          .setColor(styleKey, color);
      if (context.mounted) Navigator.of(context).pop();
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                l10n.calendarColorFor(label),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AppIcons.restart_alt),
              title: Text(l10n.calendarColorDefault),
              trailing: selected == null ? const Icon(AppIcons.check) : null,
              onTap: () => select(null),
            ),
            for (final CalendarPalette option in CalendarPalette.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: AppSizes.icon,
                  height: AppSizes.icon,
                  decoration: BoxDecoration(
                    color: Color(option.argb),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(_paletteLabel(l10n, option)),
                trailing: selected == option.argb
                    ? const Icon(AppIcons.check)
                    : null,
                onTap: () => select(option.argb),
              ),
          ],
        ),
      ),
    );
  }
}

String _paletteLabel(AppLocalizations l10n, CalendarPalette option) =>
    switch (option) {
      CalendarPalette.grey => l10n.calendarColorGrey,
      CalendarPalette.yellow => l10n.calendarColorYellow,
      CalendarPalette.blue => l10n.calendarColorBlue,
      CalendarPalette.green => l10n.calendarColorGreen,
      CalendarPalette.pink => l10n.calendarColorPink,
      CalendarPalette.purple => l10n.calendarColorPurple,
      CalendarPalette.orange => l10n.calendarColorOrange,
      CalendarPalette.teal => l10n.calendarColorTeal,
    };
