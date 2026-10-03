// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/content/content_block.dart';

/// How many lines of the article the collapsed card shows.
const int kNewsPreviewLines = 5;

typedef NewsPreviewRun = ({String text, bool bold});

final Expando<String> _previewTextCache = Expando<String>('newsPreviewText');
final Expando<List<NewsPreviewRun>> _previewRunsCache =
    Expando<List<NewsPreviewRun>>('newsPreviewRuns');
final Expando<bool> _unpreviewableBlocksCache = Expando<bool>(
  'newsUnpreviewable',
);

/// Flattens the article's blocks into the text of the preview.
///
/// The preview is a **text** preview: it can show what a paragraph, a heading,
/// a quote or a list says, but not an image. Blocks are separated by newlines
/// so the five-line limit counts real lines of the article rather than one
/// endless run-on paragraph.
///
/// Bold ranges are kept in [newsPreviewRuns] for the collapsed card.
String newsPreviewText(List<ContentBlock> blocks) {
  final String? cached = _previewTextCache[blocks];
  if (cached != null) return cached;
  final String result = newsPreviewRuns(
    blocks,
  ).map((NewsPreviewRun run) => run.text).join();
  _previewTextCache[blocks] = result;
  return result;
}

/// Text runs for the preview, preserving inline bold formatting without links.
List<NewsPreviewRun> newsPreviewRuns(List<ContentBlock> blocks) {
  final List<NewsPreviewRun>? cached = _previewRunsCache[blocks];
  if (cached != null) return cached;
  final List<NewsPreviewRun> result = _joinRuns(blocks.map(_blockRuns));
  _previewRunsCache[blocks] = result;
  return result;
}

/// Whether anything exists that the text preview cannot represent.
///
/// An article whose body is a single image would otherwise look empty with no
/// way to open it: the preview would be blank and, with nothing to truncate,
/// no "show more" would appear.
bool hasUnpreviewableBlocks(List<ContentBlock> blocks) {
  final bool? cached = _unpreviewableBlocksCache[blocks];
  if (cached != null) return cached;
  final bool result = blocks.any((ContentBlock block) => block is ImageBlock);
  _unpreviewableBlocksCache[blocks] = result;
  return result;
}

/// Whether the collapsed card has anything left to reveal.
///
/// [textOverflows] comes from measuring the preview at its real width — only
/// the layout knows whether five lines were enough.
bool hasMoreToShow({
  required List<ContentBlock> blocks,
  required bool textOverflows,
}) => textOverflows || hasUnpreviewableBlocks(blocks);

List<NewsPreviewRun> _blockRuns(ContentBlock block) => switch (block) {
  ParagraphBlock(:final List<InlineNode> children) => _inlineRuns(children),
  HeadingBlock(:final List<InlineNode> children) => _inlineRuns(children),
  QuoteBlock(:final List<InlineNode> children) => _inlineRuns(children),
  ListItemBlock(:final List<InlineNode> children) => _inlineRuns(children),
  ListBlock(:final List<ListItemBlock> items) => _joinRuns(
    items.map((ListItemBlock item) => _inlineRuns(item.children)),
  ),
  // An image has no text. It is what `hasUnpreviewableBlocks` reports.
  ImageBlock() => <NewsPreviewRun>[],
};

List<NewsPreviewRun> _joinRuns(Iterable<List<NewsPreviewRun>> groups) {
  final List<NewsPreviewRun> result = <NewsPreviewRun>[];
  for (final List<NewsPreviewRun> group in groups) {
    if (group.isEmpty) continue;
    if (result.isNotEmpty) result.add((text: '\n', bold: false));
    result.addAll(group);
  }
  return result;
}

List<NewsPreviewRun> _inlineRuns(List<InlineNode> nodes) {
  final List<NewsPreviewRun> raw = <NewsPreviewRun>[];
  for (final InlineNode node in nodes) {
    switch (node) {
      case InlineText(:final String text, :final bool bold):
        raw.add((text: text, bold: bold));
      case InlineLink(:final List<InlineText> children):
        // The link's label is part of the sentence; the URL is not.
        for (final InlineText child in children) {
          raw.add((text: child.text, bold: child.bold));
        }
    }
  }

  final String full = raw.map((NewsPreviewRun run) => run.text).join();
  final int start = full.length - full.trimLeft().length;
  final int end = full.trimRight().length;
  if (end <= start) return <NewsPreviewRun>[];

  final List<NewsPreviewRun> trimmed = <NewsPreviewRun>[];
  int offset = 0;
  for (final NewsPreviewRun run in raw) {
    final int runEnd = offset + run.text.length;
    if (runEnd > start && offset < end) {
      final int from = start > offset ? start - offset : 0;
      final int to = end < runEnd ? end - offset : run.text.length;
      trimmed.add((text: run.text.substring(from, to), bold: run.bold));
    }
    offset = runEnd;
  }
  return trimmed;
}
