// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/notifications/application/canteen_favourite_candidates.dart';
import 'package:campus_koethen/features/notifications/application/daily_summary_providers.dart';
import 'package:campus_koethen/features/notifications/application/event_reminder_candidates.dart';
import 'package:campus_koethen/features/notifications/application/notification_providers.dart';
import 'package:campus_koethen/features/notifications/application/moodle_deadline_candidates.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationRequest request(NotificationCategory category) =>
    NotificationRequest(
      category: category,
      target: category.key,
      trigger: LocalTimeTrigger(day: DateTime(2026, 8, 25), hour: 11),
      title: category.key,
      body: category.key,
    );

void main() {
  test('the aggregate keeps every scheduled category after parallel merges', () {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        eventReminderCandidatesProvider.overrideWithValue(<NotificationRequest>[
          request(NotificationCategory.eventReminder),
        ]),
        dailySummaryCandidatesProvider.overrideWithValue(<NotificationRequest>[
          request(NotificationCategory.dailySummary),
        ]),
        canteenFavouriteCandidatesProvider.overrideWithValue(
          <NotificationRequest>[request(NotificationCategory.canteenFavourite)],
        ),
        moodleDeadlineCandidatesProvider.overrideWithValue(
          <NotificationRequest>[request(NotificationCategory.moodleDeadline)],
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container
          .read(notificationCandidatesProvider)
          .map((NotificationRequest candidate) => candidate.category),
      const <NotificationCategory>[
        NotificationCategory.eventReminder,
        NotificationCategory.dailySummary,
        NotificationCategory.canteenFavourite,
        NotificationCategory.moodleDeadline,
      ],
    );
  });
}
