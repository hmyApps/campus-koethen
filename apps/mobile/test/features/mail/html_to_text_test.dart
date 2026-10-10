import 'package:campus_koethen/features/mail/data/html_to_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes excessive blank lines in a plain-text mail', () {
    expect(
      normalizeMailBody('Hallo\r\n  \r\n\r\n\r\nWelt  \r\n'),
      'Hallo\n\nWelt',
    );
  });

  test('keeps one paragraph break in HTML-derived mail', () {
    expect(
      htmlToPlainText('<div>Hallo</div><div><br></div><div>Welt</div>'),
      'Hallo\n\nWelt',
    );
  });

  group('character references (C-11)', () {
    test('decodes named entities beyond the basic six', () {
      expect(
        htmlToPlainText('<p>Pr&uuml;fung &ndash; Gr&ouml;&szlig;e &euro;</p>'),
        'Prüfung – Größe €',
      );
    });

    test('decodes decimal and hexadecimal references', () {
      expect(
        htmlToPlainText('<p>&#8364; &#x20AC; &#X27;x&#x27; &#39;y&#39;</p>'),
        "€ € 'x' 'y'",
      );
    });

    test('decodes exactly once: an escaped entity stays literal', () {
      expect(
        htmlToPlainText('<p>&amp;lt;b&amp;gt; &amp;amp;</p>'),
        '&lt;b&gt; &amp;',
      );
    });

    test('decoded angle brackets remain plain text, never markup', () {
      expect(
        htmlToPlainText('<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>'),
        '<script>alert(1)</script>',
      );
    });

    test('a stray angle bracket and an unknown entity survive verbatim', () {
      expect(
        htmlToPlainText('<p>3 < 4 &amp; AT&T &unknownthing;</p>'),
        '3 < 4 & AT&T &unknownthing;',
      );
    });

    test('a non-breaking space still becomes an ordinary space', () {
      expect(htmlToPlainText('<p>Raum&nbsp;A&#160;101</p>'), 'Raum A 101');
    });
  });
}
