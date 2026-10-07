// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Guards the boundaries of the notification feature at the source level.
///
/// These are not style checks. Each one prevents a mistake that would be
/// invisible in every unit test and would only surface as "why did I not get
/// a reminder" weeks later on somebody's phone, or as a privacy regression
/// nobody would think to look for.
library;

import 'dart:io';

import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:flutter_test/flutter_test.dart';

const String _featureDir = 'lib/features/notifications';

List<File> _dartFiles(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((File file) => file.path.endsWith('.dart'))
    .toList(growable: false);

String _sourceOf(String path) => File(path).readAsStringSync();

/// The manifest without its comments — a rule that explains why a permission
/// is absent must not itself count as asking for it.
String _manifestDeclarations() => _sourceOf(
  'android/app/src/main/AndroidManifest.xml',
).replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

void main() {
  group('planning scope (ADR-0001 § 7.2)', () {
    test('the planner never reads the calendar screen\'s display switches', () {
      // `calendarEnabledSourcesProvider` and
      // `calendarSavedEventsEnabledProvider` decide what the calendar SCREEN
      // shows. The second is off by default. A planner that read them would
      // silently produce no reminders for saved events in the normal case,
      // and would drop the timetable out of the daily overview the moment
      // somebody hid it from the calendar view — neither of which any
      // product rule asks for.
      const List<String> forbidden = <String>[
        'calendarEnabledSourcesProvider',
        'calendarSavedEventsEnabledProvider',
        'calendarDisabledSources',
      ];
      final List<String> offenders = <String>[];
      for (final File file in _dartFiles(_featureDir)) {
        final String content = file.readAsStringSync();
        for (final String symbol in forbidden) {
          if (content.contains(symbol)) offenders.add('${file.path}: $symbol');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'The scope of a notification is the notification settings plus '
            'the activated public calendars — never a view filter:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the feature has no server side of any kind', () {
      // The whole point of ADR-0001: no provider, no registration, no token,
      // no endpoint. A single import of the API client here would be the
      // first step back towards the architecture that was rejected.
      const List<String> forbidden = <String>[
        'firebase',
        'Firebase',
        'apiClient',
        'ApiClient',
        'package:dio/',
        'WorkManager',
        'BGTaskScheduler',
      ];
      final List<String> offenders = <String>[];
      for (final File file in _dartFiles(_featureDir)) {
        final String content = file.readAsStringSync();
        for (final String symbol in forbidden) {
          if (content.contains(symbol)) offenders.add('${file.path}: $symbol');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('only one file knows the notification plugin exists', () {
      final List<String> importers = <String>[
        for (final File file in _dartFiles('lib'))
          if (file.readAsStringSync().contains(
            "package:flutter_local_notifications/",
          ))
            file.path.replaceAll('\\', '/'),
      ];

      expect(importers, <String>[
        '$_featureDir/data/local_notification_gateway.dart',
      ]);
    });

    test('the planner itself is free of Flutter and of providers', () {
      final String planner = _sourceOf(
        '$_featureDir/application/notification_planner.dart',
      );
      expect(planner, isNot(contains('package:flutter/')));
      expect(planner, isNot(contains('flutter_riverpod')));
      expect(planner, isNot(contains('DateTime.now()')));
    });
  });

  group('categories are the approved four', () {
    test('no more and no fewer', () {
      expect(
        NotificationCategory.values.map((NotificationCategory c) => c.key),
        <String>[
          'event.reminder',
          'daily.summary',
          'canteen.favourite',
          'mail.new',
        ],
      );
    });

    test('each has its own Android channel and its own key prefix', () {
      expect(
        NotificationCategory.values
            .map((NotificationCategory c) => c.channelId)
            .toSet(),
        hasLength(4),
      );
      expect(
        NotificationCategory.values
            .map((NotificationCategory c) => c.keyPrefix)
            .toSet(),
        hasLength(4),
      );
    });

    test('the tie-break order is total', () {
      expect(
        NotificationCategory.values
            .map((NotificationCategory c) => c.order)
            .toSet(),
        hasLength(NotificationCategory.values.length),
      );
    });
  });

  group('no bundling (P8)', () {
    test('the app never sets a notification group key', () {
      // Android and iOS stack one app's notifications visually, and that is
      // system behaviour. What P8 forbids is the app asking for it.
      for (final File file in _dartFiles(_featureDir)) {
        expect(
          file.readAsStringSync(),
          isNot(contains('groupKey:')),
          reason: file.path,
        );
        expect(
          file.readAsStringSync(),
          isNot(contains('setAsGroupSummary')),
          reason: file.path,
        );
      }
    });
  });

  group('no exact alarm permission (§ 7.9)', () {
    test('the Android manifest asks for neither exact-alarm permission', () {
      final String manifest = _manifestDeclarations();
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
    });

    test('the scheduler always plans inexactly', () {
      expect(
        _sourceOf('$_featureDir/data/local_notification_gateway.dart'),
        contains('AndroidScheduleMode.inexactAllowWhileIdle'),
      );
    });

    test('the Android delivery receivers are declared', () {
      final String manifest = _manifestDeclarations();
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('RECEIVE_BOOT_COMPLETED'));
      expect(manifest, contains('ScheduledNotificationReceiver'));
      expect(manifest, contains('ScheduledNotificationBootReceiver'));
    });

    test(
      'Android desugaring is enabled — the plugin will not build without it',
      () {
        final String gradle = _sourceOf('android/app/build.gradle.kts');
        expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
        expect(gradle, contains('desugar_jdk_libs'));
      },
    );

    test('the iOS project has no push entitlement and no background mode', () {
      final String plist = _sourceOf('ios/Runner/Info.plist');
      expect(plist, isNot(contains('aps-environment')));
      expect(plist, isNot(contains('UIBackgroundModes')));
    });
  });
}
