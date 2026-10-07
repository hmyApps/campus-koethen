// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:campus_koethen/features/mail/data/exchange_directory_gateway.dart';
import 'package:campus_koethen/features/mail/domain/hsa_mail_profile.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_html_adapter.dart';

const MailCredentials _credentials = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'secret:with-colon',
);

void main() {
  test('searches only the pinned EWS endpoint and parses GAL results', () async {
    final FakeHtmlAdapter adapter = FakeHtmlAdapter(
      (_) => const FakeHtmlResponse(_response),
    );
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final ExchangeDirectoryGateway gateway = ExchangeDirectoryGateway(
      const HsaMailProfile(),
      dio: dio,
    );

    final results = await gateway.search(_credentials, '  Alice & Bob  ');

    expect(adapter.requests, hasLength(1));
    final RequestOptions request = adapter.requests.single;
    expect(
      request.uri,
      Uri.parse('https://mail.hs-anhalt.de/EWS/Exchange.asmx'),
    );
    expect(request.method, 'POST');
    expect(
      request.headers['authorization'],
      'Basic ${base64Encode(utf8.encode('stud@hs-anhalt.de:secret:with-colon'))}',
    );
    expect(request.data, contains('Alice &amp; Bob'));
    expect(results.map((entry) => entry.email), <String>[
      'alice@hs-anhalt.de',
      'bob@hs-anhalt.de',
    ]);
    expect(results.first.name, 'Alice Example');
  });

  test('maps an authentication rejection without exposing its body', () async {
    final FakeHtmlAdapter adapter = FakeHtmlAdapter(
      (_) => const FakeHtmlResponse(
        'server-detail-that-must-not-escape',
        statusCode: 401,
      ),
    );
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final ExchangeDirectoryGateway gateway = ExchangeDirectoryGateway(
      const HsaMailProfile(),
      dio: dio,
    );

    await expectLater(
      gateway.search(_credentials, 'Alice'),
      throwsA(
        isA<MailFailure>()
            .having(
              (MailFailure failure) => failure.kind,
              'kind',
              MailFailureKind.invalidCredentials,
            )
            .having(
              (MailFailure failure) => failure.toString(),
              'safe text',
              isNot(contains('server-detail')),
            ),
      ),
    );
  });

  test('rejects an unexpected EWS response code as protocol failure', () async {
    final FakeHtmlAdapter adapter = FakeHtmlAdapter(
      (_) => const FakeHtmlResponse('''
        <ResolveNamesResponseMessage>
          <ResponseCode>ErrorAccessDenied</ResponseCode>
        </ResolveNamesResponseMessage>
      '''),
    );
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final ExchangeDirectoryGateway gateway = ExchangeDirectoryGateway(
      const HsaMailProfile(),
      dio: dio,
    );

    await expectLater(
      gateway.search(_credentials, 'Alice'),
      throwsA(
        isA<MailFailure>().having(
          (MailFailure failure) => failure.kind,
          'kind',
          MailFailureKind.protocol,
        ),
      ),
    );
  });
}

const String _response = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
 xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
 xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
 <s:Body><m:ResolveNamesResponse><m:ResponseMessages>
  <m:ResolveNamesResponseMessage ResponseClass="Warning">
   <m:ResponseCode>ErrorNameResolutionMultipleResults</m:ResponseCode>
   <m:ResolutionSet TotalItemsInView="3">
    <t:Resolution><t:Mailbox><t:Name>Alice Example</t:Name>
     <t:EmailAddress>alice@hs-anhalt.de</t:EmailAddress></t:Mailbox></t:Resolution>
    <t:Resolution><t:Mailbox><t:Name>Duplicate Alice</t:Name>
     <t:EmailAddress>ALICE@hs-anhalt.de</t:EmailAddress></t:Mailbox></t:Resolution>
    <t:Resolution><t:Mailbox><t:Name>Bob Example</t:Name>
     <t:EmailAddress>bob@hs-anhalt.de</t:EmailAddress></t:Mailbox></t:Resolution>
   </m:ResolutionSet>
  </m:ResolveNamesResponseMessage>
 </m:ResponseMessages></m:ResolveNamesResponse></s:Body>
</s:Envelope>
''';
