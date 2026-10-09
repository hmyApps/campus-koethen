// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../core/locale/locale_providers.dart';
import '../../moodle/application/moodle_controller.dart';
import '../../moodle/application/moodle_providers.dart';
import '../../moodle/domain/moodle_deadline.dart';
import '../domain/notification_category.dart';
import '../domain/notification_preferences.dart';
import '../domain/notification_request.dart';
import 'notification_settings_controller.dart';

abstract interface class MoodleDeadlineReminderCopy {
  String get title;
  String get body;
}

/// Builds one privacy-neutral local reminder per future Moodle deadline.
///
/// The title, course and Moodle id never enter notification text or payload.
/// The opaque target is only a deterministic deduplication key. The tap target
/// is the Moodle overview, where the authenticated local cache can resolve the
/// actual deadline safely.
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
        target: _anonymousDeadlineKey(deadline),
        trigger: AbsoluteTrigger(reminderAt, before: deadline.dueAt),
        title: copy.title,
        body: copy.body,
        visibility: NotificationVisibility.neutral,
      ),
    );
  }
  return List<NotificationRequest>.unmodifiable(requests);
}

String _anonymousDeadlineKey(MoodleDeadline deadline) {
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
          ref.watch(moodleControllerProvider).value?.deadlines ??
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
