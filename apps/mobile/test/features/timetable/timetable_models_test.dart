// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/timetable/data/timetable_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

void main() {
  test('lesson information choices preserve distinct source spellings', () {
    final TimetableLessonInfoOptions options =
        TimetableLessonInfoOptions.fromJson(<String, dynamic>{
          'values': <String>['P1', 'Gruppe1', ' P1 '],
          'hasWithoutInfo': true,
        });
    expect(options.values, <String>['P1', 'Gruppe1', ' P1 ']);
    expect(options.hasWithoutInfo, isTrue);
    expect(
      () => TimetableLessonInfoOptions.fromJson(<String, dynamic>{
        'values': <Object>['P1', 1],
        'hasWithoutInfo': false,
      }),
      throwsFormatException,
    );
  });

  group('TimetableGroup', () {
    test('parses the contract shape', () {
      final List<TimetableGroup> groups = TimetableGroup.listFromJson(
        timetableGroupsFixture,
      );

      expect(groups, hasLength(3));
      expect(groups.first.id, timetableGroupIdFixture);
      expect(groups.first.shortName, 'AIN2 - BT');
      expect(
        groups.first.longName,
        'AIN2-Angewandte Informatik Vertiefung: Biotechnologie',
      );
      expect(groups.first.department, 'FB5');
      expect(groups.last.longName, isNull);
      expect(groups.last.department, isNull);
    });

    test('drops entries without an id instead of throwing', () {
      final List<TimetableGroup> groups = TimetableGroup.listFromJson(<Object>[
        <String, dynamic>{'shortName': 'no id'},
        <String, dynamic>{'id': 'a', 'shortName': 'A'},
        'not an object',
      ]);

      expect(groups.map((TimetableGroup group) => group.id), <String>['a']);
    });

    test(
      'matches a search term across short name, long name and department',
      () {
        final TimetableGroup group = TimetableGroup.listFromJson(
          timetableGroupsFixture,
        ).first;

        expect(group.matches('ain2'), isTrue, reason: 'short name, lower case');
        expect(group.matches('biotech'), isTrue, reason: 'long name');
        expect(group.matches('fb5'), isTrue, reason: 'department');
        expect(group.matches('  '), isTrue, reason: 'blank matches everything');
        expect(group.matches('maschinenbau'), isFalse);
      },
    );
  });

  group('TimetableStatus', () {
    test('parses the public availability state without upstream detail', () {
      final TimetableStatus status = TimetableStatus.fromJson(<String, dynamic>{
        'featureEnabled': true,
        'groupCount': 503,
        'coveredFrom': '2026-10-01',
        'coveredTo': '2027-04-01',
      });

      expect(status.featureEnabled, isTrue);
      expect(status.groupCount, 503);
      expect(status.coveredFrom, '2026-10-01');
      expect(status.coveredTo, '2027-04-01');
    });

    test('rejects malformed status payloads', () {
      expect(
        () => TimetableStatus.fromJson(<String, dynamic>{
          'featureEnabled': 'yes',
          'groupCount': 503,
        }),
        throwsFormatException,
      );
    });
  });

  group('TimetableEntry', () {
    Timetable parseWeek() {
      final Timetable? timetable = Timetable.fromJson(
        timetableWeekFixture(DateTime(2026, 7, 20)),
      );
      expect(timetable, isNotNull);
      return timetable!;
    }

    test('parses group, days and entries', () {
      final Timetable timetable = parseWeek();

      expect(timetable.group.shortName, 'AIN2 - BT');
      expect(timetable.days, hasLength(7));
      expect(timetable.days.first.entries, hasLength(4));

      final TimetableEntry first = timetable.days.first.entries.first;
      expect(first.id, 'e1');
      expect(first.title, 'Mathematik 2');
      expect(first.start.isUtc, isTrue, reason: 'the wire format is UTC');
      expect(first.end.difference(first.start), const Duration(minutes: 90));
      expect(first.timezone, 'Europe/Berlin');
      expect(first.teachers.single.displayName, 'Demo Demoperson01');
      expect(first.rooms.single.shortName, 'D-04/201');
      expect(first.groups.single.shortName, 'AIN2 - BT');
    });

    test('keeps lesson information distinct from a separate note', () {
      final Map<String, dynamic> json = timetableWeekFixture(
        DateTime(2026, 7, 20),
      );
      final List<dynamic> days = json['days'] as List<dynamic>;
      final Map<String, dynamic> firstDay = days.first as Map<String, dynamic>;
      final List<dynamic> entries = firstDay['entries'] as List<dynamic>;
      final Map<String, dynamic> first = entries.first as Map<String, dynamic>;
      first['lessonInfo'] = ' P1 ';
      first['note'] = 'Getrennte Notiz';

      final TimetableEntry parsed = Timetable.fromJson(
        json,
      )!.days.first.entries.first;
      expect(parsed.lessonInfo, ' P1 ');
      expect(parsed.note, 'Getrennte Notiz');
    });

    test('keeps empty days as real, empty days', () {
      final Timetable timetable = parseWeek();

      expect(timetable.days.last.entries, isEmpty);
      expect(
        timetable.dayFor(DateTime(2026, 7, 21)),
        isNotNull,
        reason: 'an empty day must be distinguishable from a missing day',
      );
      expect(timetable.dayFor(DateTime(2026, 8, 1)), isNull);
    });

    test('maps known status and type values', () {
      final List<TimetableEntry> entries = parseWeek().days.first.entries;

      expect(entries[0].status, TimetableEntryStatus.regular);
      expect(entries[0].type, TimetableEntryType.regularTeaching);
      expect(entries[1].status, TimetableEntryStatus.cancelled);
      expect(entries[2].status, TimetableEntryStatus.changed);
      expect(entries[2].type, TimetableEntryType.additional);
    });

    test('maps unknown status and type values onto unknown', () {
      final TimetableEntry entry = parseWeek().days.first.entries[3];

      expect(entry.status, TimetableEntryStatus.unknown);
      expect(entry.type, TimetableEntryType.unknown);
    });

    test('treats a missing status or type as unknown', () {
      final TimetableDay? day = TimetableDay.fromJson(<String, dynamic>{
        'date': '2026-07-20',
        'entries': <Object>[
          <String, dynamic>{
            'id': 'x',
            'start': '2026-07-20T08:00:00.000Z',
            'end': '2026-07-20T09:30:00.000Z',
          },
        ],
      });

      expect(day, isNotNull);
      expect(day!.entries.single.status, TimetableEntryStatus.unknown);
      expect(day.entries.single.type, TimetableEntryType.unknown);
      expect(day.entries.single.title, isNull);
    });

    test('drops entries without usable times instead of throwing', () {
      final TimetableDay? day = TimetableDay.fromJson(<String, dynamic>{
        'date': '2026-07-20',
        'entries': <Object>[
          <String, dynamic>{'id': 'broken', 'start': 'not-a-date'},
          <String, dynamic>{
            'id': 'ok',
            'start': '2026-07-20T08:00:00.000Z',
            'end': '2026-07-20T09:30:00.000Z',
          },
        ],
      });

      expect(day!.entries.map((TimetableEntry e) => e.id), <String>['ok']);
    });

    test('sorts days and entries chronologically', () {
      final Timetable? timetable = Timetable.fromJson(<String, dynamic>{
        'group': <String, dynamic>{'id': 'g', 'shortName': 'G'},
        'days': <Object>[
          <String, dynamic>{'date': '2026-07-21', 'entries': <Object>[]},
          <String, dynamic>{
            'date': '2026-07-20',
            'entries': <Object>[
              <String, dynamic>{
                'id': 'late',
                'start': '2026-07-20T12:00:00.000Z',
                'end': '2026-07-20T13:00:00.000Z',
              },
              <String, dynamic>{
                'id': 'early',
                'start': '2026-07-20T08:00:00.000Z',
                'end': '2026-07-20T09:00:00.000Z',
              },
            ],
          },
        ],
      });

      expect(timetable!.days.first.date, DateTime(2026, 7, 20));
      expect(
        timetable.days.first.entries.map((TimetableEntry e) => e.id),
        <String>['early', 'late'],
      );
    });

    test('returns null when the payload has no group', () {
      expect(Timetable.fromJson(<String, dynamic>{'days': <Object>[]}), isNull);
      expect(Timetable.fromJson(null), isNull);
    });
  });

  group('TimetableDataState', () {
    test('maps the contract values', () {
      expect(TimetableDataState.fromWire('ready'), TimetableDataState.ready);
      expect(
        TimetableDataState.fromWire('pending'),
        TimetableDataState.pending,
      );
      expect(
        TimetableDataState.fromWire('unavailable'),
        TimetableDataState.unavailable,
      );
    });

    test('treats an absent value as ready and an unknown one as unknown', () {
      expect(TimetableDataState.fromWire(null), TimetableDataState.ready);
      expect(
        TimetableDataState.fromWire('something-new'),
        TimetableDataState.unknown,
      );
    });
  });
}
