// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final String path in <String>[
    'lib/features/mail/presentation/mail_setup_screen.dart',
    'lib/features/moodle/presentation/moodle_setup_screen.dart',
    'lib/features/grades/presentation/grade_setup_screen.dart',
  ]) {
    test('$path routes its credential write through the shared gate', () {
      final String source = File(path).readAsStringSync();

      expect(source, contains('.connectWithIdentity('));
      expect(source, contains('retainIdentity: _reuseForOtherServices'));
      expect(source, isNot(contains('.retainVerified(')));
      expect(source, isNot(contains('AccountControllerProvider.notifier')));
    });
  }

  final Map<String, String> disconnectScreens = <String, String>{
    'lib/features/mail/presentation/mail_inbox_screen.dart':
        'DirectService.mail',
    'lib/features/moodle/presentation/moodle_overview_screen.dart':
        'DirectService.moodle',
    'lib/features/grades/presentation/grades_overview_screen.dart':
        'DirectService.grades',
  };
  for (final MapEntry<String, String> entry in disconnectScreens.entries) {
    test('${entry.key} routes account removal through the shared gate', () {
      final String source = File(entry.key).readAsStringSync();

      expect(source, contains('universityServiceConnectorProvider'));
      expect(source, contains('.disconnect(${entry.value})'));
    });
  }
}
