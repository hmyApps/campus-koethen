// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../data/timetable_models.dart';

class TimetableSemesterSuggestion {
  const TimetableSemesterSuggestion({
    required this.previous,
    required this.next,
    required this.candidates,
  });

  final TimetablePeriod previous;
  final TimetablePeriod next;
  final List<TimetableGroup> candidates;
}

TimetableSemesterSuggestion? semesterSuggestion({
  required List<TimetablePeriod> periods,
  required String? selectedGroupId,
  required DateTime now,
  String? dismissedPeriodId,
}) {
  if (selectedGroupId == null) return null;
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<TimetablePeriod> ordered = List<TimetablePeriod>.of(periods)
    ..sort((a, b) => a.validFrom.compareTo(b.validFrom));

  TimetablePeriod? previous;
  for (final TimetablePeriod period in ordered) {
    if (period.containsGroup(selectedGroupId) &&
        period.validTo.isBefore(today)) {
      previous = period;
    }
  }
  if (previous == null) return null;

  TimetablePeriod? next;
  for (final TimetablePeriod period in ordered) {
    if (period.validFrom.isAfter(previous.validTo) &&
        !period.validTo.isBefore(today) &&
        period.groups.isNotEmpty) {
      next = period;
      break;
    }
  }
  if (next == null || next.id == dismissedPeriodId) return null;
  if (next.containsGroup(selectedGroupId)) return null;

  final TimetableGroup? selected = previous.groups
      .where((group) => group.id == selectedGroupId)
      .firstOrNull;
  if (selected == null) return null;
  final List<TimetableGroup> candidates = List<TimetableGroup>.of(next.groups)
    ..sort((a, b) {
      final int score =
          _groupSimilarity(selected, b) - _groupSimilarity(selected, a);
      return score != 0 ? score : a.shortName.compareTo(b.shortName);
    });
  return TimetableSemesterSuggestion(
    previous: previous,
    next: next,
    candidates: List<TimetableGroup>.unmodifiable(candidates),
  );
}

int _groupSimilarity(TimetableGroup current, TimetableGroup candidate) {
  int score =
      current.department != null && current.department == candidate.department
      ? 20
      : 0;
  final String currentPrefix = _shortPrefix(current.shortName);
  final String candidatePrefix = _shortPrefix(candidate.shortName);
  if (currentPrefix.isNotEmpty && currentPrefix == candidatePrefix) {
    score += 100;
  }

  final Set<String> currentWords = _words(
    current.longName ?? current.shortName,
  );
  final Set<String> candidateWords = _words(
    candidate.longName ?? candidate.shortName,
  );
  score += currentWords.intersection(candidateWords).length * 4;
  return score;
}

String _shortPrefix(String value) {
  final Match? match = RegExp(
    r'^\s*([^\d\s_-]+)',
    unicode: true,
  ).firstMatch(value);
  return (match?.group(1) ?? '').toLowerCase();
}

Set<String> _words(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\d+'), ' ')
    .split(RegExp(r'[^\p{L}]+', unicode: true))
    .where((word) => word.length >= 3)
    .toSet();
