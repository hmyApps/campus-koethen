// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Editorial images: how a media reference from the API becomes a picture.
///
/// The API publishes API-relative paths (`/v1/media/…`) rather than links to
/// the CMS — the app is not allowed to talk to the CMS (AGENTS.md §2.1), and
/// the CMS's own upload URLs are relative and unusable on a phone. Every one
/// of these tests exists because a check written for outbound *links* was
/// silently dropping those paths.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_koethen/core/content/content_block.dart';
import 'package:campus_koethen/core/network/api_config.dart';
import 'package:campus_koethen/core/widgets/content_blocks_view.dart';
import 'package:campus_koethen/features/contacts/data/contact_models.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_app.dart';

void main() {
  group('resolving a media reference', () {
    test('turns an API-relative path into a fetchable URL', () {
      final String? resolved = ApiConfig.resolveMediaUrl(
        '/v1/media/uploads/foto_abc.jpg',
      );

      expect(resolved, isNotNull);
      expect(resolved, endsWith('/v1/media/uploads/foto_abc.jpg'));
      expect(resolved, startsWith(ApiConfig.baseUrl));
    });

    test('refuses an absolute URL even when it uses https', () {
      // Public/editorial data has exactly one network boundary: the Campus API.
      // Letting a response name another HTTPS host would permit tracking pixels
      // and silently reintroduce a direct third-party data path.
      expect(ApiConfig.resolveMediaUrl('https://cdn.example/foto.jpg'), isNull);
    });

    test('drops anything that is not usable', () {
      // A plain-http link from a response is not loaded.
      expect(ApiConfig.resolveMediaUrl('http://cdn.example/foto.jpg'), isNull);
      expect(ApiConfig.resolveMediaUrl('/v1/media/other/foto.jpg'), isNull);
      expect(
        ApiConfig.resolveMediaUrl('/v1/media/uploads/../secret.jpg'),
        isNull,
      );
      expect(
        ApiConfig.resolveMediaUrl('/v1/media/uploads/foto.jpg?track=1'),
        isNull,
      );
      expect(ApiConfig.resolveMediaUrl(''), isNull);
      expect(ApiConfig.resolveMediaUrl('   '), isNull);
      expect(ApiConfig.resolveMediaUrl(null), isNull);
      expect(ApiConfig.resolveMediaUrl('nicht-absolut'), isNull);
    });
  });

  group('a news article', () {
    Map<String, dynamic> article({Object? heroImage}) => <String, dynamic>{
      'slug': 'a',
      'title': 'Titel',
      'heroImage': heroImage,
      'tag': <String, dynamic>{'slug': 'news', 'name': 'News'},
      'primaryChannel': <String, dynamic>{
        'slug': 'campus-news',
        'name': 'Campus News',
      },
    };

    test('keeps the banner the API published', () {
      final NewsArticle? parsed = NewsArticle.fromJson(
        article(
          heroImage: <String, dynamic>{
            'url': '/v1/media/uploads/hero_abc.jpg',
            'alternativeText': 'Ein Bild',
            'width': 1600,
            'height': 900,
          },
        ),
      );

      expect(parsed!.heroImage, isNotNull);
      expect(parsed.heroImage!.url, '/v1/media/uploads/hero_abc.jpg');
      expect(parsed.heroImage!.alternativeText, 'Ein Bild');
      expect(parsed.heroImage!.aspectRatio, closeTo(16 / 9, 0.01));
    });

    test('has no banner when the article has none', () {
      expect(NewsArticle.fromJson(article())!.heroImage, isNull);
      expect(
        NewsArticle.fromJson(
          article(heroImage: <String, dynamic>{'url': ''}),
        )!.heroImage,
        isNull,
      );
    });

    test('has no aspect ratio when the CMS reported no size', () {
      final NewsArticle parsed = NewsArticle.fromJson(
        article(heroImage: <String, dynamic>{'url': '/v1/media/uploads/h.jpg'}),
      )!;

      // The preview remains square even when the CMS reports no dimensions.
      expect(parsed.heroImage!.aspectRatio, isNull);
    });
  });

  group('an image block inside rich text', () {
    // The API rewrites every inline image onto its own media route, exactly
    // like a banner (G-01). A check written for outbound links demanded an
    // `https` scheme and silently dropped every one of them.
    Map<String, dynamic> imageBlock(String url) => <String, dynamic>{
      'type': 'image',
      'url': url,
      'alternativeText': 'Plakat zum Sommerfest',
      'width': 1200,
      'height': 800,
    };

    test('keeps the API-relative media path the API published', () {
      final List<ContentBlock> blocks = ContentBlock.parse(<Object>[
        imageBlock('/v1/media/uploads/plakat_abc.png'),
      ]);

      expect(blocks, hasLength(1));
      final ImageBlock image = blocks.single as ImageBlock;
      expect(image.url, '/v1/media/uploads/plakat_abc.png');
      expect(image.alternativeText, 'Plakat zum Sommerfest');
      expect(image.width, 1200);
      expect(image.height, 800);
    });

    test('still refuses anything that is not the API media route', () {
      // No loosening for foreign hosts or plaintext: the parser accepts
      // exactly what the renderer can resolve against the Campus API.
      expect(
        ContentBlock.parse(<Object>[
          imageBlock('https://cdn.example/plakat.png'),
          imageBlock('http://cdn.example/plakat.png'),
          imageBlock('/v1/media/other/plakat.png'),
          imageBlock('/v1/media/uploads/../secret.png'),
          imageBlock('javascript:alert(1)'),
          imageBlock(''),
        ]),
        isEmpty,
      );
    });

    testWidgets('is rendered from the Campus API media route', (
      WidgetTester tester,
    ) async {
      final List<ContentBlock> blocks = ContentBlock.parse(<Object>[
        imageBlock('/v1/media/uploads/plakat_abc.png'),
      ]);

      await pumpScreen(
        tester,
        Scaffold(
          body: SingleChildScrollView(child: ContentBlocksView(blocks: blocks)),
        ),
      );

      final CachedNetworkImage image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(
        image.imageUrl,
        ApiConfig.resolveMediaUrl('/v1/media/uploads/plakat_abc.png'),
      );
      expect(find.bySemanticsLabel('Plakat zum Sommerfest'), findsOneWidget);
    });
  });

  group('a contact area', () {
    test('keeps the image the API published', () {
      final ContactArea? area = ContactArea.fromJson(<String, dynamic>{
        'slug': 'studierendenrat',
        'name': 'Studierendenrat',
        'image': '/v1/media/uploads/team_abc.jpg',
      });

      expect(area!.imageUrl, '/v1/media/uploads/team_abc.jpg');
    });

    test('is perfectly valid without one', () {
      final ContactArea? area = ContactArea.fromJson(<String, dynamic>{
        'slug': 'x',
        'name': 'X',
      });

      expect(area!.imageUrl, isNull);
    });
  });

  group('a contact person', () {
    test('keeps the photo the API published', () {
      // The API sends a plain string here, not a nested media object — reading
      // it as an object is why no photo ever appeared.
      final ContactArea? area = ContactArea.fromJson(<String, dynamic>{
        'slug': 'x',
        'name': 'X',
        'persons': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Testperson',
            'profileImage': '/v1/media/uploads/face_abc.jpg',
          },
        ],
      });

      expect(
        area!.persons.single.profileImageUrl,
        '/v1/media/uploads/face_abc.jpg',
      );
    });

    test('is valid without a photo', () {
      final ContactArea? area = ContactArea.fromJson(<String, dynamic>{
        'slug': 'x',
        'name': 'X',
        'persons': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Testperson'},
        ],
      });

      expect(area!.persons.single.profileImageUrl, isNull);
    });
  });
}
