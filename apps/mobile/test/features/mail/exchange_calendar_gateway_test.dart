// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/data/ews_exchange_calendar_gateway.dart';
import 'package:campus_koethen/features/mail/domain/exchange_calendar_gateway.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_html_adapter.dart';

const MailCredentials _credentials = MailCredentials(
  emailAddress: 'demo@hs-anhalt.de',
  password: 'not-a-real-password',
);

void main() {
  test(
    'uses the pinned EWS endpoint and requests only needed fields',
    () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter(
        (_) => const FakeHtmlResponse(_emptySuccess),
      );
      final Dio dio = Dio()..httpClientAdapter = adapter;
      final EwsExchangeCalendarGateway gateway = EwsExchangeCalendarGateway(
        dio: dio,
      );

      await gateway.fetchEvents(
        _credentials,
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 11, 1),
      );

      final RequestOptions request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'https://mail.hs-anhalt.de/EWS/Exchange.asmx',
      );
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], startsWith('Basic '));
      final String body = request.data as String;
      expect(body, contains('StartDate="2026-10-01T00:00:00.000Z"'));
      expect(body, contains('EndDate="2026-11-01T00:00:00.000Z"'));
      expect(body, contains('calendar:Start'));
      expect(body, contains('calendar:IsCancelled'));
      expect(body, isNot(contains('item:Body')));
      expect(body, isNot(contains('calendar:RequiredAttendees')));
    },
  );

  test('rejects redirects so credentials cannot leave the pinned host', () {
    final FakeHtmlAdapter adapter = FakeHtmlAdapter(
      (_) => const FakeHtmlResponse.redirect('https://evil.example/'),
    );
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final ExchangeCalendarGateway gateway = EwsExchangeCalendarGateway(
      dio: dio,
    );

    expect(
      () => gateway.fetchEvents(
        _credentials,
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 11, 1),
      ),
      throwsA(
        const ExchangeCalendarFailure(
          ExchangeCalendarFailureKind.tlsOrHostRejected,
        ),
      ),
    );
  });

  test('refuses invalid ranges before sending credentials', () {
    final FakeHtmlAdapter adapter = FakeHtmlAdapter(
      (_) => const FakeHtmlResponse(_emptySuccess),
    );
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final ExchangeCalendarGateway gateway = EwsExchangeCalendarGateway(
      dio: dio,
    );

    expect(
      () => gateway.fetchEvents(
        _credentials,
        from: DateTime.utc(2026, 11, 1),
        to: DateTime.utc(2026, 10, 1),
      ),
      throwsA(
        const ExchangeCalendarFailure(
          ExchangeCalendarFailureKind.invalidRequest,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });
}

const String _emptySuccess = '''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
    xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
  <s:Body><m:FindItemResponse><m:ResponseMessages>
    <m:FindItemResponseMessage ResponseClass="Success">
      <m:ResponseCode>NoError</m:ResponseCode>
      <m:RootFolder IncludesLastItemInRange="true" TotalItemsInView="0">
        <t:Items />
      </m:RootFolder>
    </m:FindItemResponseMessage>
  </m:ResponseMessages></m:FindItemResponse></s:Body>
</s:Envelope>
''';
