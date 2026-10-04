// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/hsa_ki/data/hawki_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('loginFormToken', () {
    test('reads the value of hawkiLoginForm\'s hidden _token input', () {
      const String html = '''
        <html><body>
          <form id="hawkiLoginForm" method="POST" action="/req/login">
            <input type="hidden" name="_token" value="csrf-abc123">
            <input type="text" name="account">
          </form>
        </body></html>
      ''';
      expect(HawkiHtmlParser.loginFormToken(html), 'csrf-abc123');
    });

    test('returns null when the login form is missing', () {
      const String html = '<html><body><p>Maintenance</p></body></html>';
      expect(HawkiHtmlParser.loginFormToken(html), isNull);
    });

    test('returns null when the token input has no value', () {
      const String html = '''
        <form id="hawkiLoginForm">
          <input type="hidden" name="_token" value="">
        </form>
      ''';
      expect(HawkiHtmlParser.loginFormToken(html), isNull);
    });

    test('ignores an unrelated meta csrf-token tag', () {
      const String html = '''
        <html><head><meta name="csrf-token" content="meta-token"></head>
        <body><form id="hawkiLoginForm"></form></body></html>
      ''';
      expect(HawkiHtmlParser.loginFormToken(html), isNull);
    });
  });

  group('pageMetaToken', () {
    test('reads the page-wide meta csrf-token tag', () {
      const String html = '''
        <html><head><meta name="csrf-token" content="meta-token-xyz"></head>
        <body></body></html>
      ''';
      expect(HawkiHtmlParser.pageMetaToken(html), 'meta-token-xyz');
    });

    test('returns null when no meta tag is present', () {
      const String html = '<html><body><p>Profile</p></body></html>';
      expect(HawkiHtmlParser.pageMetaToken(html), isNull);
    });
  });
}
