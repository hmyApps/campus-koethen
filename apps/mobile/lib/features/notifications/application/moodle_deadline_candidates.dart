// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../core/locale/locale_providers.dart';
import '../../moodle/application/moodle_account_controller.dart';
import '../../moodle/application/moodle_controller.dart';
import '../../moodle/application/moodle_providers.dart';
import '../../moodle/domain/moodle_deadline.dart';
import '../domain/notification_category.dart';
import '../domain/notification_preferences.dart';
import '../domain/notification_request.dart';
import 'event_reminder_candidates.dart' show kNotificationTapSourceTimeout;
import 'notification_settings_controller.dart';

abstract interface class MoodleDeadlineReminderCopy {
  String get title;
  String get body;
}

/// Builds one privacy-neutral local reminder per future Moodle deadline.
///
/// The title, course and Moodle id never enter notification text or payload.
/// The opaque target is a deterministic key. A tap resolves it against the
/// local deadline cache ([findMoodleDeadlineForNotification]) and opens the
/// calendar on the day the deadline is due.
///
/// The trigger names the deadline as its target, so the planner's delivery
/// window can never move the reminder onto or past it (F-02).
List<NotificationRequest> moodleDeadlineRequests({
  required Iterable<MoodleDeadline> deadlines,
  required DateTime now,
  required Duration lead,
  required MoodleDeadlineReminderCopy copy,
}) {
  if (lead <= Duration.zero) return const <NotificationRequest>[];
  final List<NotificationRequest> requests = <NotificationRequest>[];
  for (final MoodleDeadline deadline in deadlines) {
    if (!deadline.dueAt.isAfter(now)) continue;
    final DateTime reminderAt = deadline.dueAt.subtract(lead);
    if (!reminderAt.isAfter(now)) continue;
    requests.add(
      NotificationRequest(
        category: NotificationCategory.moodleDeadline,
        target: moodleDeadlineNotificationKey(deadline),
        trigger: AbsoluteTrigger(reminderAt, before: deadline.dueAt),
        title: copy.title,
        body: copy.body,
        visibility: NotificationVisibility.neutral,
      ),
    );
  }
  return List<NotificationRequest>.unmodifiable(requests);
}

/// The deadline among [deadlines] whose reminder carries [target], or `null`.
MoodleDeadline? findMoodleDeadlineForNotification(
  Iterable<MoodleDeadline> deadlines,
  String target,
) {
  for (final MoodleDeadline deadline in deadlines) {
    if (moodleDeadlineNotificationKey(deadline) == target) return deadline;
  }
  return null;
}

/// The local day a tapped deadline reminder should open the calendar on, or
/// `null` when its deadline is no longer in the local cache.
///
/// Waits — bounded, like the event-reminder lookup — for the Moodle account
/// and overview cache to load, because a cold start from the notification
/// reads them before either has.
Future<DateTime?> loadMoodleDeadlineDayForNotification(
  ProviderContainer container,
  String target, {
  Duration timeout = kNotificationTapSourceTimeout,
}) async {
  Future<void> settled(Future<Object?> source) =>
      source.then<void>((_) {}, onError: (Object _) {});
  await (() async {
    await settled(container.read(moodleAccountControllerProvider.future));
    await settled(container.read(moodleControllerProvider.future));
  })().timeout(timeout, onTimeout: () {});
  final MoodleDeadline? deadline = findMoodleDeadlineForNotification(
    container.read(moodleControllerProvider).value?.deadlines ??
        const <MoodleDeadline>[],
    target,
  );
  if (deadline == null) return null;
  final DateTime local = deadline.dueAt.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// The opaque payload target of [deadline]'s reminder.
String moodleDeadlineNotificationKey(MoodleDeadline deadline) {
  final String source =
      '${deadline.id}|${deadline.dueAt.toUtc().toIso8601String()}';
  int hash = 0x811c9dc5;
  for (final int unit in source.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return 'deadline-${hash.toRadixString(36)}';
}

final Provider<List<NotificationRequest>> moodleDeadlineCandidatesProvider =
    Provider<List<NotificationRequest>>((Ref ref) {
      final NotificationPreferences preferences = ref.watch(
        notificationSettingsProvider,
      );
      final List<MoodleDeadline> deadlines =
          ref.watch(moodleControllerProvider).value?.reminderDeadlines ??
          const <MoodleDeadline>[];
      return moodleDeadlineRequests(
        deadlines: deadlines,
        now: ref.watch(moodleClockProvider).now(),
        lead: Duration(minutes: preferences.moodleDeadlineLeadMinutes),
        copy: LocalisedMoodleDeadlineReminderCopy(
          lookupAppLocalizations(ref.watch(activeLocaleProvider)),
        ),
      );
    });

class LocalisedMoodleDeadlineReminderCopy
    implements MoodleDeadlineReminderCopy {
  const LocalisedMoodleDeadlineReminderCopy(this.l10n);

  final AppLocalizations l10n;

  @override
  String get title => l10n.notificationMoodleDeadlineTitle;

  @override
  String get body => l10n.notificationMoodleDeadlineBody;
}
