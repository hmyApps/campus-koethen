// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Post images use a square preview and open the original media file in-app.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_koethen/core/network/api_config.dart';
import 'package:campus_koethen/core/theme/app_icons.dart';
import 'package:campus_koethen/features/news/data/news_models.dart';
import 'package:campus_koethen/features/news/presentation/article_block.dart';
import 'package:campus_koethen/features/news/presentation/post_image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/news_harness.dart';
import '../../support/pump_app.dart';

NewsArticle article({int? width, int? height}) =>
    NewsArticle.fromJson(<String, dynamic>{
      'slug': 'a',
      'title': 'Meldung',
      'publishedAt': '2026-08-04T09:00:00.000Z',
      'heroImage': <String, dynamic>{
        'url': '/v1/media/uploads/banner.jpg',
        'alternativeText': 'Ein Bild',
        'width': width,
        'height': height,
      },
      'channels': <Object>[],
      'tag': <String, dynamic>{'slug': 'news', 'name': 'News'},
      'primaryChannel': <String, dynamic>{
        'slug': 'campus-news',
        'name': 'Campus News',
      },
      'content': <Object>[],
    })!;

/// The ratio the banner is actually drawn at.
double bannerRatio(WidgetTester tester) =>
    tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio;

Future<void> pumpCard(WidgetTester tester, NewsArticle value) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await pumpScreen(
    tester,
    Scaffold(
      body: SingleChildScrollView(child: ArticleBlock(article: value)),
    ),
    // The feed's clock ticks every minute; without freezing it the card leaves
    // a timer behind and every test here fails for a reason that is not the
    // banner.
    overrides: <Override>[frozenNewsClock()],
  );
  await tester.pump();
}

void main() {
  testWidgets('a square photo stays square in the preview', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, article(width: 800, height: 800));

    expect(bannerRatio(tester), 1);
  });

  testWidgets('a portrait photo has a square preview', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, article(width: 900, height: 1600));

    expect(bannerRatio(tester), 1);
  });

  testWidgets('a wide photo also has a square preview', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, article(width: 2100, height: 900));

    expect(bannerRatio(tester), 1);
    final Rect preview = tester.getRect(find.byType(PostImagePreview));
    final Rect icon = tester.getRect(find.byIcon(AppIcons.fullscreen));
    expect(preview.width, closeTo(preview.height, 0.01));
    expect(icon.center.dx, greaterThan(preview.center.dx));
    expect(icon.center.dy, greaterThan(preview.center.dy));
  });

  testWidgets('an image without a reported size is square too', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, article());

    expect(bannerRatio(tester), 1);
  });

  testWidgets('the preview announces its action and alternative text', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, article(width: 800, height: 800));

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label?.contains('Ein Bild') == true &&
            widget.properties.button == true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('the preview opens original resolution and closes both ways', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, article(width: 1600, height: 900));

    await tester.tap(find.byTooltip('Bild im Vollbild öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Bildansicht schließen'), findsOneWidget);
    final List<CachedNetworkImage> images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    expect(images, hasLength(2));
    expect(
      images.last.imageUrl,
      ApiConfig.resolveMediaUrl('/v1/media/uploads/banner.jpg'),
    );
    expect(images.last.memCacheWidth, isNull);
    expect(images.last.memCacheHeight, isNull);

    await tester.tap(find.byTooltip('Bildansicht schließen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Bildansicht schließen'), findsNothing);

    await tester.tap(find.byTooltip('Bild im Vollbild öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Bildansicht schließen'), findsOneWidget);

    await tester.tapAt(const Offset(10, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Bildansicht schließen'), findsNothing);
  });
}
