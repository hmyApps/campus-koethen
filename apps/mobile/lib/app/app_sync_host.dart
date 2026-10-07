// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/foreground_refresh_scheduler.dart';
import '../features/calendar/application/public_calendar_providers.dart';
import '../features/contacts/application/contacts_providers.dart';
import '../features/mail/application/mail_account_controller.dart';
import '../features/mail/application/mail_sync_controller.dart';
import '../features/moodle/application/moodle_account_controller.dart';
import '../features/moodle/application/moodle_controller.dart';
import '../features/moodle/domain/moodle_account.dart';
import '../features/news/application/news_channel_feed_controller.dart';
import '../features/news/application/news_feed_controller.dart';
import '../features/news/application/news_providers.dart';
import '../features/timetable/application/timetable_providers.dart';
import '../features/timetable/application/timetable_week.dart';

const Duration kNewsForegroundSyncInterval = Duration(minutes: 5);
const Duration kCalendarForegroundSyncInterval = Duration(minutes: 10);
const Duration kTimetableForegroundSyncInterval = Duration(hours: 1);
const Duration kContactsForegroundSyncInterval = Duration(days: 1);

/// Owns the app-wide foreground refresh policies.
///
/// These timers are intentionally process-local: while the app is paused no
/// timer or network request is kept alive. A cold start always refreshes all
/// four API-backed areas plus Moodle and mail (when connected).
class AppSyncHost extends ConsumerStatefulWidget {
  const AppSyncHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppSyncHost> createState() => _AppSyncHostState();
}

class _AppSyncHostState extends ConsumerState<AppSyncHost>
    with WidgetsBindingObserver {
  late final List<ForegroundRefreshScheduler> _schedulers;
  late final MailLiveSyncController _mailLiveSync;

  @override
  void initState() {
    super.initState();
    // Keep the notifier itself: Riverpod refs are intentionally unavailable
    // during unmount, while stopping the owned socket is part of dispose.
    _mailLiveSync = ref.read(mailLiveSyncControllerProvider.notifier);
    _schedulers = <ForegroundRefreshScheduler>[
      ForegroundRefreshScheduler(
        interval: kNewsForegroundSyncInterval,
        resumeRefresh: ForegroundResumeRefresh.always,
        onRefresh: _refreshNews,
      ),
      ForegroundRefreshScheduler(
        interval: kCalendarForegroundSyncInterval,
        onRefresh: _refreshCalendars,
      ),
      ForegroundRefreshScheduler(
        interval: kTimetableForegroundSyncInterval,
        onRefresh: _refreshTimetable,
      ),
      ForegroundRefreshScheduler(
        interval: kContactsForegroundSyncInterval,
        onRefresh: _refreshContacts,
      ),
      ForegroundRefreshScheduler(
        interval: kMoodleAutoSyncInterval,
        onRefresh: _refreshMoodle,
      ),
      ForegroundRefreshScheduler(
        interval: kMailSyncInterval,
        onRefresh: _refreshMail,
      ),
    ];
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final ForegroundRefreshScheduler scheduler in _schedulers) {
        scheduler.start();
      }
      unawaited(_mailLiveSync.start());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final ForegroundRefreshScheduler scheduler in _schedulers) {
      scheduler.dispose();
    }
    unawaited(_mailLiveSync.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    for (final ForegroundRefreshScheduler scheduler in _schedulers) {
      scheduler.handleLifecycleState(state);
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_mailLiveSync.start());
    } else {
      unawaited(_mailLiveSync.stop());
    }
  }

  Future<void> _refreshNews() async {
    ref.invalidate(newsChannelFeedControllerProvider);
    ref.invalidate(newsChannelsProvider);
    ref.invalidate(newsTagsProvider);
    ref.invalidate(newsFeedControllerProvider);
    await ref.read(newsFeedControllerProvider.future);
  }

  Future<void> _refreshCalendars() async {
    ref.invalidate(publicCalendarsCatalogProvider);
    ref.invalidate(publicCalendarMonthEntriesProvider);
    await ref.read(publicCalendarsCatalogProvider.future);
  }

  Future<void> _refreshTimetable() async {
    ref.invalidate(timetableGroupsProvider);
    ref.invalidate(timetablePeriodsProvider);
    ref.invalidate(timetableModulesProvider);
    ref.invalidate(timetableWeekProvider);
    ref.invalidate(aggregatedTimetableWeekProvider);
    await ref.read(timetableGroupsProvider.future);
    await ref.read(timetablePeriodsProvider.future);

    final List<String> groupIds = ref.read(selectedTimetableGroupIdsProvider);
    if (groupIds.isEmpty) return;
    await ref.read(
      aggregatedTimetableWeekProvider(
        AggregatedTimetableWeekRequest(
          groupIds: groupIds,
          weekStart: TimetableWeek.startOf(DateTime.now()),
        ),
      ).future,
    );
  }

  Future<void> _refreshContacts() async {
    ref.invalidate(contactAreaProvider);
    ref.invalidate(contactAreasProvider);
    ref.invalidate(contactSearchIndexProvider);
    await Future.wait<Object?>(<Future<Object?>>[
      ref.read(contactAreasProvider.future),
      ref.read(contactSearchIndexProvider.future),
    ]);
  }

  Future<void> _refreshMoodle() =>
      ref.read(moodleControllerProvider.notifier).maybeAutoSync();

  Future<void> _refreshMail() =>
      ref.read(mailSyncControllerProvider.notifier).syncNow();

  @override
  Widget build(BuildContext context) {
    // The account is restored asynchronously. If the startup scheduler ran
    // before that finished, sync as soon as the connection becomes available.
    ref.listen<AsyncValue<MoodleAccount?>>(moodleAccountControllerProvider, (
      AsyncValue<MoodleAccount?>? previous,
      AsyncValue<MoodleAccount?> next,
    ) {
      final bool wasConnected = previous?.value != null;
      if (!wasConnected && next.value != null) {
        unawaited(_refreshMoodle());
      }
    });
    // Mail credentials are restored asynchronously as well. The scheduled
    // startup attempt can therefore be a no-op before the account is ready.
    ref.listen<AsyncValue<MailAccountState>>(mailAccountControllerProvider, (
      AsyncValue<MailAccountState>? previous,
      AsyncValue<MailAccountState> next,
    ) {
      final bool wasSignedIn = previous?.value?.isSignedIn ?? false;
      final bool isSignedIn = next.value?.isSignedIn ?? false;
      if (!wasSignedIn && isSignedIn) {
        unawaited(_refreshMail());
        unawaited(_mailLiveSync.start());
      } else if (wasSignedIn && !isSignedIn) {
        unawaited(_mailLiveSync.stop());
      }
    });
    return widget.child;
  }
}
