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

import 'package:campus_koethen/core/network/api_config.dart';
import 'package:campus_koethen/features/contacts/data/contact_models.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:flutter_test/flutter_test.dart';

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
