// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../links/safe_link_launcher.dart';
import '../network/api_config.dart';
import '../network/json.dart';

/// Inline node inside a rich text block.
///
/// Only the two inline kinds of the API contract exist: `text` and `link`.
sealed class InlineNode {
  const InlineNode();

  /// Parses a single inline node. Returns `null` for anything unknown so an
  /// unexpected node can never reach the renderer.
  static InlineNode? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    switch (asString(map['type'])) {
      case 'text':
        final String? text = map['text'] is String
            ? map['text'] as String
            : null;
        if (text == null) return null;
        return InlineText(
          text: text,
          bold: asBool(map['bold']) ?? false,
          italic: asBool(map['italic']) ?? false,
          underline: asBool(map['underline']) ?? false,
          strikethrough: asBool(map['strikethrough']) ?? false,
          code: asBool(map['code']) ?? false,
        );
      case 'link':
        final String? url = asString(map['url']);
        final List<InlineText> children = parseInline(
          map['children'],
        ).whereType<InlineText>().toList(growable: false);
        if (children.isEmpty) return null;
        // Defence in depth: the API already restricts link schemes, the client
        // refuses anything else a second time.
        if (!SafeLinkLauncher.isAllowed(url)) {
          return InlineText(
            text: children.map((InlineText t) => t.text).join(),
          );
        }
        return InlineLink(url: url!, children: children);
      default:
        return null;
    }
  }

  static List<InlineNode> parseInline(Object? json) => asList(
    json,
  ).map(InlineNode.fromJson).whereType<InlineNode>().toList(growable: false);
}

class InlineText extends InlineNode {
  const InlineText({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.code = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool code;
}

class InlineLink extends InlineNode {
  const InlineLink({required this.url, required this.children});

  final String url;
  final List<InlineText> children;

  String get text => children.map((InlineText child) => child.text).join();
}

/// A rich text block of a news article or a contact area description.
///
/// Unknown block types are already dropped server-side (and reported in
/// `meta.droppedBlockTypes`). The client still fails safe: [ContentBlock.parse]
/// silently skips anything it does not know.
sealed class ContentBlock {
  const ContentBlock();

  static List<ContentBlock> parse(Object? json) => asList(json)
      .map(ContentBlock._fromJson)
      .whereType<ContentBlock>()
      .toList(growable: false);

  static ContentBlock? _fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    switch (asString(map['type'])) {
      case 'paragraph':
        final List<InlineNode> children = InlineNode.parseInline(
          map['children'],
        );
        if (children.isEmpty) return null;
        return ParagraphBlock(children);
      case 'heading':
        final List<InlineNode> children = InlineNode.parseInline(
          map['children'],
        );
        if (children.isEmpty) return null;
        final int level = (asInt(map['level']) ?? 2).clamp(1, 6);
        return HeadingBlock(level: level, children: children);
      case 'quote':
        final List<InlineNode> children = InlineNode.parseInline(
          map['children'],
        );
        if (children.isEmpty) return null;
        return QuoteBlock(children);
      case 'list':
        final List<ListItemBlock> items = asList(
          map['children'],
        ).map(_fromJson).whereType<ListItemBlock>().toList(growable: false);
        if (items.isEmpty) return null;
        return ListBlock(
          ordered: asString(map['format']) == 'ordered',
          items: items,
        );
      case 'list-item':
        final List<InlineNode> children = InlineNode.parseInline(
          map['children'],
        );
        if (children.isEmpty) return null;
        return ListItemBlock(children);
      case 'image':
        final String? url = asString(map['url']);
        // An image is not an outbound link: the API publishes it as a path on
        // its own media route (`/v1/media/uploads/…`), never as an absolute
        // URL. Accept exactly what `RemoteImage` can resolve against the
        // Campus API — no foreign host, no plaintext, no other scheme (G-01).
        if (url == null || ApiConfig.resolveMediaUrl(url) == null) return null;
        return ImageBlock(
          url: url,
          alternativeText: asString(map['alternativeText']),
          width: asInt(map['width']),
          height: asInt(map['height']),
        );
      default:
        return null;
    }
  }
}

class ParagraphBlock extends ContentBlock {
  const ParagraphBlock(this.children);

  final List<InlineNode> children;
}

class HeadingBlock extends ContentBlock {
  const HeadingBlock({required this.level, required this.children});

  final int level;
  final List<InlineNode> children;
}

class QuoteBlock extends ContentBlock {
  const QuoteBlock(this.children);

  final List<InlineNode> children;
}

class ListBlock extends ContentBlock {
  const ListBlock({required this.ordered, required this.items});

  final bool ordered;
  final List<ListItemBlock> items;
}

class ListItemBlock extends ContentBlock {
  const ListItemBlock(this.children);

  final List<InlineNode> children;
}

class ImageBlock extends ContentBlock {
  const ImageBlock({
    required this.url,
    this.alternativeText,
    this.width,
    this.height,
  });

  final String url;
  final String? alternativeText;
  final int? width;
  final int? height;
}
