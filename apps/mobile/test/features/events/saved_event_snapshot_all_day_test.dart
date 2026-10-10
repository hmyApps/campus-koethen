// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/events/domain/saved_event_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bookmarks written before VF-N01 hold an all-day post start as the instant
/// of local midnight (22:00Z/23:00Z the evening before). Reading them must
/// yield the same UTC-midnight date marker a fresh API read does, so an old
/// bookmark no longer shows its event a day early.
///
/// Inputs are built from local midnight like the other all-day tests: on a
/// machine in Europe/Berlin (CI pins TZ) they reproduce the stored instant.
Map<String, Object?> _stored({
  required String kind,
  required DateTime start,
  required bool allDay,
}) => <String, Object?>{
  'eventRef': '$kind:beispiel',
  'kind': kind,
  'title': 'Beispiel',
  'start': start.toUtc().toIso8601String(),
  'allDay': allDay,
  'savedAt': DateTime.utc(2026, 7, 1).toIso8601String(),
};

void main() {
  test('an all-day post bookmarked before the fix reads as its own date', () {
    final SavedEventSnapshot? snapshot = SavedEventSnapshot.fromJson(
      _stored(kind: 'post-event', start: DateTime(2026, 7, 21), allDay: true),
    );

    expect(snapshot!.start, DateTime.utc(2026, 7, 21));
  });

  test('a stored UTC-midnight marker is kept as it is', () {
    final SavedEventSnapshot? snapshot = SavedEventSnapshot.fromJson(
      _stored(
        kind: 'post-event',
        start: DateTime.utc(2026, 7, 21),
        allDay: true,
      ),
    );

    expect(snapshot!.start, DateTime.utc(2026, 7, 21));
  });

  test('timed posts and calendar events are never shifted', () {
    final DateTime timed = DateTime.utc(2026, 7, 20, 22, 30);
    final SavedEventSnapshot? post = SavedEventSnapshot.fromJson(
      _stored(kind: 'post-event', start: timed, allDay: false),
    );
    final SavedEventSnapshot? calendar = SavedEventSnapshot.fromJson(
      _stored(kind: 'calendar-event', start: timed, allDay: true),
    );

    expect(post!.start, timed);
    expect(calendar!.start, timed);
  });
}
