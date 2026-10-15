// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../l10n/l10n.dart';
import '../domain/notification_category.dart';
import '../domain/notification_gateway.dart';

/// The Android channels, named in the app language.
///
/// Channel names are reader-visible strings in the Android system settings, so
/// they follow the app language. Re-registering a channel under the same id is
/// how Android takes over a new name; the reader's own sound and importance
/// choices survive it. Shared by the running app and the background run, which
/// both have to make sure the channels exist before they show anything.
List<NotificationChannelSpec> notificationChannelSpecs(AppLocalizations l10n) {
  return <NotificationChannelSpec>[
    NotificationChannelSpec(
      category: NotificationCategory.dailySummary,
      name: l10n.notificationChannelDailySummaryName,
      description: l10n.notificationChannelDailySummaryDescription,
    ),
    NotificationChannelSpec(
      category: NotificationCategory.eventReminder,
      name: l10n.notificationChannelEventsName,
      description: l10n.notificationChannelEventsDescription,
    ),
    NotificationChannelSpec(
      category: NotificationCategory.canteenFavourite,
      name: l10n.notificationChannelCanteenName,
      description: l10n.notificationChannelCanteenDescription,
    ),
    NotificationChannelSpec(
      category: NotificationCategory.moodleDeadline,
      name: l10n.notificationChannelMoodleDeadlineName,
      description: l10n.notificationChannelMoodleDeadlineDescription,
    ),
    NotificationChannelSpec(
      category: NotificationCategory.gradeChange,
      name: l10n.notificationChannelGradeChangeName,
      description: l10n.notificationChannelGradeChangeDescription,
    ),
    NotificationChannelSpec(
      category: NotificationCategory.newMail,
      name: l10n.notificationChannelMailName,
      description: l10n.notificationChannelMailDescription,
    ),
  ];
}
