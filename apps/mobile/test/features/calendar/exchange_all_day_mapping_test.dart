// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/calendar/application/calendar_merge.dart';
import 'package:campus_koethen/features/calendar/domain/calendar_entry.dart';
import 'package:campus_koethen/features/mail/data/exchange_calendar_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-06: which day an all-day Exchange appointment lands on.
///
/// The gateway pins EWS's response zone to UTC. Exchange stores an all-day
/// appointment as the midnight that starts its date in the calendar's own
/// zone, so a mailbox in Köthen answers with 22:00Z (summer) or 23:00Z
/// (winter) **the evening before**. Read as the app's UTC-midnight all-day
/// encoding, every such appointment showed one day early.
///
/// Every expectation here is zone-independent: the fixture carries literal UTC
/// values, and an all-day day key is read from the value's UTC date parts, so
/// the test means the same on a runner in Köthen and on one in UTC.
List<CalendarEntry> _mapped(String calendarItems) =>
    exchangeEventsToCalendarEntries(
      parseExchangeCalendarResponse(_envelope(calendarItems)),
      untitledTitle: 'Termin ohne Betreff',
    );

String _item({
  required String id,
  required String start,
  required String end,
  required bool allDay,
}) =>
    '''
              <t:CalendarItem>
                <t:ItemId Id="$id" />
                <t:Subject>Demo-Termin</t:Subject>
                <t:Start>$start</t:Start>
                <t:End>$end</t:End>
                <t:IsAllDayEvent>$allDay</t:IsAllDayEvent>
                <t:IsCancelled>false</t:IsCancelled>
              </t:CalendarItem>''';

/// A synthetic FindItem response in the shape EWS returns; ids and subjects
/// are demo values, nothing here comes from a real mailbox.
String _envelope(String items) =>
    '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
    xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
  <s:Body>
    <m:FindItemResponse>
      <m:ResponseMessages>
        <m:FindItemResponseMessage ResponseClass="Success">
          <m:ResponseCode>NoError</m:ResponseCode>
          <m:RootFolder IncludesLastItemInRange="true" TotalItemsInView="1">
            <t:Items>
$items
            </t:Items>
          </m:RootFolder>
        </m:FindItemResponseMessage>
      </m:ResponseMessages>
    </m:FindItemResponse>
  </s:Body>
</s:Envelope>
''';

void main() {
  test('an all-day appointment in summer time lands on its own date', () {
    // 2026-10-09 00:00 MESZ (UTC+2) up to 2026-10-10 00:00 MESZ.
    final CalendarEntry entry = _mapped(
      _item(
        id: 'demo-summer',
        start: '2026-10-08T22:00:00Z',
        end: '2026-10-09T22:00:00Z',
        allDay: true,
      ),
    ).single;

    expect(entry.allDay, isTrue);
    expect(entry.day, DateTime(2026, 10, 9));
    expect(entry.lastDay, DateTime(2026, 10, 9));
    expect(
      entriesForDay(<CalendarEntry>[entry], DateTime(2026, 10, 8)),
      isEmpty,
    );
    expect(
      entriesForDay(<CalendarEntry>[entry], DateTime(2026, 10, 9)),
      hasLength(1),
    );
    // The same UTC-midnight date marker every other all-day source uses.
    expect(entry.start, DateTime.utc(2026, 10, 9));
    expect(entry.end, DateTime.utc(2026, 10, 10));
  });

  test('a multi-day all-day appointment in winter time covers its days', () {
    // 2026-12-02 00:00 MEZ (UTC+1) up to 2026-12-04 00:00 MEZ: two days.
    final CalendarEntry entry = _mapped(
      _item(
        id: 'demo-winter',
        start: '2026-12-01T23:00:00Z',
        end: '2026-12-03T23:00:00Z',
        allDay: true,
      ),
    ).single;

    expect(entry.day, DateTime(2026, 12, 2));
    expect(entry.lastDay, DateTime(2026, 12, 3));
    expect(calendarEventDays(<CalendarEntry>[entry]), <DateTime>{
      DateTime(2026, 12, 2),
      DateTime(2026, 12, 3),
    });
  });

  test('a server already sending UTC midnight is left on that date', () {
    for (final (String start, String end) in <(String, String)>[
      ('2026-10-06T00:00:00Z', '2026-10-07T00:00:00Z'),
      // Older builds omit the suffix; the parser reads it in the pinned UTC.
      ('2026-10-06T00:00:00', '2026-10-07T00:00:00'),
    ]) {
      final CalendarEntry entry = _mapped(
        _item(id: 'demo-utc', start: start, end: end, allDay: true),
      ).single;

      expect(entry.day, DateTime(2026, 10, 6), reason: start);
      expect(entry.lastDay, DateTime(2026, 10, 6), reason: start);
      expect(entry.start, DateTime.utc(2026, 10, 6), reason: start);
    }
  });

  test('a timed appointment keeps its exact instants', () {
    final CalendarEntry entry = _mapped(
      _item(
        id: 'demo-timed',
        start: '2026-10-08T22:00:00Z',
        end: '2026-10-08T23:30:00Z',
        allDay: false,
      ),
    ).single;

    expect(entry.allDay, isFalse);
    expect(entry.start, DateTime.utc(2026, 10, 8, 22));
    expect(entry.end, DateTime.utc(2026, 10, 8, 23, 30));
  });
}
