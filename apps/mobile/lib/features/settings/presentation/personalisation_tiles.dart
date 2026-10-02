// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/appearance_preferences.dart';
import '../../../l10n/l10n.dart';

/// Selects how light and dark palettes follow the operating system.
class BrightnessPreferenceTile extends ConsumerWidget {
  const BrightnessPreferenceTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final BrightnessPreference selected = ref.watch(
      settingsProvider.select(
        (AppSettings settings) => settings.brightnessPreference,
      ),
    );
    String label(BrightnessPreference preference) => switch (preference) {
      BrightnessPreference.system => l10n.settingsThemeSystem,
      BrightnessPreference.light => l10n.settingsThemeLight,
      BrightnessPreference.dark => l10n.settingsThemeDark,
    };

    return _AppearanceChoiceGroup<BrightnessPreference>(
      title: l10n.settingsTheme,
      selected: selected,
      values: BrightnessPreference.values,
      label: label,
      onChanged: (BrightnessPreference preference) {
        // This changes MaterialApp itself. Let RadioGroup finish dispatching
        // its notification before inherited theme dependencies move.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ref
              .read(settingsProvider.notifier)
              .setBrightnessPreference(preference);
        });
      },
    );
  }
}

/// Selects the accent independently of light/dark mode.
class AccentSchemeTile extends ConsumerWidget {
  const AccentSchemeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AccentScheme selected = ref.watch(
      settingsProvider.select((AppSettings settings) => settings.accentScheme),
    );
    String label(AccentScheme scheme) => switch (scheme) {
      AccentScheme.pink => l10n.settingsAccentPink,
      AccentScheme.green => l10n.settingsAccentGreen,
      AccentScheme.blue => l10n.settingsAccentBlue,
      AccentScheme.violet => l10n.settingsAccentViolet,
      AccentScheme.amber => l10n.settingsAccentAmber,
    };
    final Brightness brightness = Theme.of(context).brightness;

    return _AppearanceChoiceGroup<AccentScheme>(
      title: l10n.settingsAccent,
      selected: selected,
      values: AccentScheme.values,
      label: label,
      marker: (AccentScheme scheme) => ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.forScheme(scheme, brightness).primary,
            shape: BoxShape.circle,
            border: Border.all(color: context.colors.textPrimary),
          ),
          child: const SizedBox.square(dimension: 24),
        ),
      ),
      onChanged: (AccentScheme scheme) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ref.read(settingsProvider.notifier).setAccentScheme(scheme);
        });
      },
    );
  }
}

class _AppearanceChoiceGroup<T> extends StatelessWidget {
  const _AppearanceChoiceGroup({
    required this.title,
    required this.selected,
    required this.values,
    required this.label,
    required this.onChanged,
    this.marker,
  });

  final String title;
  final T selected;
  final Iterable<T> values;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;
  final Widget Function(T value)? marker;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.metrics.screenPadding,
        ),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      RadioGroup<T>(
        groupValue: selected,
        onChanged: (T? value) {
          if (value != null) onChanged(value);
        },
        child: Column(
          children: <Widget>[
            for (final T value in values)
              RadioListTile<T>.adaptive(
                value: value,
                title: Text(label(value)),
                secondary: marker?.call(value),
              ),
          ],
        ),
      ),
    ],
  );
}

/// The local reduced-motion switch.
///
/// Its subtitle says outright that the system setting applies anyway, so
/// leaving this off is not mistaken for "animate regardless".
class ReducedMotionTile extends ConsumerWidget {
  const ReducedMotionTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool enabled = ref.watch(
      settingsProvider.select((AppSettings s) => s.reducedMotion),
    );

    return SwitchListTile(
      secondary: const Icon(AppIcons.motion_photos_off_outlined),
      title: Text(l10n.settingsReducedMotion),
      subtitle: Text(l10n.settingsReducedMotionSubtitle),
      value: enabled,
      onChanged: (bool value) =>
          ref.read(settingsProvider.notifier).setReducedMotion(value),
    );
  }
}
