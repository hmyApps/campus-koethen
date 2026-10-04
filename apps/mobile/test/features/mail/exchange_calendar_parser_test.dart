// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/data/exchange_calendar_parser.dart';
import 'package:campus_koethen/features/mail/domain/exchange_calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses validated EWS calendar items and keeps absolute instants', () {
    final List<ExchangeCalendarEvent> events = parseExchangeCalendarResponse(
      _successResponse,
    );

    expect(events, hasLength(2));
    expect(events.first.id, 'item-1');
    expect(events.first.subject, 'Labor');
    expect(events.first.start, DateTime.utc(2026, 10, 5, 8));
    expect(events.first.end, DateTime.utc(2026, 10, 5, 10));
    expect(events.first.location, 'B.202');
    expect(events.first.isAllDay, isFalse);
    expect(events.first.isCancelled, isFalse);
    expect(events.last.isAllDay, isTrue);
  });

  test('rejects a partial EWS page instead of silently losing events', () {
    expect(
      () => parseExchangeCalendarResponse(
        _successResponse.replaceFirst(
          'IncludesLastItemInRange="true"',
          'IncludesLastItemInRange="false"',
        ),
      ),
      throwsA(isA<ExchangeCalendarResponseException>()),
    );
  });

  test('rejects malformed items instead of inventing calendar data', () {
    expect(
      () => parseExchangeCalendarResponse(
        _successResponse.replaceFirst(
          '<t:Start>2026-10-05T08:00:00Z</t:Start>',
          '<t:Start>not-a-date</t:Start>',
        ),
      ),
      throwsA(isA<ExchangeCalendarResponseException>()),
    );
  });

  test('accepts a valid appointment without a subject', () {
    final List<ExchangeCalendarEvent> events = parseExchangeCalendarResponse(
      _successResponse.replaceFirst('<t:Subject>Labor</t:Subject>', ''),
    );

    expect(events.first.subject, isEmpty);
  });
}

const String _successResponse = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
    xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
  <s:Body>
    <m:FindItemResponse>
      <m:ResponseMessages>
        <m:FindItemResponseMessage ResponseClass="Success">
          <m:ResponseCode>NoError</m:ResponseCode>
          <m:RootFolder IncludesLastItemInRange="true" TotalItemsInView="2">
            <t:Items>
              <t:CalendarItem>
                <t:ItemId Id="item-1" ChangeKey="secret-change-key" />
                <t:Subject>Labor</t:Subject>
                <t:Start>2026-10-05T08:00:00Z</t:Start>
                <t:End>2026-10-05T10:00:00Z</t:End>
                <t:IsAllDayEvent>false</t:IsAllDayEvent>
                <t:IsCancelled>false</t:IsCancelled>
                <t:Location>B.202</t:Location>
              </t:CalendarItem>
              <t:CalendarItem>
                <t:ItemId Id="item-2" />
                <t:Subject>Vorlesungsfrei</t:Subject>
                <t:Start>2026-10-06T00:00:00</t:Start>
                <t:End>2026-10-07T00:00:00</t:End>
                <t:IsAllDayEvent>true</t:IsAllDayEvent>
                <t:IsCancelled>false</t:IsCancelled>
              </t:CalendarItem>
            </t:Items>
          </m:RootFolder>
        </m:FindItemResponseMessage>
      </m:ResponseMessages>
    </m:FindItemResponse>
  </s:Body>
</s:Envelope>
''';
