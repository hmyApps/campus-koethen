// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// Severity of a [StatusBanner].
enum StatusTone { info, warning, positive }

/// An inline status hint: a note pinned to the page.
///
/// The banner always sits on `surface` — that is the pairing the contrast test
/// asserts — and always combines an icon **and** text with its accent colour,
/// so no state is communicated through colour alone.
///
/// The tone is carried three times over: by the colour of the beam, by the
/// weight of the beam (it is the heaviest stroke in the system) and by the
/// glyph. A reader who cannot tell the colours apart still gets two of the
/// three, and a greyscale screenshot still shows the bar.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    required this.title,
    this.message,
    this.tone = StatusTone.info,
    this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final StatusTone tone;
  final IconData? icon;

  /// What to do about it, where there is something to do.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = switch (tone) {
      StatusTone.info => colors.onSurfaceVariant,
      StatusTone.warning => colors.error,
      StatusTone.positive => colors.success,
    };
    final IconData effectiveIcon =
        icon ??
        switch (tone) {
          StatusTone.info => AppIcons.info_outline,
          StatusTone.warning => AppIcons.warning_amber_outlined,
          StatusTone.positive => AppIcons.check_circle_outline,
        };
    final BorderRadius radius = BorderRadius.circular(10);
    final double outlineWidth = colors.highContrast
        ? AppSizes.rule
        : AppSizes.hairline;
    final double beamWidth = colors.highContrast
        ? AppSizes.beam + AppSizes.rule
        : AppSizes.beam;

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.outline, width: outlineWidth),
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(effectiveIcon, color: accent, size: AppSizes.icon),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // Title and message read as one sentence. The action
                          // stays outside this node: merged into the label it
                          // would be neither focusable nor pressable, and a
                          // banner whose only way forward is a button a screen
                          // reader cannot reach is a dead end.
                          Semantics(
                            label: message == null || message!.isEmpty
                                ? title
                                : '$title. $message',
                            excludeSemantics: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  title,
                                  style: text.titleSmall?.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                                if (message != null &&
                                    message!.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    message!,
                                    style: text.bodySmall?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (action != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: action!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: beamWidth,
                child: ColoredBox(color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
