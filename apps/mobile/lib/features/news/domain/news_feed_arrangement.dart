// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart' show immutable;

import '../../events/domain/event_sort.dart';
import '../../events/domain/event_visibility.dart';
import '../../events/domain/unified_event.dart';
import '../data/news_models.dart';

/// How the news feed orders its loaded articles.
enum NewsFeedSort {
  /// The server's own order: pinned first, then `publishedAt` descending.
  newest('newest'),

  /// Event posts by event start ascending (running/upcoming soonest first),
  /// followed by every other post in its newest-first order.
  chronological('chronological');

  const NewsFeedSort(this.storageValue);

  /// The stable scalar persisted in `shared_preferences`.
  final String storageValue;

  /// Reads a persisted value; anything unknown falls back to [newest], the
  /// server order, so a corrupt or future value never reorders the feed.
  static NewsFeedSort fromStorage(String? value) {
    for (final NewsFeedSort sort in values) {
      if (sort.storageValue == value) return sort;
    }
    return newest;
  }
}

/// Whether [article] is an event post that has already ended at [now].
///
/// Delegates to the event overview's own visibility rule
/// ([isEventVisibleInOverview] via [postToUnifiedEvent]) so the feed and the
/// event screen can never disagree about whether an event is over. A normal
/// post is never "ended".
bool isEndedEventPost(NewsArticle article, {required DateTime now}) {
  if (!article.isEventPost) return false;
  return !isEventVisibleInOverview(postToUnifiedEvent(article), now: now);
}

/// The next instant strictly after [now] at which one of the loaded event
/// posts ends — the one moment the feed has to be re-evaluated — or `null`.
DateTime? nextNewsFeedBoundary(
  List<NewsArticle> loaded, {
  required DateTime now,
}) => nextVisibilityBoundary(<UnifiedEvent>[
  for (final NewsArticle article in loaded)
    if (article.isEventPost) postToUnifiedEvent(article),
], now: now);

/// The loaded articles as the feed renders them.
@immutable
class NewsFeedArrangement {
  const NewsFeedArrangement({
    required this.articles,
    required this.endedSlugs,
    required this.hiddenEndedCount,
  });

  /// What to draw, in order.
  final List<NewsArticle> articles;

  /// Slugs of every loaded event post that has ended — shown or not.
  final Set<String> endedSlugs;

  /// How many ended event posts are currently left out of [articles].
  final int hiddenEndedCount;

  int get endedCount => endedSlugs.length;

  bool isEnded(NewsArticle article) => endedSlugs.contains(article.slug);
}

/// Filters and orders the loaded pages client-side.
///
/// Ended event posts are left out unless [showEnded] is set. Normal posts are
/// never left out. With [NewsFeedSort.chronological], revealed ended events
/// follow the running/upcoming ones, the most recently started first, so the
/// soonest relevant event always stays on top.
NewsFeedArrangement arrangeNewsFeed(
  List<NewsArticle> loaded, {
  required DateTime now,
  required NewsFeedSort sort,
  required bool showEnded,
}) {
  final Set<String> ended = <String>{
    for (final NewsArticle article in loaded)
      if (isEndedEventPost(article, now: now)) article.slug,
  };
  bool keep(NewsArticle article) => showEnded || !ended.contains(article.slug);

  final List<NewsArticle> articles;
  switch (sort) {
    case NewsFeedSort.newest:
      articles = loaded.where(keep).toList(growable: false);
    case NewsFeedSort.chronological:
      final List<_Keyed> upcoming = <_Keyed>[];
      final List<_Keyed> past = <_Keyed>[];
      final List<NewsArticle> posts = <NewsArticle>[];
      for (final NewsArticle article in loaded) {
        if (!article.isEventPost) {
          posts.add(article);
        } else if (!ended.contains(article.slug)) {
          upcoming.add(_Keyed(article));
        } else if (showEnded) {
          past.add(_Keyed(article));
        }
      }
      upcoming.sort((_Keyed a, _Keyed b) => compareUnifiedEvents(a.key, b.key));
      past.sort((_Keyed a, _Keyed b) => compareUnifiedEvents(b.key, a.key));
      articles = List<NewsArticle>.unmodifiable(<NewsArticle>[
        for (final _Keyed k in upcoming) k.article,
        for (final _Keyed k in past) k.article,
        ...posts,
      ]);
  }

  return NewsFeedArrangement(
    articles: articles,
    endedSlugs: Set<String>.unmodifiable(ended),
    hiddenEndedCount: showEnded ? 0 : ended.length,
  );
}

/// An event post with its unified form, mapped once per sort.
class _Keyed {
  _Keyed(this.article) : key = postToUnifiedEvent(article);

  final NewsArticle article;
  final UnifiedEvent key;
}
