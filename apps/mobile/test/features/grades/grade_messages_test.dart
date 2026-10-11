// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:campus_koethen/features/grades/presentation/grade_messages.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  // Audit 2026-10-10: the portal value is shown unchanged — never rounded to
  // one decimal (2,37 used to read as 2,4), but always with at least one.
  test('graded values keep every portal decimal and at least one', () {
    expect(gradeText(de, 'de', const Grade.graded(2.37)), '2,37');
    expect(gradeText(de, 'de', const Grade.graded(1.333)), '1,333');
    expect(gradeText(de, 'de', const Grade.graded(1.7)), '1,7');
    expect(gradeText(de, 'de', const Grade.graded(1)), '1,0');
    expect(gradeText(en, 'en', const Grade.graded(2.37)), '2.37');
    expect(gradeText(en, 'en', const Grade.graded(4)), '4.0');
  });
}
