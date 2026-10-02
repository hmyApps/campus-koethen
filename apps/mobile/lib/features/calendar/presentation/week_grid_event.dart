// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';

import '../../../core/theme/app_dimensions.dart';
import '../domain/week_layout.dart';

/// Positions a truthful-duration event card inside an independent 48 dp
/// pointer, keyboard and semantics target.
class WeekGridEventPosition extends StatelessWidget {
  const WeekGridEventPosition({
    required this.item,
    required this.semanticLabel,
    required this.gridStartMinute,
    required this.pixelsPerMinute,
    required this.gridExtent,
    required this.left,
    required this.width,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final PlacedEntry item;
  final String semanticLabel;
  final int gridStartMinute;
  final double pixelsPerMinute;
  final double gridExtent;
  final double left;
  final double width;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final GridHitBounds bounds = WeekLayout.hitBoundsFor(
      item,
      gridStartMinute: gridStartMinute,
      pixelsPerMinute: pixelsPerMinute,
      minimumExtent: AppSizes.minTouchTarget,
      gridExtent: gridExtent,
    );

    return Positioned(
      top: bounds.top,
      height: bounds.height,
      left: left,
      width: width,
      child: Semantics(
        label: semanticLabel,
        excludeSemantics: true,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  top: bounds.visualOffset,
                  left: 0,
                  right: 0,
                  height: bounds.visualHeight,
                  child: ExcludeFocus(child: ExcludeSemantics(child: child)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
