// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'news_feed_controller.dart';
import 'news_providers.dart';

/// The app-wide foreground refresh of the news feeds.
///
/// The state is a tick that every live channel feed listens to. A feed that
/// was scrolled past its first page ignores the tick: reloading it would drop
/// the reader back to the top, every five minutes and on every resume. Pull to
/// refresh stays the explicit way back to page one.
class NewsAutoRefresh extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> run() async {
    final bool mainFeedScrolled =
        (ref.read(newsFeedControllerProvider).value?.page ?? 1) > 1;
    state = state + 1;
    // The main feed watches both catalogues, so refreshing them would rebuild
    // it as well.
    if (mainFeedScrolled) return;
    ref.invalidate(newsChannelsProvider);
    ref.invalidate(newsTagsProvider);
    ref.invalidate(newsFeedControllerProvider);
    await ref.read(newsFeedControllerProvider.future);
  }
}

final NotifierProvider<NewsAutoRefresh, int> newsAutoRefreshProvider =
    NotifierProvider<NewsAutoRefresh, int>(NewsAutoRefresh.new);
