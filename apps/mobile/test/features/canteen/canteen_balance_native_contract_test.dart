// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync();

void main() {
  test(
    'Android exposes optional ISO-DEP dispatch and no background service',
    () {
      final String manifest = _source(
        'android/app/src/main/AndroidManifest.xml',
      );
      final String filter = _source(
        'android/app/src/main/res/xml/nfc_tech_filter.xml',
      );
      final String activity = _source(
        'android/app/src/main/kotlin/dev/erikengler/campuskoethen/'
        'MainActivity.kt',
      );

      expect(manifest, contains('android.permission.NFC'));
      expect(manifest, contains('android.hardware.nfc'));
      expect(manifest, contains('android:required="false"'));
      expect(manifest, contains('android.nfc.action.TECH_DISCOVERED'));
      expect(filter, contains('android.nfc.tech.IsoDep'));
      expect(activity, contains('enableReaderMode'));
      expect(activity, contains('IsoDep.get'));
      expect(activity, contains('isoDep.transceive(command)'));
      expect(activity, contains('disableReaderMode'));
      final String connectedHandoff = RegExp(
        r'activeIsoDep = isoDep[\s\S]*?startResult\?\.success\(null\)',
      ).firstMatch(activity)!.group(0)!;
      expect(
        connectedHandoff,
        isNot(contains('disableReaderMode()')),
        reason:
            'reader mode must stay active until both APDUs have completed; '
            'disabling it at connect time drops the in-app IsoDep tag',
      );
      expect(manifest, isNot(contains('<service')));
      expect(activity, isNot(contains('Log.')));
      expect(activity, isNot(contains('tag.id')));
    },
  );

  test('iOS declares CoreNFC TAG capability and both supported tag paths', () {
    final String info = _source('ios/Runner/Info.plist');
    final String entitlements = _source('ios/Runner/Runner.entitlements');
    final String project = _source('ios/Runner.xcodeproj/project.pbxproj');
    final String delegate = _source('ios/Runner/AppDelegate.swift');
    final String germanUsage = _source('ios/Runner/de.lproj/InfoPlist.strings');
    final String englishUsage = _source(
      'ios/Runner/en.lproj/InfoPlist.strings',
    );

    expect(info, contains('NFCReaderUsageDescription'));
    expect(
      entitlements,
      contains('com.apple.developer.nfc.readersession.formats'),
    );
    expect(entitlements, contains('<string>TAG</string>'));
    expect(
      RegExp(
        'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
      ).allMatches(project).length,
      3,
    );
    expect(project, contains('com.apple.NearFieldCommunication'));
    expect(project, contains('InfoPlist.strings in Resources'));
    expect(germanUsage, contains('nicht gespeichert'));
    expect(englishUsage, contains('not stored'));
    expect(delegate, contains('import CoreNFC'));
    expect(delegate, contains('NFCTagReaderSession'));
    expect(delegate, contains('case .iso7816'));
    expect(delegate, contains('case .miFare'));
    expect(delegate, contains('operationGeneration'));
    expect(delegate, contains('self.session === session'));
    expect(delegate, isNot(contains('UserDefaults')));
    expect(delegate, isNot(contains('print(')));
  });
}
