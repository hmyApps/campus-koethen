// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/content/content_block.dart';
import '../../../core/links/safe_link_launcher.dart';
import '../../../core/network/json.dart';

/// A channel as delivered by `GET /v1/posts/channels`.
///
/// The client never hard-codes a channel list; every channel originates here.
class NewsChannel {
  const NewsChannel({
    required this.slug,
    required this.name,
    required this.sortOrder,
    required this.defaultSubscribed,
    this.description,
    this.colorHex,
    this.publicCalendarSlug,
  });

  final String slug;
  final String name;
  final String? description;

  /// Editorial colour hint. Never used as the sole carrier of a state and
  /// never used as a text colour, because its contrast is not guaranteed.
  final String? colorHex;

  final int sortOrder;

  /// Evaluated exactly once per slug, on the channel's first ever appearance.
  final bool defaultSubscribed;

  /// Slug of the public Google calendar this channel is linked to 1:1, or
  /// `null` when it has none. Used only to fold a matching calendar into the
  /// same event source as this channel — see the `events` feature.
  final String? publicCalendarSlug;

  static NewsChannel? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? slug = asString(map['slug']);
    if (slug == null) return null;
    return NewsChannel(
      slug: slug,
      name: asString(map['name']) ?? slug,
      description: asString(map['description']),
      colorHex: asString(map['colorHex']),
      sortOrder: asInt(map['sortOrder']) ?? 0,
      defaultSubscribed: asBool(map['defaultSubscribed']) ?? false,
      publicCalendarSlug: asString(map['publicCalendarSlug']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'slug': slug,
    'name': name,
    'description': description,
    'colorHex': colorHex,
    'sortOrder': sortOrder,
    'defaultSubscribed': defaultSubscribed,
    'publicCalendarSlug': publicCalendarSlug,
  };

  static List<NewsChannel> listFromJson(Object? json) =>
      asList(json).map(NewsChannel.fromJson).whereType<NewsChannel>().toList()
        ..sort((NewsChannel a, NewsChannel b) {
          final int order = a.sortOrder.compareTo(b.sortOrder);
          return order != 0 ? order : a.name.compareTo(b.name);
        });
}

/// Lightweight channel reference embedded in an article.
class NewsChannelRef {
  const NewsChannelRef({required this.slug, required this.name, this.colorHex});

  final String slug;
  final String name;
  final String? colorHex;

  static NewsChannelRef? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? slug = asString(map['slug']);
    if (slug == null) return null;
    return NewsChannelRef(
      slug: slug,
      name: asString(map['name']) ?? slug,
      colorHex: asString(map['colorHex']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'slug': slug,
    'name': name,
    'colorHex': colorHex,
  };
}

/// A post tag as delivered by `GET /v1/posts/tags`.
///
/// The client never hard-codes a tag list; every tag originates here. `event`
/// is the one slug the client treats as structurally special (the event
/// view), but that is a client-side convention over an ordinary dynamic tag,
/// not a distinct type on the wire.
class NewsTag {
  const NewsTag({required this.slug, required this.name});

  final String slug;
  final String name;

  static NewsTag? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? slug = asString(map['slug']);
    if (slug == null) return null;
    return NewsTag(slug: slug, name: asString(map['name']) ?? slug);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'slug': slug,
    'name': name,
  };

  static List<NewsTag> listFromJson(Object? json) =>
      asList(json).map(NewsTag.fromJson).whereType<NewsTag>().toList()
        ..sort((NewsTag a, NewsTag b) => a.name.compareTo(b.name));
}

/// Lightweight tag reference embedded in a post. Every post carries exactly
/// one — the API's `tag` field is mandatory, never a list.
class NewsTagRef {
  const NewsTagRef({required this.slug, required this.name});

  final String slug;
  final String name;

  static NewsTagRef? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? slug = asString(map['slug']);
    if (slug == null) return null;
    return NewsTagRef(slug: slug, name: asString(map['name']) ?? slug);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'slug': slug,
    'name': name,
  };
}

/// An editorial image. `null` when no approved image exists.
class NewsImage {
  const NewsImage({
    required this.url,
    this.alternativeText,
    this.width,
    this.height,
  });

  final String url;
  final String? alternativeText;
  final int? width;
  final int? height;

  double? get aspectRatio => (width != null && height != null && height! > 0)
      ? width! / height!
      : null;

  static NewsImage? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? url = asString(map['url']);
    // A media path published by the API, not an outbound link. Running it past
    // SafeLinkLauncher — which demands an absolute https URL — dropped every
    // image the CMS ever delivered.
    if (url == null || url.isEmpty) return null;
    return NewsImage(
      url: url,
      alternativeText: asString(map['alternativeText']),
      width: asInt(map['width']),
      height: asInt(map['height']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'alternativeText': alternativeText,
    'width': width,
    'height': height,
  };
}

/// A post (news article or event post). List entries carry an empty
/// [content].
///
/// Every post has exactly one [tag] and exactly one mandatory
/// [primaryChannel] — the merged `/v1/posts*` contract dropped the old
/// multi-tag shape. [channels] still lists every channel the post is
/// published to (`primaryChannel` is always one of them).
class NewsArticle {
  const NewsArticle({
    required this.slug,
    required this.title,
    required this.tag,
    required this.primaryChannel,
    this.publishedAt,
    this.heroImage,
    this.channels = const <NewsChannelRef>[],
    this.sourceName,
    this.sourceUrl,
    this.content = const <ContentBlock>[],
    this.eventStart,
    this.eventEnd,
    this.eventAllDay = false,
  });

  final String slug;
  final String title;
  final DateTime? publishedAt;
  final NewsImage? heroImage;

  /// Every channel this post is published to. Always contains
  /// [primaryChannel].
  final List<NewsChannelRef> channels;

  /// The post's single mandatory classification tag.
  final NewsTagRef tag;

  /// The post's single mandatory publishing channel — the source of truth
  /// for which event source (see the `events` feature) this post belongs to.
  final NewsChannelRef primaryChannel;

  final String? sourceName;

  /// Always a validated `https` URL or `null`.
  final String? sourceUrl;

  final List<ContentBlock> content;

  /// Event time fields. Present (non-null [eventStart]) only for posts
  /// tagged `event`; an ordinary article has all three at their defaults.
  final DateTime? eventStart;
  final DateTime? eventEnd;
  final bool eventAllDay;

  /// Whether this post carries the structural information to be shown as an
  /// event (i.e. has a start instant).
  bool get isEventPost => eventStart != null;

  /// The raw JSON this article was parsed from, used for caching.
  static NewsArticle? fromJson(Object? json) {
    final Map<String, dynamic>? map = asJsonMap(json);
    if (map == null) return null;
    final String? slug = asString(map['slug']);
    final String? title = asString(map['title']);
    final NewsTagRef? tag = NewsTagRef.fromJson(map['tag']);
    final NewsChannelRef? primaryChannel = NewsChannelRef.fromJson(
      map['primaryChannel'],
    );
    if (slug == null ||
        title == null ||
        tag == null ||
        primaryChannel == null) {
      return null;
    }
    final String? sourceUrl = asString(map['sourceUrl']);
    final bool eventAllDay = asBool(map['eventAllDay']) ?? false;
    final DateTime? eventStart = asDateTime(map['eventStart']);
    return NewsArticle(
      slug: slug,
      title: title,
      publishedAt: asDateTime(map['publishedAt']),
      heroImage: NewsImage.fromJson(map['heroImage']),
      tag: tag,
      primaryChannel: primaryChannel,
      channels: asList(map['channels'])
          .map(NewsChannelRef.fromJson)
          .whereType<NewsChannelRef>()
          .toList(growable: false),
      sourceName: asString(map['sourceName']),
      sourceUrl: SafeLinkLauncher.isAllowed(sourceUrl) ? sourceUrl : null,
      content: ContentBlock.parse(map['content']),
      eventStart: eventAllDay && eventStart != null
          ? _allDayDate(eventStart)
          : eventStart,
      eventEnd: asDateTime(map['eventEnd']),
      eventAllDay: eventAllDay,
    );
  }

  /// `eventStart` is a Strapi `datetime`: an all-day event entered as 00:00
  /// Berlin time arrives as 22:00Z/23:00Z the evening before. Every reader
  /// takes an all-day start as a UTC-midnight date marker (`calendarDayOf`),
  /// so the post showed a day early and never matched its public-calendar
  /// twin (VF-N01). The start is therefore re-read as the local date it was
  /// entered for. A value that already is UTC midnight is kept, so a server
  /// sending date markers is never shifted.
  ///
  /// `eventEnd` is deliberately left alone: its UTC date already is the last
  /// day for both an end at 23:59 and one at the following midnight.
  static DateTime _allDayDate(DateTime start) {
    final DateTime utc = start.toUtc();
    if (utc == DateTime.utc(utc.year, utc.month, utc.day)) return utc;
    final DateTime local = start.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  static List<NewsArticle> listFromJson(Object? json) => asList(
    json,
  ).map(NewsArticle.fromJson).whereType<NewsArticle>().toList(growable: false);
}

/// One page of the post list plus the pagination metadata.
///
/// [from] and [to] carry `meta.from`/`meta.to` for event-post pages only
/// (`null` on a plain `/v1/posts` page) — the server-resolved window that
/// governs the event cache key and the reconciliation of the offline saved
/// list, per the "client sends no default window" contract.
class NewsPage {
  const NewsPage({
    required this.articles,
    required this.page,
    required this.totalPages,
    this.from,
    this.to,
  });

  final List<NewsArticle> articles;
  final int page;
  final int totalPages;
  final String? from;
  final String? to;

  bool get hasNextPage => page < totalPages;
}
