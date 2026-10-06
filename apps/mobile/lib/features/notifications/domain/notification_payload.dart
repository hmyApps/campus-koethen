// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'notification_category.dart';

/// The versioned string a scheduled notification carries, so a tap can be
/// routed back to what it was about — ADR-0001 § 7.8.
///
/// Shape: `v1|<category key>|<target>`.
///
/// Three properties are deliberate and load-bearing:
///
/// * **No path, no URL.** The route is built by the app from [category] and
///   [target]; a payload that named a route would keep pointing at it after a
///   release renamed or removed it.
/// * **No personal identifier and no secret.** Moodle reminders use an opaque
///   local target and grade alerts use only the constant `grades`, so the
///   operating system never stores a title, course, grade, username or raw id.
/// * **Versioned and validated.** A payload outlives the app version that
///   wrote it. [tryParse] returns `null` for anything it does not fully
///   understand, and the caller falls back rather than guessing.
@immutable
class NotificationPayload {
  const NotificationPayload({required this.category, required this.target});

  /// The only payload version this app version writes.
  static const String version = 'v1';

  static const String _separator = '|';

  final NotificationCategory category;

  /// What the notification is about, in the category's own key vocabulary —
  /// a `CalendarEntry.id` for N1, a `YYYY-MM-DD` day for N2, a
  /// `<canteenSlug>:<YYYY-MM-DD>` pair for N3 (optionally followed by a dish),
  /// an opaque Moodle key, or the constant `grades`.
  ///
  /// Never empty, and never contains the separator: both are rejected on
  /// construction through [tryParse] and asserted by [toStorage].
  final String target;

  /// The wire form. Round-trips through [tryParse].
  String toStorage() {
    assert(
      target.isNotEmpty && !target.contains(_separator),
      'A payload target must be non-empty and free of "$_separator".',
    );
    return '$version$_separator${category.key}$_separator$target';
  }

  /// Parses a payload written by this or an earlier app version, or returns
  /// `null` when it cannot be resolved with certainty.
  ///
  /// Returns `null` — never throws, never guesses — for a null or empty
  /// string, an unknown version, an unknown category, a missing target and a
  /// malformed shape. Every one of those is a real possibility: the payload
  /// was written by a version of the app that no longer exists.
  static NotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    // Exactly three parts: a target that itself contains the separator would
    // otherwise be silently truncated into a different target.
    final List<String> parts = raw.split(_separator);
    if (parts.length != 3) return null;
    if (parts[0] != version) return null;
    final NotificationCategory? category = NotificationCategory.fromKey(
      parts[1],
    );
    if (category == null) return null;
    final String target = parts[2];
    if (target.isEmpty) return null;
    return NotificationPayload(category: category, target: target);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPayload &&
      other.category == category &&
      other.target == target;

  @override
  int get hashCode => Object.hash(category, target);

  @override
  String toString() => 'NotificationPayload(${category.key})';
}
