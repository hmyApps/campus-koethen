// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Fixtures shaped exactly like the responses in `docs/api.md`.
///
/// All names are fictional demo data and are marked as such where the contract
/// provides a flag for it. No real person, phone number or e-mail address
/// appears anywhere in this file.
library;

List<Map<String, dynamic>> get channelsFixture => <Map<String, dynamic>>[
  <String, dynamic>{
    'slug': 'campus-news',
    'name': 'Campus News',
    'description': 'Nachrichten rund um den Campus Köthen.',
    'colorHex': '#5B3FD0',
    'sortOrder': 10,
    'defaultSubscribed': true,
  },
  <String, dynamic>{
    'slug': 'fb5-news',
    'name': 'FB5 News',
    'description': null,
    'colorHex': null,
    'sortOrder': 20,
    'defaultSubscribed': true,
  },
];

List<Map<String, dynamic>> get tagsFixture => <Map<String, dynamic>>[
  <String, dynamic>{
    'slug': 'news',
    'name': 'News',
    'description': null,
    'sortOrder': 10,
  },
  <String, dynamic>{
    'slug': 'event',
    'name': 'Event',
    'description': 'Veranstaltungen am Campus.',
    'sortOrder': 20,
  },
];

List<Map<String, dynamic>> get articlesFixture => <Map<String, dynamic>>[
  <String, dynamic>{
    'slug': 'semesterstart-2026',
    'title': 'Semesterstart 2026',
    'publishedAt': '2026-07-20T09:00:00.000Z',
    'heroImage': null,
    'channels': <Object>[
      <String, dynamic>{
        'slug': 'campus-news',
        'name': 'Campus News',
        'colorHex': '#5B3FD0',
      },
    ],
    'tag': <String, dynamic>{'slug': 'news', 'name': 'News'},
    'primaryChannel': <String, dynamic>{
      'slug': 'campus-news',
      'name': 'Campus News',
      'colorHex': '#5B3FD0',
    },
    'sourceName': null,
    'sourceUrl': null,
    // The list endpoint carries the sanitised article, which is what lets the
    // feed render it inline without a request per card.
    'content': <Object>[
      <String, dynamic>{
        'type': 'paragraph',
        'children': <Object>[
          <String, dynamic>{
            'type': 'text',
            'text': 'Das Wintersemester beginnt im Oktober.',
          },
        ],
      },
    ],
  },
];

Map<String, dynamic> get canteenFixture => <String, dynamic>{
  'slug': 'koethen-fasanerieallee',
  'displayName': 'Mensa Köthen',
  'campusLabel': 'Fasanerieallee',
  'lastSuccessfulSyncAt': '2026-07-22T12:00:04.000Z',
  'dataStale': false,
};

/// A menu whose only day is [date], containing one meal with three price
/// groups, a sprint marker, extras, ingredients and markers.
Map<String, dynamic> menuFixture(DateTime date) => <String, dynamic>{
  'canteen': <String, dynamic>{
    'slug': 'koethen-fasanerieallee',
    'displayName': 'Mensa Köthen',
    'campusLabel': 'Fasanerieallee',
  },
  'days': <Object>[
    <String, dynamic>{
      'date':
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
      'meals': <Object>[
        <String, dynamic>{
          'id': '58033',
          'name': 'Bulgur-Pfanne',
          'subtitle': 'mit Kichererbsen, Wirsing und Kräuterdip',
          'sourceLanguage': 'de',
          'counterId': 44,
          'isSprint': true,
          'extras': <Object>['Salatbeilage'],
          'markers': <Object>[
            <String, dynamic>{
              'code': '52',
              'label': 'vegan',
              'kind': 'ingredient',
            },
            <String, dynamic>{
              'code': '53',
              'label': 'Sprint-Menü',
              'kind': 'marker',
            },
          ],
          'prices': <Object>[
            <String, dynamic>{
              'group': 'student',
              'label': 'Studierende',
              'amount': '1.95',
              'currency': 'EUR',
            },
            <String, dynamic>{
              'group': 'employee',
              'label': 'Bedienstete',
              'amount': '4.95',
              'currency': 'EUR',
            },
            <String, dynamic>{
              'group': 'guest',
              'label': 'Gäste',
              'amount': '7.00',
              'currency': 'EUR',
            },
          ],
        },
      ],
    },
  ],
};

/// The group list of `GET /v1/timetable/groups`.
///
/// Only Campus UUIDs appear here — the contract guarantees that no upstream
/// identifier ever reaches the client.
List<Map<String, dynamic>> get timetableGroupsFixture => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': '11111111-1111-4111-8111-111111111111',
    'shortName': 'AIN2 - BT',
    'longName': 'AIN2-Angewandte Informatik Vertiefung: Biotechnologie',
    'department': 'FB5',
  },
  <String, dynamic>{
    'id': '22222222-2222-4222-8222-222222222222',
    'shortName': 'MB1',
    'longName': 'MB1-Maschinenbau',
    'department': 'FB6',
  },
  <String, dynamic>{
    'id': '33333333-3333-4333-8333-333333333333',
    'shortName': 'OHNE',
    'longName': null,
    'department': null,
  },
];

/// Id of the group used by the timetable fixtures.
const String timetableGroupIdFixture = '11111111-1111-4111-8111-111111111111';

/// Simulates the backend's server-side group search for a fake adapter: a
/// case-insensitive substring match against short name, long name and
/// department. A null or blank [query] returns every fixture group.
List<Map<String, dynamic>> matchingTimetableGroups(Object? query) {
  final String normalized = (query is String ? query : '').trim().toLowerCase();
  if (normalized.isEmpty) return timetableGroupsFixture;
  return timetableGroupsFixture.where((Map<String, dynamic> group) {
    return <String?>[
      group['shortName'] as String?,
      group['longName'] as String?,
      group['department'] as String?,
    ].any(
      (String? field) => field?.toLowerCase().contains(normalized) ?? false,
    );
  }).toList();
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// A whole week of `GET /v1/timetable/entries`, starting at [monday].
///
/// Every day of the range is present, so an empty day is distinguishable from
/// a loading failure. The first day carries four entries that cover all status
/// and type combinations the UI has to render, including values the app does
/// not know.
///
/// Teacher names are explicitly marked demo data; no real person appears.
Map<String, dynamic> timetableWeekFixture(DateTime monday) {
  Map<String, dynamic> entry({
    required String id,
    required int hour,
    required String title,
    required String type,
    required String status,
  }) {
    final DateTime start = DateTime.utc(
      monday.year,
      monday.month,
      monday.day,
      hour,
    );
    return <String, dynamic>{
      'id': id,
      'start': start.toIso8601String(),
      'end': start.add(const Duration(minutes: 90)).toIso8601String(),
      'timezone': 'Europe/Berlin',
      'title': title,
      'subjectCode': title,
      'type': type,
      'status': status,
      'teachers': <Object>[
        <String, dynamic>{
          'shortName': 'D-Demo01',
          'displayName': 'Demo Demoperson01',
        },
      ],
      'rooms': <Object>[
        <String, dynamic>{
          'shortName': 'D-04/201',
          'longName': 'Seminarraum Demo',
        },
      ],
      'groups': <Object>[
        <String, dynamic>{
          'id': timetableGroupIdFixture,
          'shortName': 'AIN2 - BT',
        },
      ],
      'note': null,
    };
  }

  return <String, dynamic>{
    'group': <String, dynamic>{
      'id': timetableGroupIdFixture,
      'shortName': 'AIN2 - BT',
      'longName': 'AIN2-Angewandte Informatik Vertiefung: Biotechnologie',
      'department': 'FB5',
    },
    'days': <Object>[
      <String, dynamic>{
        'date': _isoDate(monday),
        'entries': <Object>[
          entry(
            id: 'e1',
            hour: 6,
            title: 'Mathematik 2',
            type: 'regular_teaching',
            status: 'regular',
          ),
          entry(
            id: 'e2',
            hour: 8,
            title: 'Technische Mechanik',
            type: 'regular_teaching',
            status: 'cancelled',
          ),
          entry(
            id: 'e3',
            hour: 10,
            title: 'Projektseminar',
            type: 'additional',
            status: 'changed',
          ),
          entry(
            id: 'e4',
            hour: 12,
            title: 'Exkursion',
            type: 'a-type-the-app-has-never-seen',
            status: 'a-status-the-app-has-never-seen',
          ),
        ],
      },
      for (int offset = 1; offset < 7; offset++)
        <String, dynamic>{
          'date': _isoDate(monday.add(Duration(days: offset))),
          'entries': <Object>[],
        },
    ],
  };
}

/// Meta block of a timetable response.
Map<String, dynamic> timetableMeta({
  bool featureEnabled = true,
  String dataState = 'ready',
  bool dataStale = false,
  String? lastSuccessfulSyncAt = '2026-07-22T03:00:11.000Z',
}) => <String, dynamic>{
  'timezone': 'Europe/Berlin',
  'featureEnabled': featureEnabled,
  'dataState': dataState,
  'dataStale': dataStale,
  'lastSuccessfulSyncAt': lastSuccessfulSyncAt,
};

/// A contact area without any person and with almost every field unmaintained.
Map<String, dynamic> get emptyContactAreaFixture => <String, dynamic>{
  'slug': 'studierendenrat',
  'name': 'Studierendenrat',
  'shortDescription': 'Die gewählte Vertretung der Studierendenschaft.',
  'iconKey': 'students-council',
  'sortOrder': 10,
  'generalEmail': null,
  'phone': null,
  'website': null,
  'appointmentBookingUrl': null,
  'address': null,
  'openingHours': null,
  'personCount': 0,
  'description': <Object>[],
  'persons': <Object>[],
};

/// A contact area whose `iconKey` is unknown to the app.
Map<String, dynamic> get unknownIconAreaFixture => <String, dynamic>{
  'slug': 'unbekannt',
  'name': 'Neuer Bereich',
  'shortDescription': null,
  'iconKey': 'a-key-the-app-has-never-seen',
  'sortOrder': 20,
  'personCount': 0,
};
