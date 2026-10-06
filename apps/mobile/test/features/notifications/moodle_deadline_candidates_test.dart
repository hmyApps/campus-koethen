// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/moodle/domain/moodle_deadline.dart';
import 'package:campus_koethen/features/notifications/application/moodle_deadline_candidates.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:flutter_test/flutter_test.dart';

class _Copy implements MoodleDeadlineReminderCopy {
  const _Copy();

  @override
  String get body => 'Open Moodle to view the deadline.';

  @override
  String get title => 'Moodle deadline approaching';
}

void main() {
  test('uses the configured absolute lead and neutral lock-screen text', () {
    final DateTime now = DateTime.utc(2026, 10, 6, 8);
    final DateTime due = DateTime.utc(2026, 10, 8, 12);
    final List<NotificationRequest> requests = moodleDeadlineRequests(
      deadlines: <MoodleDeadline>[
        MoodleDeadline(id: 42, title: 'Private title', dueAt: due),
      ],
      now: now,
      lead: const Duration(hours: 24),
      copy: const _Copy(),
    );

    expect(requests, hasLength(1));
    expect(requests.single.category, NotificationCategory.moodleDeadline);
    expect(
      (requests.single.trigger as AbsoluteTrigger).instant,
      DateTime.utc(2026, 10, 7, 12),
    );
    expect(requests.single.visibility, NotificationVisibility.neutral);
    expect(requests.single.title, isNot(contains('Private title')));
    expect(requests.single.target, isNot(contains('42')));
  });

  test('drops deadlines whose reminder moment is already past', () {
    final DateTime now = DateTime.utc(2026, 10, 6, 8);
    expect(
      moodleDeadlineRequests(
        deadlines: <MoodleDeadline>[
          MoodleDeadline(
            id: 1,
            title: 'Soon',
            dueAt: now.add(const Duration(hours: 2)),
          ),
        ],
        now: now,
        lead: const Duration(hours: 24),
        copy: const _Copy(),
      ),
      isEmpty,
    );
  });

  test('stable anonymous targets distinguish two deadlines', () {
    final DateTime now = DateTime.utc(2026, 10, 6, 8);
    final DateTime due = DateTime.utc(2026, 10, 8, 12);
    final List<NotificationRequest> requests = moodleDeadlineRequests(
      deadlines: <MoodleDeadline>[
        MoodleDeadline(id: 1, title: 'A', dueAt: due),
        MoodleDeadline(id: 2, title: 'B', dueAt: due),
      ],
      now: now,
      lead: const Duration(hours: 24),
      copy: const _Copy(),
    );

    expect(
      requests.map((NotificationRequest r) => r.target).toSet(),
      hasLength(2),
    );
  });
}
