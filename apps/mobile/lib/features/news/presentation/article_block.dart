// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/links/safe_link_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/content_blocks_view.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/remote_image.dart';
import '../../../l10n/l10n.dart';
import '../../events/domain/unified_event.dart';
import '../../events/presentation/event_save_button.dart';
import '../application/news_feed_ui_providers.dart';
import '../data/news_models.dart';
import '../domain/article_age.dart';
import '../domain/news_preview.dart';
import 'news_age_text.dart';

/// The tallest a banner may be drawn, as width divided by height.
///
/// Editors upload what they have — square press photos, portrait posters — and
/// a feed that honours every shape turns one article into a full screen before
/// its headline. Anything wider than this keeps its own proportions; anything
/// taller is cropped to it.
const double _maxBannerRatio = 16 / 9;

/// One article in the feed, drawn as its own card.
///
/// Every article sits in a [Panel] — a light, theme-matched border and no
/// shadow, per the app's one card recipe — so a reader scanning the feed can
/// tell at a glance where one piece ends and the next begins, rather than
/// having to read a hairline the way a page of running text does.
///
/// The block is **not** a button and carries no button semantics. There is no
/// article detail page: the list endpoint delivers the sanitised content of
/// every article, so a block expands in place instead of navigating — which
/// also means the feed never makes one request per visible article. The real
/// controls are the expand button, the links inside the rich text, and each
/// channel handle in the byline — the last of those is the one place this
/// block does navigate, to that channel's own profile screen.
///
class ArticleBlock extends ConsumerWidget {
  const ArticleBlock({
    required this.article,
    this.showFullContent = false,
    super.key,
  });

  final NewsArticle article;

  /// Shows the complete article without the feed's expand/collapse control.
  ///
  /// Used when the article already lives in a detail surface such as the
  /// calendar popup. It deliberately does not change the feed's persisted
  /// expansion state.
  final bool showFullContent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final String locale = Localizations.localeOf(context).languageCode;

    final bool expanded =
        showFullContent ||
        ref.watch(
          newsExpansionProvider.select(
            (Set<String> slugs) => slugs.contains(article.slug),
          ),
        );
    // One clock for the whole feed keeps "vor 3 min" honest while reading,
    // without a timer per block.
    final ArticleAge? age = articleAge(
      article.publishedAt,
      now: ref.watch(newsClockProvider),
    );

    void onToggle() =>
        ref.read(newsExpansionProvider.notifier).toggle(article.slug);

    return Semantics(
      // Announces the card's own open/closed state without swallowing the
      // headline, links and buttons underneath into one opaque label — those
      // stay individually reachable for a screen reader.
      toggled: expanded,
      container: true,
      child: Panel(
        padding: EdgeInsets.all(context.metrics.cardPadding),
        onTap: showFullContent ? null : onToggle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The line above the headline: who published it and when. Set small and
            // tracked so the headline below is unambiguously the loudest thing in
            // the block.
            _Byline(
              channels: article.channels,
              age: age,
              locale: locale,
              l10n: l10n,
            ),

            const SizedBox(height: AppSpacing.xs),
            // Every post carries exactly one mandatory tag now (the merged
            // Posts contract dropped the old multi-tag list), so the row
            // always renders — wrapped as a one-element list to keep
            // `_TagsRow` unchanged.
            _TagsRow(tags: <NewsTagRef>[article.tag], l10n: l10n),
            const SizedBox(height: AppSpacing.sm),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(article.title, style: text.headlineMedium),
                  ),
                ),
                if (article.isEventPost)
                  EventSaveButton(event: postToUnifiedEvent(article)),
              ],
            ),

            // The banner follows the headline rather than leading it. A
            // reader scanning a feed reads headlines; a photo above every one
            // of them pushes three articles off the screen for no gain.
            if (article.heroImage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              RemoteImage(
                url: article.heroImage!.url,
                alternativeText: article.heroImage!.alternativeText,
                aspectRatio: math.max(
                  article.heroImage!.aspectRatio ?? _maxBannerRatio,
                  _maxBannerRatio,
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            _ArticleBody(
              article: article,
              expanded: expanded,
              onToggle: showFullContent ? null : onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

/// Channels on the left, age on the right, both on one tracked line.
///
/// Each channel is its own tappable link rather than one joined string: an
/// article in several channels lets a reader open any one of them, not just
/// the article's own combined byline.
class _Byline extends StatelessWidget {
  const _Byline({
    required this.channels,
    required this.age,
    required this.locale,
    required this.l10n,
  });

  final List<NewsChannelRef> channels;
  final ArticleAge? age;
  final String locale;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final AppTypography type = context.type;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (channels.isNotEmpty)
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.start,
              children: <Widget>[
                for (final NewsChannelRef channel in channels)
                  _ChannelLink(channel: channel, l10n: l10n),
              ],
            ),
          )
        else
          const Spacer(),
        if (age != null) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          // The timestamp is data, so it is set in the data face. It also
          // stops the age from being mistaken for another channel handle.
          Text(
            newsAgeText(l10n, locale, age!),
            textAlign: TextAlign.end,
            style: type.dataSmall,
          ),
        ],
      ],
    );
  }
}

/// One channel handle, as a real link to that channel's profile screen.
///
/// Shows the editorial channel name exactly as supplied by the API.
class _ChannelLink extends StatelessWidget {
  const _ChannelLink({required this.channel, required this.l10n});

  final NewsChannelRef channel;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;

    return Semantics(
      link: true,
      label: l10n.newsChannelLinkSemanticLabel(channel.name),
      excludeSemantics: true,
      child: TextButton(
        onPressed: () => context.pushNamed(
          AppRoutes.newsChannelName,
          pathParameters: <String, String>{'slug': channel.slug},
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSizes.minTouchTarget),
          padding: EdgeInsets.zero,
          alignment: AlignmentDirectional.topStart,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: Text(
          channel.name,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.primary),
        ),
      ),
    );
  }
}

/// An article's active tags, drawn as small, contrast-checked pills that wrap
/// onto their own lines rather than assuming any fixed count.
///
/// Purely informational — a tag here is not a link, unlike a channel handle
/// in the byline above it. The filter to narrow the whole feed by a tag
/// lives in the filter sheet, not on the card.
class _TagsRow extends StatelessWidget {
  const _TagsRow({required this.tags, required this.l10n});

  final List<NewsTagRef> tags;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        for (final NewsTagRef tag in tags)
          Semantics(
            label: l10n.newsTagChipSemanticLabel(tag.name),
            excludeSemantics: true,
            child: Chip(
              // A theme-matched, always-contrast pill — never the article's or
              // channel's own colour hint, which carries no contrast guarantee.
              label: Text(tag.name),
              labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
              backgroundColor: scheme.secondaryContainer,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 0,
              ),
            ),
          ),
      ],
    );
  }
}

/// The article itself: five lines, or all of it.
class _ArticleBody extends ConsumerWidget {
  const _ArticleBody({
    required this.article,
    required this.expanded,
    required this.onToggle,
  });

  final NewsArticle article;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextStyle style = Theme.of(context).textTheme.bodyLarge!;

    if (article.content.isEmpty) {
      return Text(
        l10n.newsNoContent,
        style: style.copyWith(color: context.colors.textSecondary),
      );
    }

    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The real rich text: working links, images, everything the preview
          // cannot show.
          ContentBlocksView(blocks: article.content),
          if (article.sourceName != null || article.sourceUrl != null)
            _SourceLink(article: article),
          if (onToggle != null)
            _ToggleButton(
              label: l10n.newsShowLess,
              icon: AppIcons.keyboard_arrow_up,
              onPressed: onToggle!,
            ),
        ],
      );
    }

    final String preview = newsPreviewText(article.content);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Only the layout knows whether five lines were enough, so the question
        // is answered at the width the text actually gets and at the reader's
        // own text size.
        final TextPainter painter = TextPainter(
          text: TextSpan(text: preview, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: kNewsPreviewLines,
        )..layout(maxWidth: constraints.maxWidth);
        final bool overflows = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              preview,
              style: style,
              maxLines: kNewsPreviewLines,
              overflow: TextOverflow.ellipsis,
            ),
            // Offered only when there is genuinely something behind it.
            if (onToggle != null &&
                hasMoreToShow(
                  blocks: article.content,
                  textOverflows: overflows,
                ))
              _ToggleButton(
                label: l10n.newsShowMore,
                icon: AppIcons.keyboard_arrow_down,
                onPressed: onToggle!,
              ),
          ],
        );
      },
    );
  }
}

/// The article's attribution and, if there is one, a link to the original.
///
/// Editorial pieces summarise a source rather than copying it, so the way back
/// to that source has to stay reachable now that the block is the whole
/// article.
class _SourceLink extends ConsumerWidget {
  const _SourceLink({required this.article});

  final NewsArticle article;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: AppSpacing.md),
        if (article.sourceName != null)
          Text(
            l10n.newsSourceLabel(article.sourceName!),
            style: text.bodySmall,
          ),
        if (article.sourceUrl != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _open(context, ref, article.sourceUrl!, l10n),
              icon: const Icon(AppIcons.open_in_new, size: AppSizes.iconSmall),
              label: Text(l10n.newsOpenSource),
            ),
          ),
      ],
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String url,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final LinkLaunchResult result = await ref
        .read(linkLauncherProvider)
        .open(url);
    if (result == LinkLaunchResult.opened) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result == LinkLaunchResult.blocked
              ? l10n.errorLinkBlocked
              : l10n.errorLinkNotOpened,
        ),
      ),
    );
  }
}

/// "Weiterlesen" — a real button with a glyph that says which way it goes.
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppSizes.iconSmall),
        label: Text(label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        ),
      ),
    ),
  );
}
