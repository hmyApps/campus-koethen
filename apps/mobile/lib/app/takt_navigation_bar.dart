// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimensions.dart';

/// One entry of the bottom bar.
@immutable
class TaktDestination {
  const TaktDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.tooltip,
  });

  final IconData icon;
  final IconData selectedIcon;

  /// The short name under the glyph.
  final String label;

  /// The full name — the tooltip, and the accessible name where it is longer
  /// than the label the bar has room for.
  final String tooltip;
}

/// The app's bottom navigation.
///
/// The supplied design uses a quiet off-white/dark surface and no selection pill.
/// Selection is carried by the Tabler filled glyph, the berry colour and the
/// stronger label weight, while semantics expose the selected state as well.
class TaktNavigationBar extends StatelessWidget {
  const TaktNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.semanticLabel,
    super.key,
  });

  final List<TaktDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Accessible name of the bar as a whole.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final int count = destinations.length;
    final _BarLayout layout = _BarLayout.of(context);

    final MaterialLocalizations material = MaterialLocalizations.of(context);

    return Semantics(
      label: semanticLabel,
      container: true,
      explicitChildNodes: true,
      child: Material(
        color: colors.surface,
        shape: Border(
          top: BorderSide(color: colors.outline, width: AppSizes.hairline),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: layout.height,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < count; i++)
                  Expanded(
                    child: _Tab(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      showLabel: layout.showLabels,
                      positionLabel: material.tabLabel(
                        tabIndex: i + 1,
                        tabCount: count,
                      ),
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.destination,
    required this.selected,
    required this.showLabel,
    required this.positionLabel,
    required this.onTap,
  });

  final TaktDestination destination;
  final bool selected;
  final bool showLabel;

  /// "Tab 2 of 5", in the platform's own words.
  final String positionLabel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color ink = selected ? colors.primary : colors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: '${destination.tooltip}, $positionLabel',
      // excludeSemantics drops the InkWell's own tap action along with its
      // child nodes, so the merged node has to carry the action itself.
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: destination.tooltip,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: AppSizes.icon,
                  color: ink,
                ),
                if (showLabel) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(
                      color: ink,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Smallest the navigation bar may ever be, so touch targets stay >= 48 dp.
const double kNavigationBarHeight = AppSizes.minTouchTarget + AppSpacing.md;

/// Tallest the bar may grow before it starts owning the screen.
const double _maxNavigationBarHeight = 96;

/// What the bar looks like at the reader's text size.
///
/// A fixed height was a bug: at a doubled text size the label no longer fit
/// under the glyph and the row overflowed. The bar measures itself from what it
/// actually contains — glyph, gap, one scaled line of label, and the padding
/// around them.
///
/// Past [_maxNavigationBarHeight] the **label** is dropped rather than the bar
/// being allowed to eat the screen or the text being shrunk back below the size
/// the reader asked for. Nothing is lost: the glyph and the tooltip still say
/// which tab this is, and the accessible name never was the label — it is the
/// module's full title.
@immutable
class _BarLayout {
  const _BarLayout({required this.height, required this.showLabels});

  final double height;
  final bool showLabels;

  static const double _labelSize = 11.5;
  static const double _labelLineHeight = 1.2;

  /// One logical pixel of slack for how the engine rounds a laid-out line.
  ///
  /// `fontSize × height` is the line box the style asks for; what the text
  /// painter returns can be a fraction taller. Without this the bar overflowed
  /// by four tenths of a pixel at some scales — invisible, and still a red
  /// assertion in every widget test that renders the shell.
  static const double _rounding = 1;

  factory _BarLayout.of(BuildContext context) {
    final double label =
        MediaQuery.textScalerOf(context).scale(_labelSize) * _labelLineHeight;
    final double withLabel =
        AppSizes.icon + AppSpacing.xxs + label + 2 * AppSpacing.sm + _rounding;
    if (withLabel <= _maxNavigationBarHeight) {
      return _BarLayout(
        height: withLabel.clamp(kNavigationBarHeight, _maxNavigationBarHeight),
        showLabels: true,
      );
    }
    return const _BarLayout(height: kNavigationBarHeight, showLabels: false);
  }
}
