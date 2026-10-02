// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../../timetable/data/timetable_models.dart';

/// What a calendar entry still knows about where it came from.
///
/// [CalendarEntry] is deliberately uniform — the agenda draws every source the
/// same way — but flattening is lossy: a timetable slot's rooms become
/// `"B.202, B.210"`, and that string is neither one room nor prose. A detail
/// view needs the structure back, so each source carries its own typed record
/// alongside the flattened fields rather than the screens re-parsing strings.
///
/// The room accessors are the important part. Every source states *how* its
/// text may be read — as a field that holds a room designation, or as prose
/// that merely mentions one — and the resolver applies the matching rule. That
/// is what keeps "never link to the wrong room" one decision instead of one per
/// screen.
@immutable
sealed class CalendarEntryDetails {
  const CalendarEntryDetails();

  /// Values from a field whose purpose is to name a room.
  List<String> get roomDesignations => const <String>[];

  /// Free text that may mention a room among everything else.
  List<String> get roomProse => const <String>[];
}

/// A timetable slot, with the structure the agenda flattened away.
@immutable
class TimetableCalendarDetails extends CalendarEntryDetails {
  const TimetableCalendarDetails({
    required this.type,
    required this.status,
    this.teachers = const <String>[],
    this.rooms = const <String>[],
    this.groups = const <String>[],
    this.note,
    this.lessonInfo,
  });

  final TimetableEntryType type;
  final TimetableEntryStatus status;
  final List<String> teachers;
  final List<String> rooms;
  final List<String> groups;
  final String? note;
  final String? lessonInfo;

  /// The room list is exactly that — a list of rooms, so `202` means a room.
  @override
  List<String> get roomDesignations => rooms;

  @override
  bool operator ==(Object other) =>
      other is TimetableCalendarDetails &&
      other.type == type &&
      other.status == status &&
      _sameList(other.teachers, teachers) &&
      _sameList(other.rooms, rooms) &&
      _sameList(other.groups, groups) &&
      other.note == note &&
      other.lessonInfo == lessonInfo;

  @override
  int get hashCode => Object.hash(
    type,
    status,
    Object.hashAll(teachers),
    Object.hashAll(rooms),
    Object.hashAll(groups),
    note,
    lessonInfo,
  );
}

/// A Moodle deadline. Nothing here ever leaves the device (AGENTS.md §2.1).
@immutable
class MoodleCalendarDetails extends CalendarEntryDetails {
  const MoodleCalendarDetails({
    this.courseName,
    this.moduleName,
    this.eventType,
  });

  final String? courseName;
  final String? moduleName;
  final String? eventType;

  @override
  bool operator ==(Object other) =>
      other is MoodleCalendarDetails &&
      other.courseName == courseName &&
      other.moduleName == moduleName &&
      other.eventType == eventType;

  @override
  int get hashCode => Object.hash(courseName, moduleName, eventType);
}

/// An event from a public calendar — written by whoever maintains that calendar.
@immutable
class PublicCalendarDetails extends CalendarEntryDetails {
  const PublicCalendarDetails({
    required this.calendarName,
    this.location,
    this.description,
  });

  final String calendarName;
  final String? location;
  final String? description;

  /// Both fields are prose, including `location`: an ICS LOCATION holds street
  /// addresses, building names and "online" at least as often as a room number,
  /// so a bare number in there is never read as a room.
  @override
  List<String> get roomProse => <String>[?location, ?description];

  @override
  bool operator ==(Object other) =>
      other is PublicCalendarDetails &&
      other.calendarName == calendarName &&
      other.location == location &&
      other.description == description;

  @override
  int get hashCode => Object.hash(calendarName, location, description);
}

/// A favourited dish on the preferred canteen's menu for one day.
@immutable
class CanteenFavouriteMealCalendarDetails extends CalendarEntryDetails {
  const CanteenFavouriteMealCalendarDetails({required this.canteenName});

  final String canteenName;

  @override
  bool operator ==(Object other) =>
      other is CanteenFavouriteMealCalendarDetails &&
      other.canteenName == canteenName;

  @override
  int get hashCode => canteenName.hashCode;
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
