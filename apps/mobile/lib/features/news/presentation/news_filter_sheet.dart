// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../application/news_feed_view_options.dart';
import '../domain/news_feed_arrangement.dart';
import 'channel_picker_sheet.dart';
import 'tag_filter_list.dart';

/// Opens the one filter the feed has.
///
/// A sheet rather than a screen: the feed gets by with a single button at the
/// top, and the reader keeps the list behind the sheet in view while changing
/// what it shows.
Future<void> showNewsFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const NewsFilterSheet(),
  );
}

/// The contents of the news filter sheet: which channels the feed shows.
class NewsFilterSheet extends ConsumerWidget {
  const NewsFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Semantics(
                header: true,
                child: Text(l10n.newsFilterTitle, style: text.titleLarge),
              ),
            ),
            const NewsSortSection(),
            const TagFilterList(),
            const Flexible(child: ChannelPickerList()),
          ],
        ),
      ),
    );
  }
}

/// "Sortierung": newest first (the server order) or chronological.
///
/// A radio group, not chips: exactly one order applies, and radio semantics
/// tell a screen reader so. Each row is a full-width list tile, comfortably
/// above the 48dp touch target.
class NewsSortSection extends ConsumerWidget {
  const NewsSortSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final NewsFeedSort sort = ref.watch(newsFeedSortProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              l10n.newsSortSectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        RadioGroup<NewsFeedSort>(
          groupValue: sort,
          onChanged: (NewsFeedSort? next) {
            if (next != null) {
              ref.read(newsFeedSortProvider.notifier).select(next);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RadioListTile<NewsFeedSort>.adaptive(
                value: NewsFeedSort.newest,
                title: Text(l10n.newsSortNewest),
              ),
              RadioListTile<NewsFeedSort>.adaptive(
                value: NewsFeedSort.chronological,
                title: Text(l10n.newsSortChronological),
                subtitle: Text(l10n.newsSortChronologicalHint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
