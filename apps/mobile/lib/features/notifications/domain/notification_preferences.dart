// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import 'notification_category.dart';

/// The reader's own notification settings, entirely on the device.
///
/// Nothing here is ever registered, synchronised or transmitted: there is no
/// account, no installation record and no recipient (ADR-0001 § 10).
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.optedIn = false,
    this.disabledCategories = const <NotificationCategory>{},
    this.prePromptDeclined = false,
    this.dailySummaryMinutes = 8 * 60,
    this.moodleDeadlineLeadMinutes = 24 * 60,
  });

  /// The global switch. `false` until the reader has explicitly opted in in
  /// the final onboarding step or at a later contextual entry point (P2, UX
  /// spec § 2.1).
  final bool optedIn;

  /// The categories the reader switched **off**.
  ///
  /// Stored as the off-set rather than the on-set, for the same reason the
  /// calendar stores its disabled sources: after the opt-in every category is
  /// on (P2), and a category added in a later version must be on as well
  /// instead of invisible until someone finds the switch.
  final Set<NotificationCategory> disabledCategories;

  /// Whether the reader has already answered "not now" to the in-app
  /// pre-permission sheet. It keeps a contextual trigger point from asking
  /// again on every saved event; the switch in the settings always asks.
  final bool prePromptDeclined;

  /// Preferred local wall-clock minute, in the range 0..1439.
  final int dailySummaryMinutes;

  /// Local lead time for each Moodle deadline reminder.
  final int moodleDeadlineLeadMinutes;

  bool isCategoryEnabled(NotificationCategory category) =>
      !disabledCategories.contains(category);

  /// The categories that may currently produce notifications, in enum order.
  Set<NotificationCategory> get enabledCategories => <NotificationCategory>{
    for (final NotificationCategory c in NotificationCategory.values)
      if (isCategoryEnabled(c)) c,
  };

  NotificationPreferences copyWith({
    bool? optedIn,
    Set<NotificationCategory>? disabledCategories,
    bool? prePromptDeclined,
    int? dailySummaryMinutes,
    int? moodleDeadlineLeadMinutes,
  }) => NotificationPreferences(
    optedIn: optedIn ?? this.optedIn,
    disabledCategories: disabledCategories ?? this.disabledCategories,
    prePromptDeclined: prePromptDeclined ?? this.prePromptDeclined,
    dailySummaryMinutes: dailySummaryMinutes ?? this.dailySummaryMinutes,
    moodleDeadlineLeadMinutes:
        moodleDeadlineLeadMinutes ?? this.moodleDeadlineLeadMinutes,
  );

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      other.optedIn == optedIn &&
      other.prePromptDeclined == prePromptDeclined &&
      other.dailySummaryMinutes == dailySummaryMinutes &&
      other.moodleDeadlineLeadMinutes == moodleDeadlineLeadMinutes &&
      other.disabledCategories.length == disabledCategories.length &&
      other.disabledCategories.containsAll(disabledCategories);

  @override
  int get hashCode => Object.hash(
    optedIn,
    prePromptDeclined,
    dailySummaryMinutes,
    moodleDeadlineLeadMinutes,
    Object.hashAllUnordered(disabledCategories),
  );
}
