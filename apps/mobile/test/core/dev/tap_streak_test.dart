// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/dev/tap_streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  TapStreak streak({int taps = 10}) => TapStreak(taps: taps, clock: () => now);

  setUp(() => now = DateTime(2026, 10, 16, 12));

  test('fires on the tenth quick tap, not before', () {
    final TapStreak s = streak();
    for (int i = 0; i < 9; i++) {
      now = now.add(const Duration(milliseconds: 300));
      expect(s.tap(), isFalse, reason: 'tap ${i + 1}');
    }
    now = now.add(const Duration(milliseconds: 300));
    expect(s.tap(), isTrue);
  });

  test('a pause starts the count again', () {
    final TapStreak s = streak();
    for (int i = 0; i < 9; i++) {
      s.tap();
    }
    now = now.add(const Duration(seconds: 3));

    expect(s.tap(), isFalse, reason: 'this is tap 1 of a new streak');
    expect(s.count, 1);
  });

  test('after firing it starts from zero', () {
    final TapStreak s = streak(taps: 3);
    s.tap();
    s.tap();
    expect(s.tap(), isTrue);

    expect(s.count, 0);
    expect(s.tap(), isFalse);
  });
}
