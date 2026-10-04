// Campus Koethen App - AGPL-3.0-only
// Copyright (c) 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync();

void main() {
  test('Android widget is registered, local-only and opens the calendar', () {
    final String manifest = _source('android/app/src/main/AndroidManifest.xml');
    final String provider = _source(
      'android/app/src/main/kotlin/dev/erikengler/campuskoethen/'
      'CalendarWidgetProvider.kt',
    );
    final String metadata = _source(
      'android/app/src/main/res/xml/calendar_widget_info.xml',
    );

    expect(manifest, contains('android:name=".CalendarWidgetProvider"'));
    expect(manifest, contains('android.appwidget.action.APPWIDGET_UPDATE'));
    expect(manifest, contains('campuskoethen'));
    expect(manifest, contains('android:host="calendar"'));
    expect(provider, contains('HomeWidgetProvider'));
    expect(provider, contains('calendar_widget_payload'));
    expect(provider, contains('campuskoethen://calendar?homeWidget=1'));
    expect(provider, isNot(contains('HttpURLConnection')));
    expect(provider, isNot(contains('OkHttp')));
    expect(provider, isNot(contains('URL(')));
    expect(metadata, contains('android:updatePeriodMillis="1800000"'));
  });

  test('iOS widget is embedded and shares only the local app group', () {
    final String project = _source('ios/Runner.xcodeproj/project.pbxproj');
    final String runnerInfo = _source('ios/Runner/Info.plist');
    final String runnerEntitlements = _source('ios/Runner/Runner.entitlements');
    final String widgetEntitlements = _source(
      'ios/CampusCalendarWidget/CampusCalendarWidget.entitlements',
    );
    final String widget = _source(
      'ios/CampusCalendarWidget/CampusCalendarWidget.swift',
    );

    expect(project, contains('CampusCalendarWidget.appex'));
    expect(project, contains('Embed App Extensions'));
    expect(project, contains('com.apple.product-type.app-extension'));
    expect(runnerInfo, contains('<string>campuskoethen</string>'));
    for (final String entitlements in <String>[
      runnerEntitlements,
      widgetEntitlements,
    ]) {
      expect(entitlements, contains('com.apple.security.application-groups'));
      expect(entitlements, contains('group.dev.erikengler.campuskoethen'));
    }
    expect(widget, contains('UserDefaults(suiteName: appGroup)'));
    expect(widget, contains('calendar_widget_payload'));
    expect(widget, contains('showDetails'));
    expect(widget, contains('campuskoethen://calendar?homeWidget=1'));
    expect(widget, isNot(contains('URLSession')));
    expect(widget, isNot(contains('Network')));
  });
}
