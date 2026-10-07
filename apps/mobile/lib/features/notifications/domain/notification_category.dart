// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The notification categories the product release (LEVIORA-159) approved.
///
/// The set is closed: adding a value here is a product decision, not a
/// refactoring. New mail is an immediate, privacy-neutral signal; the other
/// categories are planned ahead by the local scheduler.
///
/// Every category carries its own identity in three places, and all three are
/// stable across app updates because they end up inside data the operating
/// system keeps:
///
/// * [key] — what a notification payload names (`v1|<key>|<target>`),
/// * [keyPrefix] — the first segment of a notification key (`n1:` … `n4:`),
/// * [channelId] — the Android notification channel.
///
/// [order] is the tie-breaker of the planner's deterministic sort, so two
/// notifications due at the very same instant always survive the budget in the
/// same order — see `notification_planner.dart`.
enum NotificationCategory {
  /// N1 · `event.reminder` — at most one reminder with the global or
  /// event-specific lead for a public or saved event.
  eventReminder(
    key: 'event.reminder',
    keyPrefix: 'n1',
    channelId: 'events_channel',
    storageValue: 'events',
    order: 0,
    windowPolicy: DeliveryWindowPolicy.shiftIntoWindow,
  ),

  /// N2 · `daily.summary` — the overview at the reader's chosen local time.
  dailySummary(
    key: 'daily.summary',
    keyPrefix: 'n2',
    channelId: 'summary_channel',
    storageValue: 'summary',
    order: 1,
    windowPolicy: DeliveryWindowPolicy.anyLocalTime,
  ),

  /// N3 · `canteen.favourite` — the 11:00 hint about a favourite dish (P6).
  canteenFavourite(
    key: 'canteen.favourite',
    keyPrefix: 'n3',
    channelId: 'canteen_channel',
    storageValue: 'canteen',
    order: 2,
    windowPolicy: DeliveryWindowPolicy.fixedLocalTime,
  ),

  /// N4 · `mail.new` — an immediate, content-neutral hint after IMAP reports
  /// a new message and the inbox reconciliation confirms it.
  newMail(
    key: 'mail.new',
    keyPrefix: 'n4',
    channelId: 'mail_channel',
    storageValue: 'mail',
    order: 3,
    windowPolicy: DeliveryWindowPolicy.anyLocalTime,
  );

  const NotificationCategory({
    required this.key,
    required this.keyPrefix,
    required this.channelId,
    required this.storageValue,
    required this.order,
    required this.windowPolicy,
  });

  /// The category identifier used in a notification payload.
  final String key;

  /// First segment of every scheduling key of this category.
  final String keyPrefix;

  /// The Android notification channel this category posts to. One channel
  /// one per category, so a reader can silence one kind without silencing the
  /// rest. A channel is **not** a group key and does not bundle anything
  /// (ADR-0001 § 7.7, P8).
  final String channelId;

  /// Stable identifier for local storage, never the enum index.
  final String storageValue;

  /// Position in the planner's category tie-break order.
  final int order;

  /// How the delivery window (P7) applies to this category.
  final DeliveryWindowPolicy windowPolicy;

  static NotificationCategory? fromKey(String? value) {
    for (final NotificationCategory category in NotificationCategory.values) {
      if (category.key == value) return category;
    }
    return null;
  }

  static NotificationCategory? fromStorage(String? value) {
    for (final NotificationCategory category in NotificationCategory.values) {
      if (category.storageValue == value) return category;
    }
    return null;
  }
}

/// How a category relates to the 07:00–20:00 delivery window (P7).
enum DeliveryWindowPolicy {
  /// A time explicitly selected by the reader, including overnight hours.
  anyLocalTime,

  /// The desired instant is derived from a source date minus a configured
  /// lead, so it can fall outside the window and must be shifted safely.
  shiftIntoWindow,

  /// The category names a fixed local wall-clock time that lies inside the
  /// window by construction (the 11:00 canteen hint). Nothing is shifted; a request
  /// outside the window is a programming error and is dropped with a
  /// diagnostic rather than silently moved.
  fixedLocalTime,
}
