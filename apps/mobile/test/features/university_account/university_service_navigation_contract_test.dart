// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Map<String, String> serviceScreens = <String, String>{
    'lib/features/mail/presentation/mail_screen.dart':
        'const MailSetupScreen()',
    'lib/features/moodle/presentation/moodle_screen.dart':
        'const MoodleSetupScreen()',
    'lib/features/grades/presentation/grades_screen.dart':
        'const GradeSetupScreen()',
  };

  for (final MapEntry<String, String> entry in serviceScreens.entries) {
    test('${entry.key} never connects merely because it was opened', () {
      final String source = File(entry.key).readAsStringSync();

      expect(source, contains(entry.value));
      expect(source, isNot(contains('UniversityIdentityAutoConnect')));
      expect(source, isNot(contains('universityServiceConnectorProvider')));
    });
  }
}
