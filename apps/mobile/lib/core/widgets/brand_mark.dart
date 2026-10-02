// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// Binding brand assets used by the app UI.
abstract final class BrandAssets {
  static const String icon = 'assets/branding/campus-koethen-icon.png';
  static const String logo = 'assets/branding/campus-koethen-logo.png';

  static const int iconPixelWidth = 1024;
  static const int logoPixelWidth = 1672;
  static const int logoPixelHeight = 941;
}

int _decodeWidth(
  BuildContext context,
  double logicalWidth,
  int sourcePixelWidth,
) {
  final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  return (logicalWidth * devicePixelRatio).ceil().clamp(1, sourcePixelWidth);
}

/// The binding Campus Köthen courtyard-and-meeting icon.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.appTitle,
      image: true,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: SizedBox.square(
          dimension: size,
          child: ColoredBox(
            color: AppColors.light.background,
            child: Padding(
              padding: EdgeInsets.all(size * 0.04),
              child: Image.asset(
                BrandAssets.icon,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                cacheWidth: _decodeWidth(
                  context,
                  size,
                  BrandAssets.iconPixelWidth,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The complete, binding Campus Köthen logo with its original wordmark.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({this.width = 300, super.key});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.appTitle,
      image: true,
      excludeSemantics: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: ColoredBox(
            color: AppColors.light.background,
            child: SizedBox(
              width: width,
              child: AspectRatio(
                aspectRatio:
                    BrandAssets.logoPixelWidth / BrandAssets.logoPixelHeight,
                child: Image.asset(
                  BrandAssets.logo,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  cacheWidth: _decodeWidth(
                    context,
                    width,
                    BrandAssets.logoPixelWidth,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
