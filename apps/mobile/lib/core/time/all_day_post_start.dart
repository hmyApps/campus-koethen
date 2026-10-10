// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The date marker of an all-day event post's start (VF-N01).
///
/// A post's `eventStart` is a Strapi `datetime`: an all-day event entered as
/// 00:00 Berlin time arrives as 22:00Z/23:00Z the evening before. Every reader
/// takes an all-day start as a UTC-midnight date marker (`calendarDayOf`), so
/// such a start showed a day early and never matched its public-calendar twin.
/// It is therefore re-read as the local date it was entered for. A value that
/// already is UTC midnight is kept, so a server sending date markers is never
/// shifted.
///
/// Used for fresh API reads and for bookmarks stored before the fix alike.
DateTime allDayPostStart(DateTime start) {
  final DateTime utc = start.toUtc();
  if (utc == DateTime.utc(utc.year, utc.month, utc.day)) return utc;
  final DateTime local = start.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}
