// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Counts quick consecutive taps, for hidden developer options.
///
/// A pause longer than [gap] starts the count again, so scattered taps over a
/// session never add up by accident.
class TapStreak {
  TapStreak({
    this.taps = 10,
    this.gap = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int taps;
  final Duration gap;
  final DateTime Function() _clock;

  int count = 0;
  DateTime? _last;

  /// Registers one tap; `true` on the tap that completes the streak.
  bool tap() {
    final DateTime now = _clock();
    final DateTime? last = _last;
    if (last == null || now.difference(last) > gap) count = 0;
    _last = now;
    count++;
    if (count >= taps) {
      count = 0;
      _last = null;
      return true;
    }
    return false;
  }
}
