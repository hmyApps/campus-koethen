// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:html/parser.dart' as html_parser;

final RegExp _scriptStylePattern = RegExp(
  r'<(script|style)[^>]*>.*?</\1>',
  dotAll: true,
  caseSensitive: false,
);
final RegExp _brPattern = RegExp(r'<\s*br\s*/?>', caseSensitive: false);
final RegExp _blockClosePattern = RegExp(
  r'</\s*(p|div|tr|li|h[1-6])\s*>',
  caseSensitive: false,
);
final RegExp _allTagsPattern = RegExp(r'<[^>]+>');
final RegExp _lineWhitespacePattern = RegExp(r'[ \t]+$', multiLine: true);
final RegExp _blankLinesPattern = RegExp(r'\n[ \t]*\n(?:[ \t]*\n)+');

/// Keeps paragraph breaks while removing transport line endings and excess
/// whitespace from both plain and HTML-derived mail bodies.
String normalizeMailBody(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\u00a0', ' ')
    .replaceAll(_lineWhitespacePattern, '')
    .replaceAll(_blankLinesPattern, '\n\n')
    .trim();

/// Reduces an HTML mail body to safe plain text.
///
/// This is intentionally lossy: the MVP renders TEXT only. No HTML is shown, no
/// WebView is used, and — because the output is plain text — no remote image is
/// ever fetched. Scripts, styles and tags are removed rather than interpreted.
String htmlToPlainText(String? html) {
  if (html == null || html.trim().isEmpty) return '';
  String text = html;
  // Drop script/style blocks entirely, including their content.
  text = text.replaceAll(_scriptStylePattern, ' ');
  // Turn common block/line breaks into newlines before stripping tags.
  text = text.replaceAll(_brPattern, '\n');
  text = text.replaceAll(_blockClosePattern, '\n');
  // Remove all remaining tags.
  text = text.replaceAll(_allTagsPattern, '');
  text = _decodeCharacterReferences(text);
  // Collapse excessive blank lines and trailing whitespace.
  return normalizeMailBody(text);
}

/// Decodes every HTML character reference — named (`&uuml;`), decimal
/// (`&#8364;`) and hexadecimal (`&#x20AC;`) — in a single pass, with the
/// HTML5 parser's own entity table, so `&amp;lt;` yields the literal `&lt;`
/// instead of being decoded twice.
///
/// Every remaining `<` is escaped first: the parser then only ever sees
/// character data, so neither leftover tag-shaped text nor a decoded `&lt;`
/// can turn into markup. The result is plain text either way.
String _decodeCharacterReferences(String text) {
  if (!text.contains('&')) return text;
  return html_parser.parseFragment(text.replaceAll('<', '&lt;')).text ?? '';
}
