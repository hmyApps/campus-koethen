// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/content/content_block.dart';
import 'package:campus_koethen/features/news/domain/news_preview.dart';
import 'package:flutter_test/flutter_test.dart';

InlineText _t(String text) => InlineText(text: text);

ParagraphBlock _p(String text) => ParagraphBlock(<InlineNode>[_t(text)]);

const ImageBlock _image = ImageBlock(url: '/v1/media/uploads/a.jpg');

void main() {
  group('the preview text', () {
    test('joins blocks with a newline, so lines are real lines', () {
      expect(
        newsPreviewText(<ContentBlock>[_p('Erste Zeile'), _p('Zweite Zeile')]),
        'Erste Zeile\nZweite Zeile',
      );
    });

    test('reads headings and quotes too', () {
      expect(
        newsPreviewText(<ContentBlock>[
          HeadingBlock(level: 2, children: <InlineNode>[_t('Überblick')]),
          QuoteBlock(<InlineNode>[_t('Ein Zitat')]),
        ]),
        'Überblick\nEin Zitat',
      );
    });

    test('a list contributes one line per item', () {
      expect(
        newsPreviewText(<ContentBlock>[
          ListBlock(
            ordered: false,
            items: <ListItemBlock>[
              ListItemBlock(<InlineNode>[_t('A')]),
              ListItemBlock(<InlineNode>[_t('B')]),
            ],
          ),
        ]),
        'A\nB',
      );
    });

    test('a link contributes its label, never its URL', () {
      expect(
        newsPreviewText(<ContentBlock>[
          ParagraphBlock(<InlineNode>[
            _t('Mehr auf '),
            InlineLink(
              url: 'https://example.org/sehr/lang',
              children: <InlineText>[_t('der Website')],
            ),
          ]),
        ]),
        'Mehr auf der Website',
      );
    });

    test('keeps bold ranges while trimming and joining preview text', () {
      final List<ContentBlock> blocks = <ContentBlock>[
        ParagraphBlock(<InlineNode>[
          _t('  Ganz '),
          const InlineText(text: 'wichtig', bold: true),
          InlineLink(
            url: 'https://example.org',
            children: const <InlineText>[
              InlineText(text: ' und '),
              InlineText(text: 'verlinkt  ', bold: true),
            ],
          ),
        ]),
        _p('Danach'),
      ];

      expect(newsPreviewText(blocks), 'Ganz wichtig und verlinkt\nDanach');
      expect(newsPreviewRuns(blocks), <NewsPreviewRun>[
        (text: 'Ganz ', bold: false),
        (text: 'wichtig', bold: true),
        (text: ' und ', bold: false),
        (text: 'verlinkt', bold: true),
        (text: '\n', bold: false),
        (text: 'Danach', bold: false),
      ]);
    });

    test('an image contributes nothing to the text', () {
      expect(newsPreviewText(<ContentBlock>[_image, _p('Text')]), 'Text');
    });

    test('no blocks means no preview', () {
      expect(newsPreviewText(const <ContentBlock>[]), '');
    });
  });

  group('deciding whether there is more', () {
    test('overflowing text alone is enough', () {
      expect(
        hasMoreToShow(blocks: <ContentBlock>[_p('x')], textOverflows: true),
        isTrue,
      );
    });

    test('an image is enough even when the text fits', () {
      // Otherwise an article whose body is one image would look empty with no
      // way to open it: nothing to truncate, so no "show more".
      expect(
        hasMoreToShow(blocks: <ContentBlock>[_image], textOverflows: false),
        isTrue,
      );
      expect(hasUnpreviewableBlocks(<ContentBlock>[_image]), isTrue);
    });

    test('short text without images has nothing more to reveal', () {
      expect(
        hasMoreToShow(blocks: <ContentBlock>[_p('kurz')], textOverflows: false),
        isFalse,
      );
      expect(hasUnpreviewableBlocks(<ContentBlock>[_p('kurz')]), isFalse);
    });

    test('an empty article has nothing more either', () {
      expect(
        hasMoreToShow(blocks: const <ContentBlock>[], textOverflows: false),
        isFalse,
      );
    });
  });

  test('the collapsed card shows five lines', () {
    expect(kNewsPreviewLines, 5);
  });
}
