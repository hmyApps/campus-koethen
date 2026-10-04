// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Pure HTML extraction for HAWKI pages — no network code, same split as
/// every other direct-integration parser in this app.
abstract final class HawkiHtmlParser {
  /// The login form's own CSRF token, confirmed 2026-10-04 from the real
  /// page's own login script: it reads
  /// `#hawkiLoginForm input[name="_token"]`, never the `<meta
  /// name="csrf-token">` tag, for this specific request.
  static String? loginFormToken(String htmlSource) {
    final Document doc = html.parse(htmlSource);
    final Element? form = doc.querySelector('#hawkiLoginForm');
    final Element? input = form?.querySelector('input[name="_token"]');
    final String? value = input?.attributes['value'];
    return (value == null || value.isEmpty) ? null : value;
  }

  /// The page-wide CSRF token Laravel's default layout embeds in every page
  /// as `<meta name="csrf-token" content="…">`, used for authenticated
  /// requests made from pages with no login form of their own (e.g.
  /// `/profile`).
  static String? pageMetaToken(String htmlSource) {
    final Document doc = html.parse(htmlSource);
    final Element? meta = doc.querySelector('meta[name="csrf-token"]');
    final String? value = meta?.attributes['content'];
    return (value == null || value.isEmpty) ? null : value;
  }
}
