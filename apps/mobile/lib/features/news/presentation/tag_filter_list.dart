// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/loaded.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/news_providers.dart';
import '../application/tag_filter.dart';
import '../data/news_models.dart';

/// The feed's tag filter: "Alle" plus every active tag, single-select.
///
/// Unlike [ChannelPickerList] this is not a set of independent switches —
/// exactly one option is active at a time, because a tag is a lens on the
/// feed rather than a subscription. The list never assumes a fixed number of
/// tags: it draws however many the API currently offers.
class TagFilterList extends ConsumerWidget {
  const TagFilterList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Loaded<List<NewsTag>>> tags = ref.watch(newsTagsProvider);

    return switch (tags) {
      AsyncLoading<Loaded<List<NewsTag>>>() when !tags.hasValue =>
        const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: LoadingView(),
        ),
      AsyncError<Loaded<List<NewsTag>>>(:final Object error) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ErrorView(
          failure: error,
          onRetry: () => ref.invalidate(newsTagsProvider),
        ),
      ),
      _ => _buildList(context, ref, l10n, tags.requireValue.value),
    };
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<NewsTag> tags,
  ) {
    // No tags at all is not an error state here: the feed simply offers
    // "Alle" and nothing else to narrow it by.
    if (tags.isEmpty) return const SizedBox.shrink();

    final String? selected = ref.watch(newsTagFilterProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Text(
              l10n.newsTagFilterSectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              Semantics(
                selected: selected == null,
                label: l10n.newsTagFilterAllSemanticLabel,
                // excludeSemantics drops the chip's own tap action, so the
                // merged node has to carry it.
                onTap: () =>
                    ref.read(newsTagFilterProvider.notifier).select(null),
                excludeSemantics: true,
                child: ChoiceChip(
                  label: Text(l10n.newsTagFilterAllLabel),
                  selected: selected == null,
                  onSelected: (_) =>
                      ref.read(newsTagFilterProvider.notifier).select(null),
                ),
              ),
              for (final NewsTag tag in tags)
                Semantics(
                  selected: selected == tag.slug,
                  label: l10n.newsTagFilterTagSemanticLabel(tag.name),
                  onTap: () =>
                      ref.read(newsTagFilterProvider.notifier).select(tag.slug),
                  excludeSemantics: true,
                  child: ChoiceChip(
                    // Long or localised names wrap inside the chip instead of
                    // clipping — a Wrap of chips, not a scroll row, so the
                    // sheet's own height already accommodates it.
                    label: Text(tag.name),
                    selected: selected == tag.slug,
                    onSelected: (_) => ref
                        .read(newsTagFilterProvider.notifier)
                        .select(tag.slug),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
