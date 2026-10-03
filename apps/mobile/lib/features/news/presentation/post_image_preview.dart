// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/remote_image.dart';
import '../../../l10n/l10n.dart';
import '../data/news_models.dart';

/// Square post preview. The full view fetches the same original media URL
/// without the preview's reduced in-memory decode size.
class PostImagePreview extends StatelessWidget {
  const PostImagePreview({required this.image, super.key});

  final NewsImage image;

  @override
  Widget build(BuildContext context) {
    final String? url = ApiConfig.resolveMediaUrl(image.url);
    if (url == null) return const SizedBox.shrink();

    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final String? description = image.alternativeText;
    final String semanticLabel = description == null || description.isEmpty
        ? l10n.newsOpenImage
        : l10n.newsOpenImageWithDescription(description);

    return Tooltip(
      message: l10n.newsOpenImage,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Stack(
          children: <Widget>[
            RemoteImage(
              url: image.url,
              alternativeText: description,
              aspectRatio: 1,
            ),
            PositionedDirectional(
              end: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: SizedBox.square(
                  dimension: AppSizes.minTouchTarget,
                  child: Icon(
                    AppIcons.fullscreen,
                    color: colors.onPrimary,
                    size: AppSizes.icon,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: () => _showOriginalImage(
                    context,
                    url,
                    l10n,
                    alternativeText: description,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showOriginalImage(
  BuildContext context,
  String url,
  AppLocalizations l10n, {
  String? alternativeText,
}) {
  final AppColors colors = context.colors;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.newsCloseImage,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.92),
    pageBuilder: (BuildContext dialogContext, _, _) => Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CachedNetworkImage(
                    imageUrl: url,
                    imageBuilder: (BuildContext _, ImageProvider provider) =>
                        Image(
                          image: provider,
                          fit: BoxFit.contain,
                          semanticLabel: alternativeText,
                          excludeFromSemantics:
                              alternativeText == null ||
                              alternativeText.isEmpty,
                        ),
                    placeholder: (BuildContext _, String _) =>
                        CircularProgressIndicator(color: colors.surface),
                    errorWidget: (BuildContext _, String _, Object _) =>
                        Material(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  AppIcons.broken_image_outlined,
                                  color: colors.onSurface,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  l10n.newsImageUnavailable,
                                  style: TextStyle(color: colors.onSurface),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: AppSpacing.md,
              end: AppSpacing.md,
              child: IconButton.filled(
                tooltip: l10n.newsCloseImage,
                constraints: const BoxConstraints(
                  minWidth: AppSizes.minTouchTarget,
                  minHeight: AppSizes.minTouchTarget,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(AppIcons.close),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
