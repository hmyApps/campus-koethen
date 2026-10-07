// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/timetable/application/semester_assistant.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_test/flutter_test.dart';

const TimetableGroup oldGroup = TimetableGroup(
  id: 'old',
  shortName: 'AIN2',
  longName: 'Angewandte Informatik 2. Semester',
  department: 'FB5',
);
const TimetableGroup likelyNext = TimetableGroup(
  id: 'next',
  shortName: 'AIN3',
  longName: 'Angewandte Informatik 3. Semester',
  department: 'FB5',
);
const TimetableGroup unrelated = TimetableGroup(
  id: 'other',
  shortName: 'MB3',
  longName: 'Maschinenbau 3. Semester',
  department: 'FB6',
);

List<TimetablePeriod> periods() => <TimetablePeriod>[
  TimetablePeriod(
    id: 'summer',
    name: 'Sommer 2026',
    validFrom: DateTime(2026, 4, 7),
    validTo: DateTime(2026, 9, 30),
    groups: const <TimetableGroup>[oldGroup],
  ),
  TimetablePeriod(
    id: 'winter',
    name: 'Winter 2026/27',
    validFrom: DateTime(2026, 10, 5),
    validTo: DateTime(2027, 3, 31),
    groups: const <TimetableGroup>[unrelated, likelyNext],
  ),
];

void main() {
  test('does not suggest before the selected semester ended', () {
    expect(
      semesterSuggestion(
        periods: periods(),
        selectedGroupId: oldGroup.id,
        now: DateTime(2026, 9, 30, 23, 59),
      ),
      isNull,
    );
  });

  test('suggests the available next semester after the old one ended', () {
    final TimetableSemesterSuggestion result = semesterSuggestion(
      periods: periods(),
      selectedGroupId: oldGroup.id,
      now: DateTime(2026, 10, 1),
    )!;

    expect(result.next.id, 'winter');
    expect(result.candidates.first.id, likelyNext.id);
  });

  test('a dismissal is scoped to this one upcoming period', () {
    expect(
      semesterSuggestion(
        periods: periods(),
        selectedGroupId: oldGroup.id,
        now: DateTime(2026, 10, 1),
        dismissedPeriodId: 'winter',
      ),
      isNull,
    );
  });

  test('skips expired intermediate semesters after a long absence', () {
    final List<TimetablePeriod> history = <TimetablePeriod>[
      ...periods(),
      TimetablePeriod(
        id: 'summer-2027',
        name: 'Sommer 2027',
        validFrom: DateTime(2027, 4, 1),
        validTo: DateTime(2027, 9, 30),
        groups: const <TimetableGroup>[likelyNext],
      ),
    ];

    final TimetableSemesterSuggestion result = semesterSuggestion(
      periods: history,
      selectedGroupId: oldGroup.id,
      now: DateTime(2027, 4, 2),
    )!;

    expect(result.next.id, 'summer-2027');
  });

  test(
    'does not ask when the selected group already belongs to the next period',
    () {
      final List<TimetablePeriod> shared = periods();
      shared[1] = TimetablePeriod(
        id: shared[1].id,
        name: shared[1].name,
        validFrom: shared[1].validFrom,
        validTo: shared[1].validTo,
        groups: const <TimetableGroup>[oldGroup, likelyNext],
      );
      expect(
        semesterSuggestion(
          periods: shared,
          selectedGroupId: oldGroup.id,
          now: DateTime(2026, 10, 1),
        ),
        isNull,
      );
    },
  );
}
