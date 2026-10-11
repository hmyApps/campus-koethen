// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/notifications/data/device_time_zone.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// What the native side of flutter_local_notifications accepts as a zone:
/// Android hands `timeZoneName` to `java.time.ZoneId.of`, iOS to
/// `NSTimeZone timeZoneWithName:`. Both know the tz database region names,
/// and neither knows a made-up one such as `device-offset-60`.
final RegExp _ianaRegionName = RegExp(
  r'^(UTC|[A-Z][A-Za-z_]+(/[A-Za-z0-9_+-]+)+)$',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('flutter_timezone');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a failed native zone lookup still uses the device offset', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });

    final tz.Location location = await DeviceTimeZoneResolver()
        .resolveLocation();

    expect(
      tz.TZDateTime.now(location).timeZoneOffset,
      DateTime.now().timeZoneOffset,
    );
  });

  group('the offset fallback names a zone the native side knows', () {
    setUpAll(tz_data.initializeTimeZones);

    void expectValid(Duration offset) {
      final tz.Location location = locationForDeviceOffset(offset);
      expect(location.name, matches(_ianaRegionName), reason: '$offset');
      // The same name resolves in the bundled database, and to the offset.
      expect(tz.getLocation(location.name).name, location.name);
      expect(tz.TZDateTime.now(location).timeZoneOffset, offset);
    }

    test('whole hours east and west of UTC use Etc/GMT with the inverted '
        'sign', () {
      expect(
        locationForDeviceOffset(const Duration(hours: 1)).name,
        'Etc/GMT-1',
      );
      expect(
        locationForDeviceOffset(const Duration(hours: -5)).name,
        'Etc/GMT+5',
      );
      expectValid(const Duration(hours: 1));
      expectValid(const Duration(hours: -5));
      expectValid(const Duration(hours: 14));
      expectValid(const Duration(hours: -12));
    });

    test('UTC itself', () {
      expectValid(Duration.zero);
    });

    test('a non-whole-hour offset borrows a real zone with that offset', () {
      expectValid(const Duration(hours: 5, minutes: 30));
      expectValid(const Duration(hours: 5, minutes: 45));
      expectValid(const Duration(hours: 9, minutes: 30));
    });
  });
}
