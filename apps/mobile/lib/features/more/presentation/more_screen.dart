// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../app/app_routes.dart';
import '../../../app/navigation_config.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/l10n.dart';

/// The "Mehr" hub: everything the bottom bar has no room for.
///
/// The list is **derived** from the module catalogue, grouped by the category
/// each module declares. That is what makes the bar safe to configure:
/// whichever four modules a user pins, every other one turns up here under its
/// own heading. A hand-written list looks identical on a default install and
/// quietly strands whatever nobody thought to add.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final NavigationConfig navigation = ref.watch(
      settingsProvider.select((AppSettings s) => s.navigation),
    );
    final List<MoreCategoryEntry> entries = navigation.moreEntries;

    return ScreenScaffold(
      title: l10n.moreTitle,
      actions: <Widget>[
        IconButton(
          tooltip: l10n.moreSettings,
          onPressed: () => GoRouter.of(context).push(AppRoutes.settings),
          icon: const Icon(AppIcons.settings_outlined),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: <Widget>[
          for (final MoreCategoryEntry entry in entries) ...<Widget>[
            SectionHeader(label: entry.category.label(l10n)),
            for (final AppModule module in entry.modules)
              _ModuleRow(module: module, l10n: l10n),
          ],
        ],
      ),
    );
  }
}

/// One module: its glyph in a drawn box, its name, and what it is for.
///
/// The box around the glyph is the same hairline the cards use, so a list of
/// modules reads as a set of things rather than as a column of loose icons.
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.module, required this.l10n});

  final AppModule module;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final AppMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final bool disabled = module.isTemporarilyUnavailable;
    final String? subtitle = disabled
        ? l10n.moreModuleTemporarilyUnavailable
        : module.subtitle(l10n);
    final double contentOpacity = disabled ? 0.45 : 1;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: subtitle == null
          ? module.title(l10n)
          : '${module.title(l10n)}. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        // Pushed rather than switched to: a module opened from here belongs to
        // this stack, which is what keeps "Mehr" highlighted while it is open.
        onTap: disabled ? null : () => GoRouter.of(context).push(module.route),
        child: Opacity(
          opacity: contentOpacity,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.screenPadding,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: AppSizes.minTouchTarget - AppSpacing.sm,
                  height: AppSizes.minTouchTarget - AppSpacing.sm,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: colors.outline.withValues(alpha: 0.36),
                      width: AppSizes.hairline,
                    ),
                  ),
                  child: Icon(
                    module.icon,
                    size: AppSizes.iconSmall,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(module.title(l10n), style: text.titleMedium),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(subtitle, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (!disabled)
                  Icon(
                    AppIcons.chevron_right,
                    size: AppSizes.icon,
                    color: colors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
