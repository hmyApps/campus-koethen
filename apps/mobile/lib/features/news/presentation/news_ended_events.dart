// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/news_feed_view_options.dart';
import '../data/news_models.dart';
import '../domain/news_feed_arrangement.dart';

/// Keeps a news list honest about which event posts have ended.
///
/// "Now" is read afresh on every build, so any rebuild re-evaluates the
/// rule. On top of that a resume rebuilds (a boundary can pass while the app
/// sits in the background) and exactly **one** timer is armed for the next
/// end among the loaded event posts — never polling.
mixin NewsEndedEventsRefresh<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, WidgetsBindingObserver {
  Timer? _endedTimer;
  DateTime? _armedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _endedTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  /// The instant the feed is evaluated at; call once per build.
  DateTime feedNow() => ref.read(newsFeedClockProvider).now();

  /// Arms (or re-arms) the single timer for the next end among [loaded].
  void syncEndedEventsTimer(List<NewsArticle> loaded, DateTime now) {
    final DateTime? next = nextNewsFeedBoundary(loaded, now: now);
    if (next == _armedFor) return;
    _endedTimer?.cancel();
    _endedTimer = null;
    _armedFor = next;
    if (next == null) return;
    final Duration wait = next.difference(now);
    _endedTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _armedFor = null;
      _endedTimer = null;
      if (mounted) setState(() {});
    });
  }
}

/// "Ältere Events anzeigen (n)" / "Ältere Events ausblenden".
///
/// Sits at the end of the loaded list (and in the empty state when every
/// loaded post is an ended event). The count is the number of loaded ended
/// event posts currently hidden.
class NewsEndedEventsToggle extends ConsumerWidget {
  const NewsEndedEventsToggle({
    required this.scope,
    required this.arrangement,
    super.key,
  });

  /// A [NewsFeedScopeKey] value.
  final String scope;
  final NewsFeedArrangement arrangement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool showing = ref.watch(newsShowEndedEventsProvider(scope));
    return Center(
      child: OutlinedButton.icon(
        onPressed: () =>
            ref.read(newsShowEndedEventsProvider(scope).notifier).toggle(),
        icon: Icon(
          showing
              ? AppIcons.visibility_off_outlined
              : AppIcons.visibility_outlined,
        ),
        label: Text(
          showing
              ? l10n.newsHideEndedEvents
              : l10n.newsShowEndedEvents(arrangement.hiddenEndedCount),
        ),
      ),
    );
  }
}

/// The empty state for a list whose every loaded post is an ended event:
/// the reveal toggle as its action and, while more pages exist, the
/// load-more [footer] so pagination keeps going without a visible item.
Widget newsAllEventsEndedView(
  BuildContext context, {
  required Widget toggle,
  Widget? footer,
}) {
  final AppLocalizations l10n = context.l10n;
  return EmptyView(
    icon: AppIcons.event_outlined,
    title: l10n.newsAllEventsEndedTitle,
    message: l10n.newsAllEventsEndedMessage,
    action: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        toggle,
        if (footer != null) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          footer,
        ],
      ],
    ),
  );
}
