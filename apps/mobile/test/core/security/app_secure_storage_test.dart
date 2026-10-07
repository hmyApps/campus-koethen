// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';

import 'package:campus_koethen/core/security/app_secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keychain classes whose items stay on the device they were written on.
/// Everything else is included in a device backup and can be restored onto
/// ANOTHER device — which is exactly what a portal password and a Moodle
/// bearer token must never do (AGENTS.md §2).
const Set<KeychainAccessibility> deviceBoundAccessibility =
    <KeychainAccessibility>{
      KeychainAccessibility.passcode,
      KeychainAccessibility.unlocked_this_device,
      KeychainAccessibility.first_unlock_this_device,
    };

void main() {
  group('app secure storage', () {
    test('is device bound, so nothing reaches a device backup', () {
      expect(deviceBoundAccessibility, contains(appKeychainAccessibility));
      expect(
        appSecureStorage().iOptions.accessibility,
        appKeychainAccessibility,
      );
    });

    // A source guard rather than a behavioural one: the defect this replaces
    // was four stores each spelling their own options out, three of which had
    // drifted to a backup-able class. One definition is the only thing that
    // keeps them from drifting again.
    test('no other place in lib/ builds its own FlutterSecureStorage', () {
      final Directory lib = Directory('lib');
      expect(lib.existsSync(), isTrue, reason: 'run from apps/mobile');

      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String portablePath = entity.path.replaceAll('\\', '/');
        if (portablePath.endsWith('core/security/app_secure_storage.dart')) {
          continue;
        }
        if (entity.readAsStringSync().contains('FlutterSecureStorage(')) {
          offenders.add(portablePath);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files construct their own secure storage instead of using '
            'appSecureStorage(): ${offenders.join(', ')}',
      );
    });
  });
}
