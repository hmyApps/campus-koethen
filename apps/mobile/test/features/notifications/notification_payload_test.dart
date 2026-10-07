// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_payload.dart';
import 'package:flutter_test/flutter_test.dart';

/// A payload outlives the app version that wrote it — it sits in the operating
/// system's notification store until the notification is delivered or the app
/// is uninstalled. Everything here is about what happens when a *newer* app
/// reads an *older* string.

void main() {
  group('round trip', () {
    test('every category survives being written and read back', () {
      for (final NotificationCategory category in NotificationCategory.values) {
        const String target = 'savedEvent:calendar:4711';
        final NotificationPayload payload = NotificationPayload(
          category: category,
          target: target,
        );
        expect(NotificationPayload.tryParse(payload.toStorage()), payload);
      }
    });

    test('the wire form is the documented one', () {
      expect(
        const NotificationPayload(
          category: NotificationCategory.dailySummary,
          target: '2026-09-03',
        ).toStorage(),
        'v1|daily.summary|2026-09-03',
      );
    });
  });

  group('a payload from a version that no longer exists', () {
    test('an unknown version resolves to nothing rather than to a guess', () {
      expect(
        NotificationPayload.tryParse('v2|daily.summary|2026-09-03'),
        isNull,
      );
      expect(NotificationPayload.tryParse('|daily.summary|2026-09-03'), isNull);
    });

    test('a category this version has dropped resolves to nothing', () {
      // K3/K4/K6 were dropped by P5 — a build from before that could have
      // scheduled one, and its payload is still out there.
      expect(
        NotificationPayload.tryParse('v1|timetable.reminder|timetable:9'),
        isNull,
      );
      expect(NotificationPayload.tryParse('v1|moodle.deadline|4711'), isNull);
    });

    test('a malformed shape never throws and never half-parses', () {
      for (final String? raw in <String?>[
        null,
        '',
        'v1',
        'v1|daily.summary',
        'v1|daily.summary|',
        'v1|daily.summary|a|b',
        '||',
        'complete nonsense',
      ]) {
        expect(
          NotificationPayload.tryParse(raw),
          isNull,
          reason: 'must not resolve: $raw',
        );
      }
    });
  });

  group('privacy', () {
    test('no category key names a study-record data source', () {
      // P5 removed every individual Moodle and timetable reminder, so no
      // payload can carry a study identifier at all (ADR-0001 § 7.8).
      for (final NotificationCategory category in NotificationCategory.values) {
        expect(category.key, isNot(contains('moodle')));
        expect(category.key, isNot(contains('grade')));
      }
    });

    test('new-mail payload carries only an IMAP UID', () {
      const NotificationPayload payload = NotificationPayload(
        category: NotificationCategory.newMail,
        target: '4711',
      );
      expect(payload.toStorage(), 'v1|mail.new|4711');
      expect(payload.toStorage(), isNot(contains('@')));
    });

    test('the diagnostic form names the category and nothing else', () {
      const NotificationPayload payload = NotificationPayload(
        category: NotificationCategory.canteenFavourite,
        target: 'mensa-fasanerieallee:2026-09-03',
      );
      expect(payload.toString(), isNot(contains('mensa-fasanerieallee')));
      expect(payload.toString(), contains('canteen.favourite'));
    });
  });
}
