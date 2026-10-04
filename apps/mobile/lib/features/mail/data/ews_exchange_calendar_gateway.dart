// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/exchange_calendar_event.dart';
import '../domain/exchange_calendar_gateway.dart';
import '../domain/hsa_mail_profile.dart';
import '../domain/mail_credentials.dart';
import 'exchange_calendar_parser.dart';

/// Minimal, read-only EWS client for the account's default calendar.
///
/// The endpoint and redirect policy are intentionally as strict as the
/// Moodle/Nextcloud clients: the Basic header contains the university password
/// and must never be replayed outside the exact pinned HTTPS endpoint.
class EwsExchangeCalendarGateway implements ExchangeCalendarGateway {
  EwsExchangeCalendarGateway({Dio? dio, this.profile = const HsaMailProfile()})
    : _dio = dio ?? _defaultDio();

  final Dio _dio;
  final HsaMailProfile profile;

  static Dio _defaultDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      followRedirects: false,
      validateStatus: (_) => true,
    ),
  );

  @override
  Future<List<ExchangeCalendarEvent>> fetchEvents(
    MailCredentials credentials, {
    required DateTime from,
    required DateTime to,
  }) async {
    final DateTime start = from.toUtc();
    final DateTime end = to.toUtc();
    if (!end.isAfter(start)) {
      throw const ExchangeCalendarFailure(
        ExchangeCalendarFailureKind.invalidRequest,
      );
    }
    final Uri uri = profile.exchangeCalendarUri;
    if (!profile.allowsExchangeCalendar(uri)) {
      throw const ExchangeCalendarFailure(
        ExchangeCalendarFailureKind.tlsOrHostRejected,
      );
    }

    final String authorization = base64Encode(
      utf8.encode('${credentials.emailAddress}:${credentials.password}'),
    );
    final Response<dynamic> response;
    try {
      response = await _dio.postUri<dynamic>(
        uri,
        data: _findItemEnvelope(start, end),
        options: Options(
          contentType: 'text/xml; charset=utf-8',
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: <String, String>{
            'Authorization': 'Basic $authorization',
            'SOAPAction':
                'http://schemas.microsoft.com/exchange/services/2006/messages/FindItem',
          },
        ),
      );
    } on DioException catch (error) {
      throw _mapDio(error);
    }

    final int status = response.statusCode ?? 0;
    if (status >= 300 && status < 400) {
      throw const ExchangeCalendarFailure(
        ExchangeCalendarFailureKind.tlsOrHostRejected,
      );
    }
    if (status == 401) {
      throw const ExchangeCalendarFailure(
        ExchangeCalendarFailureKind.invalidCredentials,
      );
    }
    if (status == 403) {
      throw const ExchangeCalendarFailure(
        ExchangeCalendarFailureKind.permissionDenied,
      );
    }
    if (status >= 500) {
      throw const ExchangeCalendarFailure(
        ExchangeCalendarFailureKind.serviceUnavailable,
      );
    }
    if (status < 200 || status >= 300 || response.data is! String) {
      throw const ExchangeCalendarFailure(
        ExchangeCalendarFailureKind.invalidResponse,
      );
    }
    try {
      return parseExchangeCalendarResponse(response.data as String);
    } on ExchangeCalendarResponseException {
      throw const ExchangeCalendarFailure(
        ExchangeCalendarFailureKind.invalidResponse,
      );
    }
  }

  ExchangeCalendarFailure _mapDio(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => const ExchangeCalendarFailure(
      ExchangeCalendarFailureKind.timeout,
    ),
    DioExceptionType.badCertificate => const ExchangeCalendarFailure(
      ExchangeCalendarFailureKind.tlsOrHostRejected,
    ),
    DioExceptionType.connectionError => const ExchangeCalendarFailure(
      ExchangeCalendarFailureKind.networkUnavailable,
    ),
    _ => const ExchangeCalendarFailure(
      ExchangeCalendarFailureKind.invalidResponse,
    ),
  };
}

String _findItemEnvelope(DateTime from, DateTime to) =>
    '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
    xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
  <s:Header>
    <t:RequestServerVersion Version="Exchange2016" />
    <t:TimeZoneContext><t:TimeZoneDefinition Id="UTC" /></t:TimeZoneContext>
  </s:Header>
  <s:Body>
    <m:FindItem Traversal="Shallow">
      <m:ItemShape>
        <t:BaseShape>IdOnly</t:BaseShape>
        <t:AdditionalProperties>
          <t:FieldURI FieldURI="item:Subject" />
          <t:FieldURI FieldURI="calendar:Start" />
          <t:FieldURI FieldURI="calendar:End" />
          <t:FieldURI FieldURI="calendar:IsAllDayEvent" />
          <t:FieldURI FieldURI="calendar:IsCancelled" />
          <t:FieldURI FieldURI="calendar:Location" />
        </t:AdditionalProperties>
      </m:ItemShape>
      <m:CalendarView StartDate="${from.toIso8601String()}"
          EndDate="${to.toIso8601String()}" MaxEntriesReturned="1000" />
      <m:ParentFolderIds><t:DistinguishedFolderId Id="calendar" /></m:ParentFolderIds>
    </m:FindItem>
  </s:Body>
</s:Envelope>
''';
