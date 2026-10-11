// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Resolves the zone the device is in, so a wall-clock time can be planned as
/// a wall-clock time.
///
/// A port: the planner is a pure function over a [tz.Location], and a test can
/// hand it Berlin, Sydney or a zone whose clocks change on the day under test
/// without touching a platform channel.
abstract interface class TimeZoneResolver {
  /// Loads the zone database once. Safe to call repeatedly.
  Future<void> initialize();

  /// The current IANA zone name, e.g. `Europe/Berlin`, or `null` when the
  /// platform will not say.
  Future<String?> deviceTimeZoneName();

  /// The location to plan in — the device zone, or its current UTC offset
  /// when the platform cannot provide an IANA name. Never throws.
  Future<tz.Location> resolveLocation();
}

/// [TimeZoneResolver] over `flutter_timezone` and the `timezone` database.
class DeviceTimeZoneResolver implements TimeZoneResolver {
  bool _databaseLoaded = false;

  @override
  Future<void> initialize() async {
    if (_databaseLoaded) return;
    tz_data.initializeTimeZones();
    _databaseLoaded = true;
  }

  @override
  Future<String?> deviceTimeZoneName() async {
    try {
      final TimezoneInfo info = await FlutterTimezone.getLocalTimezone();
      return info.identifier;
    } catch (error) {
      _report(error);
      return null;
    }
  }

  @override
  Future<tz.Location> resolveLocation() async {
    await initialize();
    final String? name = await deviceTimeZoneName();
    if (name == null) return _deviceOffsetLocation();
    try {
      return tz.getLocation(name);
    } catch (error) {
      // A newly split zone or vendor-specific alias may be absent from the
      // bundled database. The device's current offset is still more accurate
      // than silently scheduling every reminder at UTC.
      _report(error);
      return _deviceOffsetLocation();
    }
  }

  tz.Location _deviceOffsetLocation() =>
      locationForDeviceOffset(DateTime.now().timeZoneOffset);

  void _report(Object error) {
    assert(() {
      debugPrint(
        'notifications: time zone lookup failed (${error.runtimeType})',
      );
      return true;
    }());
  }
}

/// A zone from the bundled database whose offset is [offset] right now.
///
/// The fallback for a device that will not name its zone. The location's
/// name travels to the native side of flutter_local_notifications as
/// `timeZoneName`, where Android passes it to `java.time.ZoneId.of` and iOS to
/// `NSTimeZone timeZoneWithName:`. Both reject a made-up name, which made every
/// scheduled notification fail silently, so only real tz database names are
/// returned:
///
/// * `UTC` for no offset,
/// * `Etc/GMT∓h` for a whole-hour offset (POSIX inverts the sign: UTC+1 is
///   `Etc/GMT-1`),
/// * otherwise a region whose offset is [offset] now, preferring one without
///   daylight saving so the borrowed rules do not shift within the planning
///   horizon. Should no region match at all, the nearest whole-hour `Etc`
///   zone is still better than a zone the platform cannot read.
@visibleForTesting
tz.Location locationForDeviceOffset(Duration offset, {DateTime? now}) {
  if (offset == Duration.zero) return tz.UTC;
  final tz.Location? whole = _etcLocation(offset);
  if (whole != null && offset.inMinutes % 60 == 0) return whole;

  final int at = (now ?? DateTime.now()).millisecondsSinceEpoch;
  const int halfYear = 183 * Duration.millisecondsPerDay;
  final List<String> names =
      tz.timeZoneDatabase.locations.keys
          .where(
            (String name) => name.contains('/') && !name.startsWith('Etc/'),
          )
          .toList()
        ..sort();
  tz.Location? withDst;
  for (final String name in names) {
    final tz.Location location = tz.timeZoneDatabase.locations[name]!;
    if (location.timeZone(at).offset != offset) continue;
    if (location.timeZone(at + halfYear).offset == offset) return location;
    withDst ??= location;
  }
  return withDst ??
      _etcLocation(Duration(hours: (offset.inMinutes / 60).round())) ??
      tz.UTC;
}

tz.Location? _etcLocation(Duration offset) {
  final int hours = offset.inMinutes ~/ 60;
  if (hours == 0) return tz.UTC;
  final String name = 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null; // beyond the Etc range (-12 … +14)
  }
}

/// A [TimeZoneResolver] pinned to one zone. For tests, and for any platform
/// without a device zone to ask for.
class FixedTimeZoneResolver implements TimeZoneResolver {
  FixedTimeZoneResolver(this.name);

  final String name;

  @override
  Future<void> initialize() async => tz_data.initializeTimeZones();

  @override
  Future<String?> deviceTimeZoneName() async => name;

  @override
  Future<tz.Location> resolveLocation() async {
    await initialize();
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.UTC;
    }
  }
}
