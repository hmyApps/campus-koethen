// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_metrics.dart';

/// A sheet of paper: the app's card.
///
/// White on warm paper in the light palette, a lighter surface in the dark one,
/// a hairline all the way round and no shadow anywhere. That is the entire
/// recipe, and it is centralised here so a card cannot pick up a fourth
/// variation of its own padding.
///
/// [live] is the one decoration a panel may carry: a marker edge down its
/// leading side, for the one card on a screen that is happening *now*. Callers
/// always pair it with a word — the marker never carries a state on its own.
class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding,
    this.onTap,
    this.live = false,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool live;

  /// Set where the panel is a single control and its contents would otherwise
  /// be announced as a heap of unrelated strings.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final AppMetrics metrics = context.metrics;
    final BorderRadius radius = BorderRadius.circular(metrics.cardRadius);

    final EdgeInsetsGeometry inset =
        padding ?? EdgeInsets.all(metrics.cardPadding);

    Widget content = Padding(
      // The marker edge is drawn over the panel, so a live panel owes its text
      // the width of the beam on top of its ordinary inset.
      padding: live
          ? inset.add(const EdgeInsetsDirectional.only(start: AppSizes.beam))
          : inset,
      child: child,
    );

    if (live) {
      // A positioned bar rather than a stretched row child: `Stack` takes its
      // size from the content and lets the beam grow to match, which a `Row`
      // with a stretched cross axis cannot do inside an unbounded column.
      content = Stack(
        children: <Widget>[
          content,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: AppSizes.beam,
            child: ColoredBox(color: colors.accent),
          ),
        ],
      );
    }

    // `Material` rather than `DecoratedBox`: ink is painted by the nearest
    // Material ancestor, so an opaque fill drawn *above* that ancestor hides
    // the ripple, the pressed highlight and — the one that matters — the
    // keyboard focus ring. Letting the Material carry the fill itself puts the
    // ink back on top of it. `clipBehavior` replaces the ClipRRect that used
    // to keep the marker edge inside the rounded corner.
    Widget panel = Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.outline, width: AppSizes.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: radius, child: content),
    );

    if (semanticLabel != null) {
      panel = Semantics(
        label: semanticLabel,
        button: onTap != null,
        // excludeSemantics drops the InkWell's tap action, so the merged node
        // carries it itself.
        onTap: onTap,
        excludeSemantics: true,
        child: panel,
      );
    }

    return panel;
  }
}
